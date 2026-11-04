import Foundation
import CryptoKit
import Darwin

struct SearchReport { var matches: [URL]; var warnings: [String]; var cancelled: Bool }
struct RenameItem { let source: URL; let destination: URL }
struct ComparisonItem { let relativePath: String; let status: String }
struct ArchiveItem { let path: String; let size: UInt64; let isDirectory: Bool }

struct ArchivePasswordRequired: LocalizedError {
    var errorDescription: String? { "This archive requires a password, or the supplied password was incorrect." }
}

enum NativeOperationError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}

enum NativeOperations {
    private static let fm = FileManager.default
    private static func canonical(_ url: URL) -> URL {
        guard let resolved = realpath(url.path, nil) else { return url.standardizedFileURL }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved))
    }
    private static func fail(_ message: String) -> NativeOperationError { .message(message) }
    private static func exists(_ url: URL) -> Bool {
        (try? fm.attributesOfItem(atPath: url.path)) != nil
    }
    private static func ordinaryDirectory(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw fail("Expected an ordinary directory: \(url.path)") }
    }
    private static func regularFile(_ url: URL) throws {
        let attributes = try fm.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw fail("Expected a regular file: \(url.path)") }
    }
    private static func validName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0")
    }
    private static func collisionKey(_ url: URL) -> String {
        let sensitive = (try? url.deletingLastPathComponent().resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]).volumeSupportsCaseSensitiveNames) ?? false
        let path = canonical(url.deletingLastPathComponent()).appendingPathComponent(url.lastPathComponent).path.precomposedStringWithCanonicalMapping
        return sensitive ? path : path.lowercased()
    }
    private static func wildcard(_ pattern: String) throws -> NSRegularExpression {
        var expression = "^"
        for character in pattern {
            if character == "*" { expression += ".*" }
            else if character == "?" { expression += "." }
            else { expression += NSRegularExpression.escapedPattern(for: String(character)) }
        }
        return try NSRegularExpression(pattern: expression + "$", options: [.caseInsensitive])
    }
    static func search(root: URL, pattern: String, contains: String? = nil, showHidden: Bool = false,
                       cancelled: () -> Bool = { false }) throws -> SearchReport {
        try ordinaryDirectory(root)
        let root = canonical(root)
        let matcher = try wildcard(pattern.isEmpty ? "*" : pattern)
        var report = SearchReport(matches: [], warnings: [], cancelled: false)
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]
        let options: FileManager.DirectoryEnumerationOptions = showHidden ? [] : [.skipsHiddenFiles]
        guard let iterator = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: options,
                                          errorHandler: { url, error in report.warnings.append("\(url.path): \(error.localizedDescription)"); return true }) else {
            throw fail("Cannot enumerate \(root.path)")
        }
        let needle = contains.flatMap { $0.isEmpty ? nil : Data($0.utf8) }
        for case let url as URL in iterator {
            if cancelled() { report.cancelled = true; break }
            do {
                let values = try url.resourceValues(forKeys: Set(keys))
                if values.isSymbolicLink == true { iterator.skipDescendants(); continue }
                let name = url.lastPathComponent
                guard matcher.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil else { continue }
                if let needle {
                    guard values.isRegularFile == true else { continue }
                    if !(try fileContains(url, needle: needle, cancelled: cancelled)) { continue }
                }
                report.matches.append(url)
                if report.matches.count >= 100_000 { report.warnings.append("Stopped after 100,000 results."); break }
            } catch { report.warnings.append("\(url.path): \(error.localizedDescription)") }
        }
        if cancelled() { report.cancelled = true }
        report.matches.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        return report
    }
    private static func fileContains(_ url: URL, needle: Data, cancelled: () -> Bool) throws -> Bool {
        guard needle.count <= 1_048_576 else { throw fail("Search text exceeds 1 MiB.") }
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        var tail = Data()
        while !cancelled() {
            let chunk = try file.read(upToCount: 262_144) ?? Data()
            if chunk.isEmpty { return false }
            tail.append(chunk)
            if tail.range(of: needle) != nil { return true }
            tail = Data(tail.suffix(max(0, needle.count - 1)))
        }
        return false
    }
    static func sha256(_ url: URL) throws -> String {
        try regularFile(url)
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        var hash = SHA256()
        while true {
            let data = try file.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty { break }
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func previewRename(sources: [URL], find: String, replace: String, prefix: String = "", suffix: String = "") throws -> [RenameItem] {
        guard !sources.isEmpty else { throw fail("Select files or folders to rename.") }
        let items = sources.map { source -> RenameItem in
            let old = source.lastPathComponent
            let changed = find.isEmpty ? old : old.replacingOccurrences(of: find, with: replace)
            let folder = canonical(source.deletingLastPathComponent())
            return RenameItem(source: folder.appendingPathComponent(source.lastPathComponent),
                              destination: folder.appendingPathComponent(prefix + changed + suffix))
        }
        try validateRename(items)
        return items
    }
    private static func validateRename(_ items: [RenameItem]) throws {
        guard Set(items.map { $0.source.path }).count == items.count else { throw fail("Duplicate rename sources.") }
        var destinations = Set<String>()
        let sourceKeys = Set(items.map { collisionKey($0.source) })
        for item in items {
            guard validName(item.destination.lastPathComponent),
                  canonical(item.source.deletingLastPathComponent()).path == canonical(item.destination.deletingLastPathComponent()).path else {
                throw fail("Rename must use a valid name in the same folder: \(item.source.path) → \(item.destination.path)")
            }
            guard exists(item.source) else { throw fail("Source disappeared: \(item.source.path)") }
            let key = collisionKey(item.destination)
            guard destinations.insert(key).inserted else { throw fail("Two items would have the same name: \(item.destination.lastPathComponent)") }
            if exists(item.destination) && !sourceKeys.contains(key) { throw fail("Destination already exists: \(item.destination.path)") }
        }
        for first in items {
            for second in items where first.source != second.source {
                if second.source.path.hasPrefix(first.source.path + "/") { throw fail("Do not rename a folder and its contents in the same operation.") }
            }
        }
    }
    static func applyRename(_ items: [RenameItem]) throws {
        try validateRename(items)
        let changed = items.filter { $0.source.path != $0.destination.path }
        var temporary: [Int: URL] = [:]
        var completed = Set<Int>()
        do {
            for (index, item) in changed.enumerated() {
                let url = item.source.deletingLastPathComponent().appendingPathComponent(".rename-" + UUID().uuidString)
                try fm.moveItem(at: item.source, to: url); temporary[index] = url
            }
            for (index, item) in changed.enumerated() {
                guard !exists(item.destination), let url = temporary[index] else { throw fail("Destination changed during rename: \(item.destination.path)") }
                try fm.moveItem(at: url, to: item.destination); completed.insert(index)
            }
        } catch {
            let original = error.localizedDescription
            var recoveryErrors: [String] = []
            // Return all committed destinations to temporary names before restoring
            // originals, so swaps and cycles do not collide during rollback.
            for index in completed.sorted().reversed() {
                do { try fm.moveItem(at: changed[index].destination, to: temporary[index]!) }
                catch { recoveryErrors.append("\(changed[index].destination.path): \(error.localizedDescription)") }
            }
            for index in temporary.keys.sorted() {
                let url = temporary[index]!
                if exists(url) {
                    do { try fm.moveItem(at: url, to: changed[index].source) }
                    catch { recoveryErrors.append("Recovery file \(url.path): \(error.localizedDescription)") }
                }
            }
            throw fail(original + (recoveryErrors.isEmpty ? "\nOriginal names restored." : "\nSome names could not be restored:\n" + recoveryErrors.joined(separator: "\n")))
        }
    }
    private struct ManifestEntry { let url: URL; let type: FileAttributeType; let size: UInt64; let modified: Date? }
    private static func manifest(_ root: URL, cancelled: () -> Bool) throws -> [String: ManifestEntry] {
        try ordinaryDirectory(root)
        let root = canonical(root)
        var failure: Error?
        guard let iterator = fm.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], errorHandler: { _, error in failure = error; return false }) else { throw fail("Cannot enumerate \(root.path)") }
        var result: [String: ManifestEntry] = [:]
        for case let url as URL in iterator {
            if cancelled() { throw fail("Comparison cancelled; no complete result is available.") }
            let attributes = try fm.attributesOfItem(atPath: url.path)
            let type = attributes[.type] as? FileAttributeType ?? .typeUnknown
            if type == .typeSymbolicLink { iterator.skipDescendants() }
            let relative = String(url.path.dropFirst(root.path.count + 1))
            result[relative] = ManifestEntry(url: url, type: type, size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0, modified: attributes[.modificationDate] as? Date)
        }
        if let failure { throw failure }
        return result
    }
    static func compare(left: URL, right: URL, byContent: Bool = true, cancelled: () -> Bool = { false }) throws -> [ComparisonItem] {
        let left = left.standardizedFileURL, right = right.standardizedFileURL
        let a = try manifest(left, cancelled: cancelled), b = try manifest(right, cancelled: cancelled)
        var result: [ComparisonItem] = []
        for path in Set(a.keys).union(b.keys).sorted() {
            if cancelled() { throw fail("Comparison cancelled; no complete result is available.") }
            let status: String
            if let x = a[path], let y = b[path] {
                if x.type != y.type { status = "Different type" }
                else if x.type == .typeDirectory { status = "Directory" }
                else if x.type == .typeSymbolicLink { status = try fm.destinationOfSymbolicLink(atPath: x.url.path) == fm.destinationOfSymbolicLink(atPath: y.url.path) ? "Equal link" : "Different link" }
                else if x.type != .typeRegular { status = "Unsupported special file" }
                else if x.size != y.size { status = "Different" }
                else if byContent { status = try sha256(x.url) == sha256(y.url) ? "Equal content" : "Different" }
                else { status = x.modified == y.modified ? "Same size/date (content unchecked)" : "Different date" }
            } else { status = a[path] != nil ? "Only left" : "Only right" }
            result.append(ComparisonItem(relativePath: path, status: status))
        }
        return result
    }
    static func recognizesArchive(name: String) -> Bool {
        ["zip", "7z", "tar", "gz", "tgz", "bz2", "tbz2", "xz", "txz", "rar"].contains((name as NSString).pathExtension.lowercased())
    }
    // Binary libarchive metadata is validated independently of process output.
    static func listArchive(archive: URL, tool: URL, password: String? = nil, cancelled: () -> Bool = {false}) throws -> [ArchiveItem] {
        try NativeArchiveReader().walk(archive: archive, output: nil, password: password, cancelled: cancelled)
    }
    private static func runTool(_ tool: URL, arguments: [String], directory: URL, extractionRoot: URL? = nil) throws {
        guard fm.isExecutableFile(atPath: tool.path) else { throw fail("Bundled archive tool is unavailable.") }
        let logURL = fm.temporaryDirectory.appendingPathComponent("commander-tool-" + UUID().uuidString)
        fm.createFile(atPath: logURL.path, contents: nil)
        defer { try? fm.removeItem(at: logURL) }
        let log = try FileHandle(forWritingTo: logURL); defer { try? log.close() }
        let process = Process(); process.executableURL = tool; process.arguments = arguments; process.currentDirectoryURL = directory
        process.standardOutput = log; process.standardError = log; process.standardInput = FileHandle.nullDevice
        try process.run()
        defer { if process.isRunning { process.terminate(); process.waitUntilExit() } }
        let deadline = Date().addingTimeInterval(300)
        while process.isRunning {
            var problem: String?
            if Date() > deadline { problem = "Archive operation exceeded five minutes." }
            if let size = (try? fm.attributesOfItem(atPath: logURL.path)[.size]) as? NSNumber, size.intValue > 8_388_608 { problem = "Archive tool output exceeded its limit." }
            if let root = extractionRoot, let entries = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isSymbolicLinkKey]) {
                var total: UInt64 = 0, count = 0
                for case let url as URL in entries {
                    count += 1
                    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
                    total += UInt64(max(0, values.fileSize ?? 0))
                    if values.isSymbolicLink == true || total > 1_073_741_824 || count > 100_000 { problem = "Extraction produced an unsafe link or exceeded its size/count limit."; break }
                }
            }
            if let problem { process.terminate(); process.waitUntilExit(); throw fail(problem) }
            Thread.sleep(forTimeInterval: 0.1)
        }
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let output = String(data: try Data(contentsOf: logURL), encoding: .utf8) ?? ""
            throw fail("Archive tool failed (\(process.terminationStatus)).\n" + String(output.suffix(4000)))
        }
    }
    static func pack(sources: [URL], archive: URL, tool: URL) throws {
        guard let first = sources.first else { throw fail("Select files to pack.") }
        let parent = canonical(first.deletingLastPathComponent())
        guard sources.allSatisfy({ canonical($0.deletingLastPathComponent()).path == parent.path }) else { throw fail("Packing currently requires items from one folder.") }
        guard !exists(archive) else { throw fail("Archive already exists: \(archive.path)") }
        try ordinaryDirectory(archive.deletingLastPathComponent())
        for source in sources {
            let attributes = try fm.attributesOfItem(atPath: source.path)
            let type = attributes[.type] as? FileAttributeType
            guard type == .typeRegular || type == .typeDirectory else { throw fail("Packing symbolic links and special files is unsupported.") }
            guard !archive.standardizedFileURL.path.hasPrefix(source.standardizedFileURL.path + "/") else { throw fail("Do not create an archive inside a selected folder.") }
            if type == .typeDirectory {
                let entries = try manifest(source, cancelled: { false })
                guard entries.values.allSatisfy({ $0.type == .typeRegular || $0.type == .typeDirectory }) else { throw fail("Selected folder contains links or special files; packing was not started.") }
            }
        }
        let temporary = archive.deletingLastPathComponent().appendingPathComponent(".archive-" + UUID().uuidString + ".zip")
        defer { try? fm.removeItem(at: temporary) }
        try runTool(tool, arguments: ["a", "-tzip", "-mx=5", temporary.path, "--"] + sources.map(\.lastPathComponent), directory: parent)
        _ = try listArchive(archive: temporary, tool: tool)
        guard !exists(archive) else { throw fail("Destination appeared while packing; archive was not replaced.") }
        try fm.moveItem(at: temporary, to: archive)
    }
    static func unpack(archive: URL, destination: URL, tool: URL, password: String? = nil) throws {
        try ordinaryDirectory(destination)
        let items = try listArchive(archive: archive, tool: tool, password: password)
        let roots = Set(items.map { String($0.path.split(separator: "/")[0]) })
        for name in roots where exists(destination.appendingPathComponent(name)) { throw fail("Extraction would replace an existing item: \(name)") }
        let stage = destination.appendingPathComponent(".extract-" + UUID().uuidString)
        try fm.createDirectory(at: stage, withIntermediateDirectories: false)
        var committed: [String] = []
        do {
            _ = try NativeArchiveReader().walk(archive: archive, output: stage, password: password)
            let extracted = try manifest(stage, cancelled: { false })
            let expectedFiles = Dictionary(uniqueKeysWithValues: items.filter { !$0.isDirectory }.map { ($0.path, $0.size) })
            for (path, entry) in extracted {
                guard entry.type == .typeDirectory || entry.type == .typeRegular else { throw fail("Extraction produced a link or special file: \(path)") }
                if entry.type == .typeRegular { guard expectedFiles[path] == entry.size else { throw fail("Extracted file differs from ZIP metadata: \(path)") } }
            }
            guard expectedFiles.keys.allSatisfy({ extracted[$0]?.type == .typeRegular }) else { throw fail("Archive extraction is incomplete.") }
            for name in roots.sorted() {
                let target = destination.appendingPathComponent(name)
                guard !exists(target) else { throw fail("Extraction destination changed: \(name)") }
                try fm.moveItem(at: stage.appendingPathComponent(name), to: target); committed.append(name)
            }
            try fm.removeItem(at: stage)
        } catch {
            var recovery: [String] = []
            for name in committed.reversed() {
                do { try fm.moveItem(at: destination.appendingPathComponent(name), to: stage.appendingPathComponent(name)) }
                catch { recovery.append(name) }
            }
            if recovery.isEmpty { try? fm.removeItem(at: stage) }
            throw fail(error.localizedDescription + (recovery.isEmpty ? "" : "\nPartial extraction remains: " + recovery.joined(separator: ", ")))
        }
    }
}

