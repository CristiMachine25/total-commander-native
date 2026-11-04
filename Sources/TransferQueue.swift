import AppKit
import Darwin

enum TransferCollisionPolicy: String, CaseIterable {
    case ask = "Ask", skip = "Skip existing", replace = "Replace existing", rename = "Keep both", cancel = "Cancel job"
}
struct NativeTransferOptions: Equatable {
    var preserveDirectoryDates = true
    var preserveFileDates = true
    var preservePermissions = true
    var verifyAfterCopy = false
    var bufferSizeKB = 1024
    var bufferSize: Int { min(16384,max(64,bufferSizeKB)) * 1024 }
}
struct TransferConflict { let source: URL; let destination: URL }
struct TransferProgress {
    let id: UUID
    var state: String
    var currentPath: String
    var copiedBytes: UInt64
    var totalBytes: UInt64
    var completedItems: Int
    var skippedItems: Int
}
struct TransferResult {
    let progress: TransferProgress
    let cancelled: Bool
    let errors: [String]
    let warnings: [String]
    var summary: String {
        "\(progress.state): \(progress.completedItems) completed, \(progress.skippedItems) skipped. " +
        (cancelled ? "Completed changes remain; unfinished sources are retained." : "") +
        (errors.isEmpty ? "" : "\n" + errors.joined(separator: "\n")) +
        (warnings.isEmpty ? "" : "\n" + warnings.joined(separator: "\n"))
    }
}
final class TransferCancellation {
    private let lock = NSLock()
    private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}
enum TransferError: LocalizedError {
    case message(String), cancelled
    var errorDescription: String? { switch self { case .message(let value): return value; case .cancelled: return "Transfer cancelled." } }
}

/// Synchronous worker, used by the serialized queue and isolated fixture tests.
final class NativeTransferEngine {
    private let fm = FileManager.default
    private let cancellation: TransferCancellation
    private let policy: TransferCollisionPolicy
    private let resolve: ((TransferConflict) -> TransferCollisionPolicy)?
    private let update: (TransferProgress) -> Void
    private var progress: TransferProgress
    private var warnings: [String] = []
    private let move: Bool
    private let options: NativeTransferOptions
    private var lastUpdate = Date.distantPast
    private var destinationDirectories: [String: stat] = [:]
    private var destinationIsCanonical = false

