import Foundation
import CryptoKit
import Darwin

/// ZIP-only rewrites. Each operation builds and verifies a complete replacement
/// before atomically exchanging it with the original; existing sessions stay immutable.
enum ArchiveMutationService {
    private static let fm = FileManager.default
    private static func fail(_ message: String) -> ArchiveBrowserError { .message(message) }
    private static func validPath(_ path: String, rootAllowed: Bool = false) throws {
        if path.isEmpty && rootAllowed { return }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") && !$0.contains(":") && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }) else { throw fail("Enter a ZIP-relative path without empty, traversal, control or Windows drive components.") }
    }
    private static func metadata(_ url: URL) throws -> stat {
        var value = stat(); guard lstat(url.path,&value) == 0 else { throw fail("Cannot inspect \(url.path).") }; return value
    }
    private static func same(_ a: stat,_ b: stat) -> Bool {
        a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_size == b.st_size && a.st_mode == b.st_mode && a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec && a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
    }
    private static func fdMetadata(_ fd: Int32) throws -> stat {
        var value = stat(); guard fstat(fd,&value) == 0 else { throw fail("Cannot inspect opened archive.") }; return value
    }
    private static func stream(_ input: Int32, output: Int32? = nil, maxBytes: Int = 536_870_912) throws -> String {
        let before = try fdMetadata(input)
        guard before.st_mode & S_IFMT == S_IFREG, before.st_size >= 0, before.st_size <= maxBytes,
              lseek(input,0,SEEK_SET) >= 0 else { throw fail("Choose an ordinary file within the 512 MiB limit.") }
        var hash = SHA256(), buffer = [UInt8](repeating:0,count:262144), total = 0
        while true {
            let count = read(input,&buffer,buffer.count)
            if count < 0 { if errno == EINTR { continue }; throw fail("File read failed.") }
            if count == 0 { break }; total += count
            guard total <= maxBytes else { throw fail("File grew beyond its supported limit.") }
            hash.update(data:Data(buffer[0..<count]))
            if let output {
                var written = 0
                while written < count {
                    let amount = buffer.withUnsafeBytes { write(output,$0.baseAddress!.advanced(by:written),count-written) }
                    if amount < 0 && errno == EINTR { continue }
                    guard amount > 0 else { throw fail("Staged file write failed.") }; written += amount
                }
            }
        }
        guard same(before,try fdMetadata(input)), total == before.st_size else { throw fail("File changed while reading. No archive update committed.") }
        return hash.finalize().map{String(format:"%02x",$0)}.joined()
    }
    private static func openFile(_ url: URL) throws -> Int32 {
        guard url.isFileURL else { throw fail("Archive mutation requires local files; download a remote ZIP first.") }
        let fd = open(url.path,O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw fail("Cannot open local file: \(url.path)") }
        return fd
    }
    private static func digest(_ url: URL) throws -> String {
        let fd = try openFile(url); defer { close(fd) }; return try stream(fd)
    }
    private static func requireDirectory(_ tree: URL,_ path: String) throws -> URL {
        try validPath(path,rootAllowed:true)
        let result = path.isEmpty ? tree : tree.appendingPathComponent(path)
        guard try metadata(result).st_mode & S_IFMT == S_IFDIR else { throw fail("ZIP parent is not a directory: \(path)") }
        return result
    }
    private static func collision(_ parent: URL, name: String) throws -> URL? {
        let key = name.precomposedStringWithCanonicalMapping.lowercased()
        return try fm.contentsOfDirectory(at:parent,includingPropertiesForKeys:nil).first { $0.lastPathComponent.precomposedStringWithCanonicalMapping.lowercased() == key }
    }
    private static func copySource(_ source: URL,to destination: URL,items: inout Int,bytes: inout Int64) throws {
        guard source.isFileURL else { throw fail("Only local sources may be added to ZIP files.") }
        try validPath(source.lastPathComponent)
        items += 1; guard items <= 100_000 else { throw fail("Archive update exceeds 100,000 items.") }
        let before = try metadata(source)
        switch before.st_mode & S_IFMT {
        case S_IFDIR:
            try fm.createDirectory(at:destination,withIntermediateDirectories:false)
            for child in try fm.contentsOfDirectory(at:source,includingPropertiesForKeys:nil) { try copySource(child,to:destination.appendingPathComponent(child.lastPathComponent),items:&items,bytes:&bytes) }
        case S_IFREG:
            bytes += before.st_size; guard bytes <= 1_073_741_824 else { throw fail("Archive update exceeds the 1 GiB expanded limit.") }
            let input = try openFile(source); defer { close(input) }
            guard same(before,try fdMetadata(input)) else { throw fail("Source changed before copying.") }
            let output = open(destination.path,O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,0o600)
            guard output >= 0 else { throw fail("Cannot create staged member.") }; defer { close(output) }
            _ = try stream(input,output:output)
            guard fsync(output) == 0 else { throw fail("Cannot flush staged member.") }
        default: throw fail("Symbolic links and special files cannot be added to this ZIP.")
        }
        guard same(before,try metadata(source)) else { throw fail("Source changed while preparing the archive.") }
        try fm.setAttributes([.posixPermissions: NSNumber(value:before.st_mode & 0o777), .modificationDate: Date(timeIntervalSince1970:Double(before.st_mtimespec.tv_sec)+Double(before.st_mtimespec.tv_nsec)/1e9)],ofItemAtPath:destination.path)
    }
    private static func rewrite(_ session: ArchiveBrowserSession, edit: (URL) throws -> Void) throws -> ArchiveBrowserSession {
        guard session.isWritableZIP else { throw fail("This archive format is read-only. Only unencrypted ZIP archives can be modified.") }
        guard session.original.isFileURL else { throw fail("Remote archive modification is not supported; download the ZIP first.") }
        let expected = try digest(session.snapshot)
        guard try digest(session.original) == expected else { throw fail("The ZIP changed since it was opened. Reopen it before modifying members.") }
        let work = fm.temporaryDirectory.appendingPathComponent("native-zip-edit-"+UUID().uuidString)
        try fm.createDirectory(at:work,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);defer{try? fm.removeItem(at:work)}
        let tree = work.appendingPathComponent("contents"), candidate = work.appendingPathComponent("replacement.zip")
        try fm.createDirectory(at:tree,withIntermediateDirectories:false)
        try NativeOperations.unpack(archive:session.snapshot,destination:tree,tool:session.tool)
        try edit(tree)
        let children = try fm.contentsOfDirectory(at:tree,includingPropertiesForKeys:nil)
        if children.isEmpty {
            var empty = Data([0x50,0x4b,0x05,0x06]);empty.append(Data(repeating:0,count:18));try empty.write(to:candidate,options:.withoutOverwriting)
        } else { try NativeOperations.pack(sources:children,archive:candidate,tool:session.tool) }
        let replacement = try ArchiveBrowserSession(archive:candidate,tool:session.tool,originalLocation:session.original)
        replacement.displayOrigin=session.displayOrigin
        try replacement.testIntegrity()
        // A second extraction verifies safe complete member bytes before touching the original.
        let verify = work.appendingPathComponent("verify");try fm.createDirectory(at:verify,withIntermediateDirectories:false)
        try NativeOperations.unpack(archive:replacement.snapshot,destination:verify,tool:session.tool)
        guard try NativeOperations.compare(left:tree,right:verify,byContent:true).allSatisfy({ $0.status == "Equal content" || $0.status == "Directory" }) else { throw fail("Rebuilt ZIP does not match staged member bytes. Original preserved.") }
        try commit(candidate,original:session.original,expected:expected)
        return replacement
    }
    private static func commit(_ candidate: URL,original: URL,expected: String) throws {
        let parent = original.deletingLastPathComponent()
        let parentFD = open(parent.path,O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard parentFD >= 0 else { throw fail("Cannot open the ZIP parent directory.") };defer{close(parentFD)}
        let parentStamp = try fdMetadata(parentFD), name = original.lastPathComponent
        let current = openat(parentFD,name,O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard current >= 0 else { throw fail("Original ZIP disappeared or became a link.") };defer{close(current)}
        guard try stream(current) == expected else { throw fail("ZIP changed while preparing the update. Original preserved; reopen it.") }
        let currentStamp = try fdMetadata(current), stagedName = ".zip-update-"+UUID().uuidString
        let staged = openat(parentFD,stagedName,O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,0o600)
        guard staged >= 0 else { throw fail("Cannot stage a replacement beside the ZIP.") };defer{close(staged)}
        var keepRecovery = false
        defer { if !keepRecovery { unlinkat(parentFD,stagedName,0) } }
        let input = try openFile(candidate);defer{close(input)}
        let newDigest = try stream(input,output:staged)
        guard fchmod(staged,currentStamp.st_mode & 0o777) == 0, fsync(staged) == 0 else { throw fail("Cannot flush the replacement ZIP.") }
        let parentNow = try metadata(parent)
        var currentPath = stat()
        guard parentNow.st_dev == parentStamp.st_dev, parentNow.st_ino == parentStamp.st_ino,
              fstatat(parentFD,name,&currentPath,AT_SYMLINK_NOFOLLOW) == 0, same(currentStamp,currentPath), try stream(current) == expected else { throw fail("ZIP or parent changed before commit. Original preserved.") }
        guard renameatx_np(parentFD,stagedName,parentFD,name,UInt32(RENAME_SWAP)) == 0 else { throw fail("Atomic ZIP replacement failed; original preserved: \(String(cString:strerror(errno)))") }
        // If another process replaced the original in the final race window, swap
        // it back only while the new ZIP still occupies the original name.
        do {
            let saved = openat(parentFD,stagedName,O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard saved >= 0 else { throw fail("Cannot verify preserved ZIP after exchange.") };defer{close(saved)}
            guard try stream(saved) == expected else { throw fail("Original ZIP changed during atomic exchange.") }
            var installed = stat(), stagedStamp = try fdMetadata(staged)
            guard fstatat(parentFD,name,&installed,AT_SYMLINK_NOFOLLOW) == 0, installed.st_dev == stagedStamp.st_dev, installed.st_ino == stagedStamp.st_ino,
                  try stream(staged) == newDigest else { throw fail("Installed ZIP changed immediately after exchange.") }
            _ = fsync(parentFD)
        } catch {
            var installed = stat();let stagedStamp = try? fdMetadata(staged)
            if fstatat(parentFD,name,&installed,AT_SYMLINK_NOFOLLOW) == 0, let stagedStamp,
               installed.st_dev == stagedStamp.st_dev, installed.st_ino == stagedStamp.st_ino,
               renameatx_np(parentFD,stagedName,parentFD,name,UInt32(RENAME_SWAP)) == 0 {
                throw fail(error.localizedDescription + " The preserved original was restored.")
            }
            keepRecovery = true
            throw fail(error.localizedDescription + " Preserved ZIP remains at \(parent.appendingPathComponent(stagedName).path); automatic restore was unsafe.")
        }
    }
    static func add(session: ArchiveBrowserSession,sources: [URL],at path: String,overwrite: Bool = false) throws -> ArchiveBrowserSession {
        guard !sources.isEmpty else { throw fail("Select local files or folders to add.") }
        return try rewrite(session) { tree in
            let target = try requireDirectory(tree,path);var names = Set<String>(),items = 0,bytes:Int64 = 0
            for source in sources {
                try validPath(source.lastPathComponent)
                guard names.insert(source.lastPathComponent.precomposedStringWithCanonicalMapping.lowercased()).inserted else { throw fail("Selected sources have colliding ZIP names.") }
                if let existing = try collision(target,name:source.lastPathComponent) {
                    guard overwrite else { throw fail("ZIP member already exists: \(source.lastPathComponent)") };try fm.removeItem(at:existing)
                }
                try copySource(source,to:target.appendingPathComponent(source.lastPathComponent),items:&items,bytes:&bytes)
            }
        }
    }
    static func delete(session: ArchiveBrowserSession,paths: [String]) throws -> ArchiveBrowserSession {
        let selected = try session.selectedRoots(paths)
        return try rewrite(session) { tree in for path in selected { try validPath(path);try fm.removeItem(at:tree.appendingPathComponent(path)) } }
    }
    static func rename(session: ArchiveBrowserSession,path: String,toName: String,overwrite: Bool = false) throws -> ArchiveBrowserSession {
        try validPath(path);try validPath(toName)
        guard !toName.contains("/"), session.node(path) != nil else { throw fail("Choose an existing member and a single new name.") }
        return try rewrite(session) { tree in
            let parentPath = (path as NSString).deletingLastPathComponent,parent = try requireDirectory(tree,parentPath)
            let source = tree.appendingPathComponent(path),target = parent.appendingPathComponent(toName)
            guard source.path != target.path else { throw fail("Choose a different member name.") }
            if let existing = try collision(parent,name:toName), !same(try metadata(existing),try metadata(source)) {
                guard overwrite else { throw fail("Destination member exists.") };try fm.removeItem(at:existing)
            }
            // A temporary hop permits case-only renames on default macOS volumes.
            let temporary = parent.appendingPathComponent(".rename-"+UUID().uuidString)
            try fm.moveItem(at:source,to:temporary)
            do { try fm.moveItem(at:temporary,to:target) }
            catch { try? fm.moveItem(at:temporary,to:source); throw error }
        }
    }
    static func makeDirectory(session: ArchiveBrowserSession,path: String) throws -> ArchiveBrowserSession {
        try validPath(path)
        return try rewrite(session) { tree in
            let parent = try requireDirectory(tree,(path as NSString).deletingLastPathComponent),name = (path as NSString).lastPathComponent
            guard try collision(parent,name:name) == nil else { throw fail("ZIP member already exists.") }
            try fm.createDirectory(at:parent.appendingPathComponent(name),withIntermediateDirectories:false)
        }
    }
    static func update(session: ArchiveBrowserSession,path: String,from localFile: URL) throws -> ArchiveBrowserSession {
        try validPath(path)
        guard session.node(path)?.isDirectory == false, try metadata(localFile).st_mode & S_IFMT == S_IFREG else { throw fail("Updating requires an existing regular ZIP member and a regular local file.") }
        return try rewrite(session) { tree in
            let destination = tree.appendingPathComponent(path);try fm.removeItem(at:destination)
            var items=0,bytes:Int64=0;try copySource(localFile,to:destination,items:&items,bytes:&bytes)
        }
    }
}