/// Binary archive metadata and bounded streaming extraction. No command-output parsing,
/// archive-controlled filesystem writes, links, or password process arguments.
private final class NativeArchiveReader {
    typealias P = UnsafeMutableRawPointer
    private let library: P
    private let create: @convention(c) () -> P?
    private let free: @convention(c) (P) -> Int32
    private let allFormats: @convention(c) (P) -> Int32
    private let allFilters: @convention(c) (P) -> Int32
    private let rawFormat: @convention(c) (P) -> Int32
    private let openFD: @convention(c) (P, Int32, Int) -> Int32
    private let next: @convention(c) (P, UnsafeMutablePointer<P?>) -> Int32
    private let readData: @convention(c) (P, P?, Int) -> Int
    private let errorText: @convention(c) (P) -> UnsafePointer<CChar>?
    private let formatCode: @convention(c) (P) -> Int32
    private let pathname: @convention(c) (P) -> UnsafePointer<CChar>?
    private let symlink: @convention(c) (P) -> UnsafePointer<CChar>?
    private let hardlink: @convention(c) (P) -> UnsafePointer<CChar>?
    private let filetype: @convention(c) (P) -> UInt32
    private let size: @convention(c) (P) -> Int64
    private let sizeSet: @convention(c) (P) -> Int32
    private let passphrase: @convention(c) (P, UnsafePointer<CChar>) -> Int32
    private func fail(_ message: String) -> NativeOperationError { .message(message) }
    init() throws {
        guard let handle = dlopen("/usr/lib/libarchive.2.dylib", RTLD_NOW | RTLD_LOCAL) else { throw NativeOperationError.message("macOS archive reader is unavailable.") }
        library = handle
        func symbol<T>(_ name: String, _: T.Type) throws -> T {
            guard let pointer = dlsym(handle, name) else { throw NativeOperationError.message("Archive reader lacks " + name) }
            return unsafeBitCast(pointer, to: T.self)
        }
        do {
            create = try symbol("archive_read_new", (@convention(c) () -> P?).self)
            free = try symbol("archive_read_free", (@convention(c) (P) -> Int32).self)
            allFormats = try symbol("archive_read_support_format_all", (@convention(c) (P) -> Int32).self)
            allFilters = try symbol("archive_read_support_filter_all", (@convention(c) (P) -> Int32).self)
            rawFormat = try symbol("archive_read_support_format_raw", (@convention(c) (P) -> Int32).self)
            openFD = try symbol("archive_read_open_fd", (@convention(c) (P, Int32, Int) -> Int32).self)
            next = try symbol("archive_read_next_header", (@convention(c) (P, UnsafeMutablePointer<P?>) -> Int32).self)
            readData = try symbol("archive_read_data", (@convention(c) (P, P?, Int) -> Int).self)
            errorText = try symbol("archive_error_string", (@convention(c) (P) -> UnsafePointer<CChar>?).self)
            formatCode = try symbol("archive_format", (@convention(c) (P) -> Int32).self)
            pathname = try symbol("archive_entry_pathname_utf8", (@convention(c) (P) -> UnsafePointer<CChar>?).self)
            symlink = try symbol("archive_entry_symlink", (@convention(c) (P) -> UnsafePointer<CChar>?).self)
            hardlink = try symbol("archive_entry_hardlink", (@convention(c) (P) -> UnsafePointer<CChar>?).self)
            filetype = try symbol("archive_entry_filetype", (@convention(c) (P) -> UInt32).self)
            size = try symbol("archive_entry_size", (@convention(c) (P) -> Int64).self)
            sizeSet = try symbol("archive_entry_size_is_set", (@convention(c) (P) -> Int32).self)
            passphrase = try symbol("archive_read_add_passphrase", (@convention(c) (P, UnsafePointer<CChar>) -> Int32).self)
        } catch { dlclose(handle); throw error }
    }
    deinit { dlclose(library) }
    func walk(archive: URL, output: URL?, password: String?, cancelled: () -> Bool = {false}) throws -> [ArchiveItem] {
        let fd = open(archive.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw fail("Cannot open archive safely.") }; defer { close(fd) }
        var before = stat(); guard fstat(fd, &before) == 0, before.st_mode & S_IFMT == S_IFREG, before.st_size <= 536_870_912 else { throw fail("Choose a regular archive up to 512 MiB.") }
        var magic = [UInt8](repeating: 0, count: 8); let magicCount = pread(fd, &magic, magic.count, 0)
        let gzip = magicCount >= 2 && magic[0] == 0x1f && magic[1] == 0x8b
        let bzip = magicCount >= 3 && Array(magic.prefix(3)) == [0x42,0x5a,0x68]
        let xz = magicCount >= 6 && Array(magic.prefix(6)) == [0xfd,0x37,0x7a,0x58,0x5a,0x00]
        let rawCompressed = gzip || bzip || xz
        guard let reader = create() else { throw fail("Cannot initialize archive reader.") }; defer { _ = free(reader) }
        _ = allFormats(reader); _ = allFilters(reader); if rawCompressed { _ = rawFormat(reader) }
        if let password {
            guard !password.utf8.contains(0), password.utf8.count <= 4096 else { throw fail("Unsupported archive password.") }
            guard password.withCString({ passphrase(reader, $0) }) == 0 else { throw fail("Cannot supply archive password.") }
        }
        func failure() -> Error {
            var detail = errorText(reader).map { String(cString: $0) } ?? "Malformed or unsupported archive."
            if let password, !password.isEmpty { detail = detail.replacingOccurrences(of: password, with: "[redacted]") }
            let lower = detail.lowercased()
            if !lower.contains("not supported"), !lower.contains("unsupported"), lower.contains("passphrase") || lower.contains("password") { return ArchivePasswordRequired() }
            return fail("Archive read failed: " + detail)
        }
        guard openFD(reader, fd, 65536) == 0 else { throw failure() }
        var result: [ArchiveItem] = [], names = Set<String>(), files = Set<String>(), canonicalPaths: [String:String] = [:], total: UInt64 = 0
        let deadline = Date().addingTimeInterval(300)
        while true {
            guard !cancelled(), Date() < deadline, result.count < 100000 else { throw fail("Archive exceeds time or member-count limits.") }
            var entry: P?; let status = next(reader, &entry)
            if status == 1 { break }
            guard status == 0, let entry else { throw failure() }
            let format = formatCode(reader) & 0xff0000
            guard [0x30000, 0x50000, 0xd0000, 0xe0000, 0x100000].contains(Int(format)) || (rawCompressed && format == 0x90000) else { throw fail("Only ZIP/ZIP64, 7z, TAR, GZIP and RAR archives are supported.") }
            guard symlink(entry) == nil, hardlink(entry) == nil else { throw fail("Archive symbolic and hard links are not allowed.") }
            let type = filetype(entry), directory = type == UInt32(S_IFDIR)
            guard directory || type == UInt32(S_IFREG) else { throw fail("Archive special files are not allowed.") }
            guard let rawName = pathname(entry), var name = String(validatingCString: rawName) else { throw fail("Archive filenames must be valid UTF-8.") }
            if rawCompressed && format == 0x90000 { name = archive.deletingPathExtension().lastPathComponent }
            while name.hasPrefix("./") { name = String(name.dropFirst(2)) }
            if directory { while name.hasSuffix("/") { name.removeLast() }; if name.isEmpty || name == "." { continue } }
            let parts = name.split(separator: "/", omittingEmptySubsequences: false)
            guard !name.isEmpty, !name.hasPrefix("/"), !name.contains("\\"), !name.contains(":"),
                  !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  parts.count <= 64, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw fail("Unsafe archive member path.") }
            for index in 1...parts.count {
                let prefix = parts.prefix(index).joined(separator: "/"), key = prefix.precomposedStringWithCanonicalMapping.lowercased()
                if let previous = canonicalPaths[key], previous != prefix { throw fail("Ambiguous archive directory spelling.") }
                canonicalPaths[key] = prefix
            }
            let key = name.precomposedStringWithCanonicalMapping.lowercased()
            guard names.insert(key).inserted else { throw fail("Duplicate or case-colliding archive path: " + name) }
            if !directory { files.insert(key) }
            for index in 1..<parts.count {
                let parent = parts.prefix(index).joined(separator: "/").precomposedStringWithCanonicalMapping.lowercased()
                guard !files.contains(parent) else { throw fail("Archive file/directory collision.") }
            }
            let declared = size(entry), known = sizeSet(entry) != 0
            guard !known || declared >= 0 && declared <= 536_870_912 else { throw fail("Archive member exceeds 512 MiB.") }
            var targetFD: Int32 = -1
            if let output {
                let target = output.appendingPathComponent(name)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions:0o700])
                if directory { try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true, attributes: [.posixPermissions:0o700]) }
                else { targetFD = open(target.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600); guard targetFD >= 0 else { throw fail("Cannot create extracted file safely.") } }
            }
            defer { if targetFD >= 0 { close(targetFD) } }
            var actual: UInt64 = 0, buffer = [UInt8](repeating: 0, count: 65536)
            while true {
                guard !cancelled(), Date() < deadline else { throw fail("Archive expansion cancelled or timed out.") }
                let count = buffer.withUnsafeMutableBytes { readData(reader, $0.baseAddress, $0.count) }
                guard count >= 0 else { throw failure() }; if count == 0 { break }
                actual += UInt64(count); total += UInt64(count)
                guard actual <= 536_870_912, total <= 1_073_741_824 else { throw fail("Archive expansion exceeds 512 MiB per member or 1 GiB total.") }
                if targetFD >= 0 {
                    var offset = 0
                    while offset < count {
                        let written = buffer.withUnsafeBytes { write(targetFD, $0.baseAddress!.advanced(by: offset), count - offset) }
                        if written < 0 && errno == EINTR { continue }
                        guard written > 0 else { throw fail("Extracted file write failed.") }; offset += written
                    }
                }
            }
            guard directory ? actual == 0 : (!known || actual == UInt64(declared)) else { throw fail("Archive member size does not match its metadata.") }
            if targetFD >= 0 { guard fsync(targetFD) == 0 else { throw fail("Extracted file flush failed.") } }
            result.append(ArchiveItem(path: name, size: actual, isDirectory: directory))
        }
        let finalFormat = formatCode(reader) & 0xff0000
        guard [0x30000,0x50000,0xd0000,0xe0000,0x100000].contains(Int(finalFormat)) || (rawCompressed && finalFormat == 0x90000) else { throw fail("Unsupported archive format.") }
        for path in names {
            let components = path.split(separator: "/")
            for index in 1..<components.count where files.contains(components.prefix(index).joined(separator: "/")) { throw fail("Archive file/directory collision.") }
        }
        var after = stat(); guard fstat(fd, &after) == 0, before.st_size == after.st_size, before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec, before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec, before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec, before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else { throw fail("Archive changed while reading.") }
        return result
    }
}