    init(id: UUID = UUID(), move: Bool, policy: TransferCollisionPolicy,
         options: NativeTransferOptions = NativeTransferOptions(),
         cancellation: TransferCancellation = TransferCancellation(),
         resolve: ((TransferConflict) -> TransferCollisionPolicy)? = nil,
         update: @escaping (TransferProgress) -> Void = { _ in }) {
        self.options = options; self.move = move; self.policy = policy; self.cancellation = cancellation; self.resolve = resolve; self.update = update
        progress = TransferProgress(id:id,state:"Preparing",currentPath:"",copiedBytes:0,totalBytes:0,completedItems:0,skippedItems:0)
    }
    private func checkCancellation() throws { if cancellation.isCancelled { throw TransferError.cancelled } }
    private func emit(force: Bool = false) {
        if force || Date().timeIntervalSince(lastUpdate) >= 0.1 { lastUpdate = Date(); update(progress) }
    }
    private func info(_ url: URL) throws -> stat {
        var result = stat()
        guard lstat(url.path, &result) == 0 else { throw TransferError.message("\(url.path): \(String(cString:strerror(errno)))") }
        return result
    }
    private func existing(_ url: URL) -> stat? { try? info(url) }
    private func canonicalDirectory(_ url: URL) throws -> URL {
        guard let path = realpath(url.path,nil) else { throw TransferError.message("Cannot resolve directory: \(url.path)") }
        defer { free(path) }
        let result = URL(fileURLWithPath:String(cString:path))
        guard try info(result).st_mode & S_IFMT == S_IFDIR else { throw TransferError.message("Not a directory: \(url.path)") }
        return result
    }
    private func sameIdentity(_ a: stat, _ b: stat) -> Bool { a.st_dev == b.st_dev && a.st_ino == b.st_ino }
    private func unchanged(_ a: stat, _ b: stat) -> Bool {
        sameIdentity(a,b) && a.st_size == b.st_size && a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec
    }
    // Resolve each destination ancestor from an opened root without following links.
    // Remember identities so renaming/replacing a previously visited directory fails.
    private func destinationParent(_ target: URL) throws -> Int32 {
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw TransferError.message("Cannot open filesystem root.") }
        do {
            var path = ""
            for part in target.deletingLastPathComponent().path.split(separator: "/") {
                path += "/" + part
                let next = openat(fd, String(part), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else { throw TransferError.message("Destination ancestor changed or became a link: \(path)") }
                var current = stat()
                guard fstat(next, &current) == 0 else { close(next); throw TransferError.message("Cannot inspect destination ancestor.") }
                if let expected = destinationDirectories[path], !sameIdentity(current, expected) {
                    close(next); throw TransferError.message("Destination ancestor was replaced: \(path)")
                }
                destinationDirectories[path] = current
                close(fd); fd = next
            }
            return fd
        } catch { close(fd); throw error }
    }
    private func revalidateParent(_ target: URL, fd: Int32) throws {
        let fresh = try destinationParent(target); defer { close(fresh) }
        var a = stat(), b = stat()
        guard fstat(fresh, &a) == 0, fstat(fd, &b) == 0, sameIdentity(a,b) else { throw TransferError.message("Destination parent changed: \(target.path)") }
    }
    private func atInfo(_ fd: Int32, _ name: String) throws -> stat? {
        var value = stat()
        if fstatat(fd,name,&value,AT_SYMLINK_NOFOLLOW) == 0 { return value }
        if errno == ENOENT { return nil }
        throw TransferError.message("Cannot inspect destination: \(name)")
    }
    private func removeAt(_ fd: Int32, _ name: String) throws {
        guard let value = try atInfo(fd,name) else { return }
        if value.st_mode & S_IFMT == S_IFDIR {
            let child = openat(fd,name,O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard child >= 0 else { throw TransferError.message("Cannot clean private directory: \(name)") }
            defer { close(child) }
            guard let stream = fdopendir(dup(child)) else { throw TransferError.message("Cannot enumerate private directory.") }
            defer { closedir(stream) }
            while let item = readdir(stream) {
                let leaf = withUnsafePointer(to:&item.pointee.d_name) { pointer in
                    pointer.withMemoryRebound(to:CChar.self,capacity:Int(item.pointee.d_namlen)+1) { String(cString:$0) }
                }
                if leaf != "." && leaf != ".." { try removeAt(child,leaf) }
            }
            guard unlinkat(fd,name,AT_REMOVEDIR) == 0 else { throw TransferError.message("Cannot remove private directory: \(name)") }
        } else {
            guard unlinkat(fd,name,0) == 0 else { throw TransferError.message("Cannot remove private item: \(name)") }
        }
    }
    private func count(_ url: URL) throws -> UInt64 {
        try checkCancellation()
        let value = try info(url)
        switch value.st_mode & S_IFMT {
        case S_IFREG: return UInt64(max(0,value.st_size))
        case S_IFLNK: return 0
        case S_IFDIR:
            return try fm.contentsOfDirectory(at:url,includingPropertiesForKeys:nil).reduce(UInt64(0)) { try $0 + count($1) }
        default: throw TransferError.message("Special files are not supported: \(url.path)")
        }
    }
    func run(sources: [URL], destination: URL) -> TransferResult {
        do {
            guard !sources.isEmpty else { throw TransferError.message("No transfer sources selected.") }
            let root = destinationIsCanonical ? destination : try canonicalDirectory(destination)
            let initialParent = try destinationParent(root.appendingPathComponent(".identity-check")); close(initialParent)
            var canonicalSources: [URL] = []
            var sourceNames = Set<String>()
            for source in sources {
                try checkCancellation()
                let source = try canonicalDirectory(source.deletingLastPathComponent()).appendingPathComponent(source.lastPathComponent)
                let metadata = try info(source)
                let target = root.appendingPathComponent(source.lastPathComponent)
                guard sourceNames.insert(source.lastPathComponent.precomposedStringWithCanonicalMapping.lowercased()).inserted else { throw TransferError.message("Selected items have conflicting destination names.") }
                if source.path == target.path || existing(target).map({sameIdentity(metadata,$0)}) == true { throw TransferError.message("Cannot transfer an item onto itself: \(source.path)") }
                if metadata.st_mode & S_IFMT == S_IFDIR {
                    guard root.path != source.path, !root.path.hasPrefix(source.path + "/") else { throw TransferError.message("Cannot transfer a folder into itself or its descendants.") }
                }
                for previous in canonicalSources where source.path.hasPrefix(previous.path + "/") || previous.path.hasPrefix(source.path + "/") { throw TransferError.message("Do not select a folder and its descendants together.") }
                canonicalSources.append(source)
                progress.totalBytes += try count(source)
            }
            progress.state = move ? "Moving" : "Copying"; emit(force:true)
            for source in canonicalSources { _ = try transfer(source, to:root.appendingPathComponent(source.lastPathComponent)) }
            progress.state = "Completed"; emit(force:true)
            return TransferResult(progress:progress,cancelled:false,errors:[],warnings:warnings)
        } catch {
            let cancelled = cancellation.isCancelled || (error as? TransferError).map { if case .cancelled = $0 { return true }; return false } == true
            progress.state = cancelled ? "Cancelled" : "Failed"; emit(force:true)
            return TransferResult(progress:progress,cancelled:cancelled,errors:cancelled ? [] : [error.localizedDescription],warnings:warnings)
        }
    }
    private func uniqueTarget(_ target: URL) -> URL {
        let ext = target.pathExtension, base = ext.isEmpty ? target.lastPathComponent : target.deletingPathExtension().lastPathComponent
        var index = 2
        while true {
            let leaf = base + " (\(index))" + (ext.isEmpty ? "" : "." + ext)
            let candidate = target.deletingLastPathComponent().appendingPathComponent(leaf)
            if existing(candidate) == nil { return candidate }
            index += 1
        }
    }
    @discardableResult private func transfer(_ source: URL, to initialTarget: URL) throws -> Bool {
        try checkCancellation()
        let parentFD = try destinationParent(initialTarget); defer { close(parentFD) }
        progress.currentPath = source.path; emit()
        try revalidateParent(initialTarget, fd:parentFD)
        let original = try info(source), sourceType = original.st_mode & S_IFMT
        var target = initialTarget, collision = try atInfo(parentFD,initialTarget.lastPathComponent)
        // Never traverse a destination link while merging directories. A link is
        // a leaf collision and requires an explicit replace or keep-both choice.
        if sourceType == S_IFDIR, let collision, collision.st_mode & S_IFMT == S_IFDIR, policy != .rename {
            return try merge(source, target:target, original:original, created:false)
        }
        if let current = collision {
            if sameIdentity(original,current) { throw TransferError.message("Source and target identify the same file: \(source.path)") }
            let choice = policy == .ask ? (resolve?(TransferConflict(source:source,destination:target)) ?? .cancel) : policy
            try checkCancellation()
            switch choice {
            case .skip: progress.skippedItems += 1; emit(force:true); return false
            case .rename: target = uniqueTarget(target); collision = nil
            case .replace: break
            case .ask, .cancel: cancellation.cancel(); throw TransferError.cancelled
            }
        }
        switch sourceType {
        case S_IFDIR:
            if let collision {
                // Type-conflict replacement builds the complete folder privately.
                let snapshot = try snapshotTree(source)
                let stage = target.deletingLastPathComponent().appendingPathComponent(".transfer-" + UUID().uuidString)
                try revalidateParent(target, fd:parentFD)
                guard mkdirat(parentFD,stage.lastPathComponent,0o700) == 0 else { throw TransferError.message("Cannot create private staging directory.") }
                do {
                    // A replacement directory is copied first; moving sources
                    // during staging would make a cancelled job lose its source.
                    let copyEngine = NativeTransferEngine(move:false,policy:.replace,options:options,cancellation:cancellation,update:{ _ in })
                    let stageFD = try destinationParent(stage.appendingPathComponent(".identity-check")); close(stageFD)
                    copyEngine.destinationDirectories = destinationDirectories
                    copyEngine.destinationIsCanonical = true
                    let children = try fm.contentsOfDirectory(at:source,includingPropertiesForKeys:nil)
                    if !children.isEmpty {
                        let result = copyEngine.run(sources:children,destination:stage)
                        guard result.errors.isEmpty, !result.cancelled else { if result.cancelled { throw TransferError.cancelled }; throw TransferError.message(result.summary) }
                        progress.copiedBytes += result.progress.copiedBytes
                    }
                    let metadataFD = try destinationParent(stage.appendingPathComponent(".identity-check"))
                    applyDirectoryMetadata(original,fd:metadataFD,path:stage.path);close(metadataFD)
                    try checkCancellation(); try commit(stage:stage,target:target,expected:collision,parentFD:parentFD)
                    if move { try removeSnapshot(snapshot) }
                    progress.completedItems += 1; emit(force:true); return true
                } catch { try? removeAt(parentFD,stage.lastPathComponent); throw error }
            }
            try revalidateParent(target, fd:parentFD)
            guard mkdirat(parentFD,target.lastPathComponent,0o755) == 0 else { throw TransferError.message("Cannot create destination directory.") }
            return try merge(source,target:target,original:original,created:true)
        case S_IFREG:
            try copyRegular(source,target:target,original:original,expected:collision,parentFD:parentFD)
        case S_IFLNK:
            let link = try fm.destinationOfSymbolicLink(atPath:source.path)
            let stage = target.deletingLastPathComponent().appendingPathComponent(".transfer-" + UUID().uuidString)
            defer { try? removeAt(parentFD,stage.lastPathComponent) }
            try revalidateParent(target, fd:parentFD)
            guard symlinkat(link,parentFD,stage.lastPathComponent) == 0 else { throw TransferError.message("Cannot stage symbolic link.") }
            try checkCancellation(); try commit(stage:stage,target:target,expected:collision,parentFD:parentFD)
            if move { guard sameIdentity(original,try info(source)) else { throw TransferError.message("Source link changed; retained: \(source.path)") }; try fm.removeItem(at:source) }
        default: throw TransferError.message("Special files are unsupported: \(source.path)")
        }
        progress.completedItems += 1; emit(force:true); return true
    }
    private func snapshotTree(_ root: URL) throws -> [(URL, stat)] {
        try checkCancellation()
        let metadata = try info(root)
        var result: [(URL, stat)] = [(root, metadata)]
        if metadata.st_mode & S_IFMT == S_IFDIR {
            for child in try fm.contentsOfDirectory(at:root,includingPropertiesForKeys:nil) { result += try snapshotTree(child) }
        }
        return result
    }
    private func removeSnapshot(_ snapshot: [(URL, stat)]) throws {
        // Validate every known entry before deleting any source. Never recurse
        // into newly arrived contents during cleanup of a staged directory move.
        for (url, expected) in snapshot {
            guard unchanged(expected,try info(url)) else { throw TransferError.message("Copied directory, but a changed source was retained: \(url.path)") }
        }
        for (url, expected) in snapshot.reversed() {
            if expected.st_mode & S_IFMT == S_IFDIR {
                guard sameIdentity(expected,try info(url)), rmdir(url.path) == 0 else { throw TransferError.message("Copied directory; source folder remains: \(url.path)") }
            } else {
                guard unchanged(expected,try info(url)), unlink(url.path) == 0 else { throw TransferError.message("Copied directory; source entry remains: \(url.path)") }
            }
        }
    }
    private func merge(_ source: URL, target: URL, original: stat, created: Bool) throws -> Bool {
        guard try info(target).st_mode & S_IFMT == S_IFDIR else { throw TransferError.message("Destination directory changed: \(target.path)") }
        let directoryFD = try destinationParent(target.appendingPathComponent(".identity-check")); defer { close(directoryFD) }
        var allMoved = true
        for child in try fm.contentsOfDirectory(at:source,includingPropertiesForKeys:nil).sorted(by:{$0.lastPathComponent < $1.lastPathComponent}) {
            if !(try transfer(child,to:target.appendingPathComponent(child.lastPathComponent))) { allMoved = false }
        }
        try checkCancellation()
        if created {
            try revalidateParent(target.appendingPathComponent(".identity-check"), fd:directoryFD)
            applyDirectoryMetadata(original,fd:directoryFD,path:target.path)
        }
        if move && allMoved {
            // rmdir refuses newly arrived/unprocessed contents instead of removing
            // them recursively after the original enumeration.
            guard rmdir(source.path) == 0 else { throw TransferError.message("Transferred contents, but source folder remains: \(source.path) (\(String(cString:strerror(errno))))") }
        }
        progress.completedItems += 1; emit(force:true); return allMoved
    }
    private func applyDirectoryMetadata(_ original:stat,fd:Int32,path:String) {
        if options.preservePermissions,fchmod(fd,original.st_mode & 0o7777) != 0 {warnings.append("Folder permissions were not preserved: "+path)}
        if options.preserveDirectoryDates {
            var times=[original.st_atimespec,original.st_mtimespec]
            if futimens(fd,&times) != 0 {warnings.append("Folder timestamps were not preserved: "+path)}
        }
    }
    private func verifyContents(input:Int32,output:Int32,size:off_t)throws {
        progress.state="Verifying";emit(force:true)
        defer {progress.state=move ? "Moving" : "Copying";emit(force:true)}
        var original=[UInt8](repeating:0,count:options.bufferSize),copied=original
        var offset:off_t=0
        func readChunk(_ fd:Int32,_ bytes:inout [UInt8],_ count:Int,_ offset:off_t)throws->Int {
            var total=0
            while total<count {
                try checkCancellation()
                let amount=bytes.withUnsafeMutableBytes {pread(fd,$0.baseAddress!.advanced(by:total),count-total,offset+off_t(total))}
                if amount<0 {if errno==EINTR{continue};throw TransferError.message("Could not read data for copy verification.")}
                if amount==0{break};total += amount
            }
            return total
        }
        while offset<size {
            try checkCancellation();let count=Int(min(off_t(original.count),size-offset))
            let left=try readChunk(input,&original,count,offset),right=try readChunk(output,&copied,count,offset)
            guard left==count,right==count,original.prefix(count).elementsEqual(copied.prefix(count)) else {throw TransferError.message("Copy verification failed; destination was not committed and source was retained.")}
            offset += off_t(count)
        }
        var copiedStat=stat()
        guard fstat(output,&copiedStat)==0,copiedStat.st_size==size else{throw TransferError.message("Copy verification found a different destination size; source retained.")}
    }
    private func copyRegular(_ source: URL, target: URL, original: stat, expected: stat?, parentFD: Int32) throws {
        let input = Darwin.open(source.path,O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard input >= 0 else { throw TransferError.message("Cannot read \(source.path): \(String(cString:strerror(errno)))") }
        defer { Darwin.close(input) }
        var opened = stat()
        guard fstat(input,&opened) == 0, opened.st_mode & S_IFMT == S_IFREG, sameIdentity(original,opened) else { throw TransferError.message("Source changed before reading: \(source.path)") }
        let stage = target.deletingLastPathComponent().appendingPathComponent(".transfer-" + UUID().uuidString)
        try revalidateParent(target, fd:parentFD)
        let output = openat(parentFD,stage.lastPathComponent,O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,0o600)
        guard output >= 0 else { throw TransferError.message("Cannot create staged destination: \(String(cString:strerror(errno)))") }
        defer { Darwin.close(output); try? removeAt(parentFD,stage.lastPathComponent) }
        var buffer = [UInt8](repeating:0,count:options.bufferSize)
        while true {
            try checkCancellation()
            let amount = Darwin.read(input,&buffer,buffer.count)
            if amount == 0 { break }
            if amount < 0 { if errno == EINTR { continue }; throw TransferError.message("Read failed: \(String(cString:strerror(errno)))") }
            var written = 0
            while written < amount {
                let count = buffer.withUnsafeBytes { Darwin.write(output,$0.baseAddress!.advanced(by:written),amount-written) }
                if count < 0 { if errno == EINTR { continue }; throw TransferError.message("Write failed: \(String(cString:strerror(errno)))") }
                if count == 0 { throw TransferError.message("Write made no progress.") }
                written += count
            }
            progress.copiedBytes += UInt64(amount); emit()
        }
        var after = stat()
        guard fstat(input,&after) == 0, unchanged(opened,after) else { throw TransferError.message("Source changed while being copied; destination was not committed: \(source.path)") }
        // Keep extended attributes regardless of POSIX permission/date choices. The
        // legacy all-metadata path preserves the existing default copy behavior.
        var metadataFlags=copyfile_flags_t(COPYFILE_XATTR)
        if options.preservePermissions {metadataFlags |= copyfile_flags_t(COPYFILE_ACL)}
        if options.preservePermissions && options.preserveFileDates {metadataFlags |= copyfile_flags_t(COPYFILE_STAT)}
        if fcopyfile(input,output,nil,metadataFlags) != 0 {warnings.append("Metadata was not fully preserved: \(source.path)")}
        if options.preservePermissions && !options.preserveFileDates, fchmod(output,opened.st_mode & 0o7777) != 0 {warnings.append("Permissions were not preserved: \(source.path)")}
        if options.preserveFileDates && !options.preservePermissions {
            var times=[opened.st_atimespec,opened.st_mtimespec]
            if futimens(output,&times) != 0 {warnings.append("Timestamps were not preserved: \(source.path)")}
        }
        guard fsync(output) == 0 else { throw TransferError.message("Could not flush staged data: \(String(cString:strerror(errno)))") }
        if options.verifyAfterCopy {
            try verifyContents(input:input,output:output,size:opened.st_size)
            guard fstat(input,&after)==0,unchanged(opened,after) else {throw TransferError.message("Source changed during verification; source and old destination retained.")}
        }
        try checkCancellation(); try commit(stage:stage,target:target,expected:expected,parentFD:parentFD)
        if move {
            guard unchanged(opened,try info(source)) else { throw TransferError.message("Copied, but source changed and was retained: \(source.path)") }
            guard unlink(source.path) == 0 else { throw TransferError.message("Copied, but source could not be removed: \(source.path)") }
        }
    }
    private func renameExclusive(_ fd: Int32, _ from: String, _ to: String) throws {
        guard renameatx_np(fd,from,fd,to,UInt32(RENAME_EXCL)) == 0 else { throw TransferError.message("Cannot commit \(to): \(String(cString:strerror(errno)))") }
    }
    private func commit(stage: URL, target: URL, expected: stat?, parentFD: Int32) throws {
        try revalidateParent(target, fd:parentFD)
        let name = target.lastPathComponent
        if let expected {
            guard let current = try atInfo(parentFD,name), unchanged(expected,current) else { throw TransferError.message("Destination changed while copying; it was not replaced: \(target.path)") }
            let backup = ".transfer-backup-" + UUID().uuidString
            try renameExclusive(parentFD,name,backup)
            do {
                guard let saved = try atInfo(parentFD,backup), sameIdentity(expected,saved) else { throw TransferError.message("Destination identity changed before replacement.") }
                try renameExclusive(parentFD,stage.lastPathComponent,name)
            } catch {
                do { try renameExclusive(parentFD,backup,name) }
                catch { warnings.append("Original destination retained as \(backup) in the opened destination directory; restore it manually.") }
                throw error
            }
            do { try removeAt(parentFD,backup) }
            catch { warnings.append("Replacement succeeded; previous item remains as \(backup) in the destination directory.") }
        } else { try renameExclusive(parentFD,stage.lastPathComponent,name) }
    }

}

final class NativeTransferQueue {
    static let shared = NativeTransferQueue()
    private let worker = DispatchQueue(label:"native.commander.transfers",qos:.userInitiated)
    private let lock = NSLock()
    private var cancellations: [UUID: TransferCancellation] = [:]
    var hasPendingJobs: Bool { lock.lock(); defer { lock.unlock() }; return !cancellations.isEmpty }
    @discardableResult func enqueue(sources: [URL], destination: URL, move: Bool,
                                   policy: TransferCollisionPolicy = .ask,
                                   options: NativeTransferOptions = NativeTransferOptions(),
                                   resolve: ((TransferConflict) -> TransferCollisionPolicy)? = nil,
                                   callbackQueue: DispatchQueue = .main,
                                   onUpdate: @escaping (TransferProgress) -> Void = { _ in },
                                   completion: @escaping (TransferResult) -> Void = { _ in }) -> UUID {
        let id = UUID(), cancellation = TransferCancellation()
        lock.lock(); cancellations[id] = cancellation; lock.unlock()
        let initial = TransferProgress(id:id,state:"Queued",currentPath:destination.path,copiedBytes:0,totalBytes:0,completedItems:0,skippedItems:0)
        callbackQueue.async { onUpdate(initial) }
        worker.async { [self] in
            let engine = NativeTransferEngine(id:id,move:move,policy:policy,options:options,cancellation:cancellation,resolve:resolve,update: { value in callbackQueue.async { onUpdate(value) } })
            let result = engine.run(sources:sources,destination:destination)
            lock.lock(); cancellations.removeValue(forKey:id); lock.unlock()
            callbackQueue.async { completion(result) }
        }
        return id
    }
    func cancel(_ id: UUID) { lock.lock(); let value = cancellations[id]; lock.unlock(); value?.cancel() }
}

final class TransferQueueController: NSWindowController, NSWindowDelegate {
    private static let shared = TransferQueueController()
    static var hasPendingJobs: Bool { NativeTransferQueue.shared.hasPendingJobs }
    private let list = NSTextView()
    private let progressBar = NSProgressIndicator()
    private let detail = NSTextField(labelWithString: "No pending transfers")
    private let jobs = NSPopUpButton()
    private var order: [UUID] = []
    private var states: [UUID: TransferProgress] = [:]
    private var results: [UUID: TransferResult] = [:]

    /// May be called from the app after its destination confirmation. The policy
    /// chooser and conflicts run on the main thread; data movement stays serial.
    static func enqueue(sources: [URL], destination: URL, move: Bool,
                        options: NativeTransferOptions = NativeTransferOptions(),
                        defaultPolicy: TransferCollisionPolicy = .ask,
                        confirmPolicy: Bool = true,
                        confirmOverwrite: Bool = true,
                        completion: @escaping (TransferResult) -> Void = { _ in }) {
        let controller = shared
        let alert = NSAlert()
        alert.messageText = move ? "Queue move" : "Queue copy"
        alert.informativeText = "\(sources.count) selected item(s) → \(destination.path)\nExisting folders merge; this policy applies to conflicting files or item types."
        let policy = NSPopUpButton(frame:NSRect(x:0,y:0,width:300,height:28))
        let choices: [TransferCollisionPolicy] = [.ask,.skip,.replace,.rename]
        policy.addItems(withTitles:choices.map(\.rawValue))
        policy.selectItem(at:choices.firstIndex(of:defaultPolicy) ?? 0)
        let verify=NSButton(checkboxWithTitle:"Verify copied files by reading them back",target:nil,action:nil)
        verify.state=options.verifyAfterCopy ? .on : .off
        let accessory=NSStackView(views:[policy,verify]);accessory.orientation = .vertical;accessory.alignment = .leading;accessory.spacing=10;accessory.frame=NSRect(x:0,y:0,width:360,height:65)
        alert.accessoryView=accessory
        alert.addButton(withTitle:"Add to queue"); alert.addButton(withTitle:"Cancel")
        if confirmPolicy {guard alert.runModal() == .alertFirstButtonReturn else { return }}
        controller.showWindow(nil); controller.window?.makeKeyAndOrderFront(nil)
        var rememberedChoice: TransferCollisionPolicy?
        var operationOptions=options;operationOptions.verifyAfterCopy=verify.state == .on
        var selectedPolicy=choices[policy.indexOfSelectedItem]
        if selectedPolicy == .ask && !confirmOverwrite {selectedPolicy = .replace}
        if selectedPolicy == .replace && confirmOverwrite {selectedPolicy = .ask}
        let id = NativeTransferQueue.shared.enqueue(sources:sources,destination:destination,move:move,policy:selectedPolicy,options:operationOptions,resolve:{ conflict in
            if let rememberedChoice { return rememberedChoice }
            var decision = TransferCollisionPolicy.cancel
            DispatchQueue.main.sync {
                let dialog = NSAlert()
                dialog.messageText = "Destination already exists"
                dialog.informativeText = "Source: \(conflict.source.path)\nDestination: \(conflict.destination.path)\nReplace discards the existing destination after the new item is committed."
                for title in ["Skip", "Replace", "Keep both", "Cancel job"] { dialog.addButton(withTitle:title) }
                let applyAll = NSButton(checkboxWithTitle:"Use this choice for remaining conflicts",target:nil,action:nil)
                dialog.accessoryView = applyAll
                switch dialog.runModal() {
                case .alertFirstButtonReturn: decision = .skip
                case .alertSecondButtonReturn: decision = .replace
                case .alertThirdButtonReturn: decision = .rename
                default: decision = .cancel
                }
                if applyAll.state == .on { rememberedChoice = decision }
            }
            return decision
        },onUpdate:{ value in controller.states[value.id] = value; controller.refresh() },completion:{ result in
            controller.results[result.progress.id] = result
            controller.states[result.progress.id] = result.progress
            controller.refresh(); completion(result)
        })
        controller.order.append(id)
        controller.states[id] = TransferProgress(id:id,state:"Queued",currentPath:destination.path,copiedBytes:0,totalBytes:0,completedItems:0,skippedItems:0)
        controller.refresh()
    }
    private init() {
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:740,height:420),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        super.init(window:window)
        window.title = "Transfer queue"; window.minSize = NSSize(width:560,height:320); window.isReleasedWhenClosed = false; window.delegate = self
        let cancel = NSButton(title:"Cancel selected job",target:self,action:#selector(cancelSelected))
        jobs.target = self; jobs.action = #selector(selectionChanged)
        let row = NSStackView(views:[jobs,cancel]); row.spacing = 8
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        list.isEditable = false; list.isSelectable = true; list.font = .monospacedSystemFont(ofSize:11,weight:.regular)
        list.isVerticallyResizable = true; list.autoresizingMask = [.width]; list.textContainer?.widthTracksTextView = true
        list.maxSize = NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
        scroll.documentView = list
        detail.lineBreakMode = .byTruncatingMiddle
        progressBar.isIndeterminate = false; progressBar.minValue = 0; progressBar.maxValue = 1; progressBar.style = .bar
        let stack = NSStackView(views:[row,detail,progressBar,scroll]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        window.contentView!.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor,constant:12),stack.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor,constant:-12),stack.topAnchor.constraint(equalTo:window.contentView!.topAnchor,constant:12),stack.bottomAnchor.constraint(equalTo:window.contentView!.bottomAnchor,constant:-12),row.widthAnchor.constraint(equalTo:stack.widthAnchor),detail.widthAnchor.constraint(equalTo:stack.widthAnchor),progressBar.widthAnchor.constraint(equalTo:stack.widthAnchor),scroll.widthAnchor.constraint(equalTo:stack.widthAnchor),scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:180),jobs.widthAnchor.constraint(greaterThanOrEqualToConstant:350)])
        window.center()
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) unsupported") }
    private func refresh() {
        let selected = jobs.indexOfSelectedItem
        jobs.removeAllItems()
        jobs.addItems(withTitles:order.enumerated().map { index,id in "Job \(index + 1): \(states[id]?.state ?? "Queued")" })
        if order.indices.contains(selected) { jobs.selectItem(at:selected) }
        else if !order.isEmpty { jobs.selectItem(at:order.count - 1) }
        list.string = order.enumerated().map { index,id in
            if let result = results[id] { return "Job \(index + 1) — " + result.summary }
            guard let state = states[id] else { return "" }
            return "Job \(index + 1) — \(state.state)\n\(state.currentPath)\n\(state.completedItems) completed, \(state.skippedItems) skipped; \(state.copiedBytes)/\(state.totalBytes) bytes processed"
        }.joined(separator:"\n\n")
        selectionChanged()
    }
    @objc private func selectionChanged() {
        guard order.indices.contains(jobs.indexOfSelectedItem), let state = states[order[jobs.indexOfSelectedItem]] else { return }
        detail.stringValue = state.currentPath
        progressBar.doubleValue = state.totalBytes == 0 ? (state.state == "Completed" ? 1 : 0) : min(1,Double(state.copiedBytes)/Double(state.totalBytes))
    }
    @objc private func cancelSelected() {
        guard order.indices.contains(jobs.indexOfSelectedItem) else { return }
        NativeTransferQueue.shared.cancel(order[jobs.indexOfSelectedItem])
    }
}
