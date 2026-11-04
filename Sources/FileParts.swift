import Foundation
import Darwin

final class FilePartsTask: @unchecked Sendable {
    private let lock = NSLock(); private var stopped = false
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}
struct FilePartsPlan {
    let parts: [URL]
    let suggestedName: String
    let expectedSize: UInt64?
    let expectedCRC32: UInt32?
    let manifest: URL?
}
enum FilePartsError: LocalizedError {
    case message(String), cancelled
    var errorDescription: String? { switch self { case .message(let text): return text; case .cancelled: return "File operation cancelled; temporary output was removed." } }
}

enum FilePartsService {
    private static let fm = FileManager.default
    private static let crcTable: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value); for _ in 0..<8 { crc = crc & 1 == 0 ? crc >> 1 : (crc >> 1) ^ 0xedb88320 }; return crc
    }
    private static func check(_ task: FilePartsTask) throws { if task.isCancelled { throw FilePartsError.cancelled } }
    private static func fail(_ text: String) -> FilePartsError { .message(text) }
    private static func info(_ url: URL) throws -> stat { var s = stat(); guard url.isFileURL, lstat(url.path, &s) == 0 else { throw fail("Cannot inspect " + url.path) }; return s }
    private static func signature(_ s: stat) -> String { "\(s.st_dev):\(s.st_ino):\(s.st_mode):\(s.st_size):\(s.st_mtimespec.tv_sec):\(s.st_mtimespec.tv_nsec):\(s.st_ctimespec.tv_sec):\(s.st_ctimespec.tv_nsec)" }
    private static func regular(_ url: URL) throws -> stat { let s = try info(url); guard s.st_mode & S_IFMT == S_IFREG, s.st_size >= 0 else { throw fail("Choose ordinary files; symbolic links and special files are unsupported.") }; return s }
    private static func validName(_ name: String) -> Bool { !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\") && !name.contains(":") && !name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) } }
    private static func readFD(_ url: URL, expected: stat) throws -> Int32 {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw fail("Cannot safely open source.") }
        var actual = stat(); guard fstat(fd, &actual) == 0, signature(actual) == signature(expected) else { close(fd); throw fail("Source changed before reading.") }; return fd
    }
    private static func verify(_ url: URL, fd: Int32, expected: stat) throws {
        var actual = stat(); guard fstat(fd, &actual) == 0, signature(actual) == signature(expected), signature(try info(url)) == signature(expected) else { throw fail("Input changed during the operation; output was not committed.") }
    }
    private static func outputFD(_ url: URL) throws -> Int32 {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw fail("Destination already exists or cannot be created.") }; return fd
    }
    private static func copyBytes(input: Int32, output: Int32, count: UInt64, crc: inout UInt32, task: FilePartsTask, update: (UInt64) -> Void) throws {
        var remaining = count, buffer = [UInt8](repeating: 0, count: 262144)
        while remaining > 0 {
            try check(task); let received = read(input, &buffer, Int(min(UInt64(buffer.count), remaining)))
            if received < 0 && errno == EINTR { continue }
            guard received > 0 else { throw fail("Unexpected end of input or read failure.") }
            for byte in buffer.prefix(received) { crc = crcTable[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8) }
            var written = 0
            while written < received {
                let amount = buffer.withUnsafeBytes { write(output, $0.baseAddress!.advanced(by: written), received - written) }
                if amount < 0 && errno == EINTR { continue }
                guard amount > 0 else { throw fail("Output write failed.") }; written += amount
            }
            remaining -= UInt64(received); update(UInt64(received))
        }
    }
    private static func stage(in destination: URL) throws -> URL {
        guard try info(destination).st_mode & S_IFMT == S_IFDIR else { throw fail("Choose an ordinary destination folder.") }
        let stage = destination.appendingPathComponent(".file-parts-" + UUID().uuidString)
        try fm.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions:0o700]); return stage
    }
    private static func commit(_ files: [URL], to destination: URL, task: FilePartsTask) throws -> [URL] {
        var committed: [(URL,String)] = []
        do {
            for file in files {
                try check(task); let target = destination.appendingPathComponent(file.lastPathComponent)
                try fm.moveItem(at: file, to: target); committed.append((target, signature(try info(target))))
            }
            return committed.map(\.0)
        } catch {
            var retained: [String] = []
            for (url, expected) in committed.reversed() {
                do { guard signature(try info(url)) == expected else { retained.append(url.path); continue }; try fm.removeItem(at: url) }
                catch { retained.append(url.path) }
            }
            if !retained.isEmpty { throw fail(error.localizedDescription + "\nChanged or inaccessible partial outputs retained: " + retained.joined(separator: ", ")) }
            throw error
        }
    }
    static func parsePartSize(_ text: String) throws -> UInt64 {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = text.range(of: "^[0-9]+[kKmMgG]?$", options: .regularExpression) else { throw fail("Enter a positive byte count, optionally followed by k, M or G.") }
        let raw = String(text[match]); let last = raw.last!
        let multiplier: UInt64 = last.lowercased() == "k" ? 1024 : last.lowercased() == "m" ? 1_048_576 : last.lowercased() == "g" ? 1_073_741_824 : 1
        guard let count = UInt64(multiplier == 1 ? raw : String(raw.dropLast())), count > 0 else { throw fail("Part size must be positive.") }
        let (result, overflow) = count.multipliedReportingOverflow(by: multiplier); guard !overflow, result <= UInt64(Int64.max) else { throw fail("Part size is too large.") }; return result
    }
    @discardableResult static func split(source: URL, destination: URL, bytesPerPart: UInt64, task: FilePartsTask = FilePartsTask(), progress: ((UInt64,UInt64)->Void)? = nil) throws -> [URL] {
        try check(task); let before = try regular(source), total = UInt64(before.st_size)
        guard bytesPerPart > 0, total > 0 else { throw fail("Choose a nonempty file and a positive part size.") }
        let count = (total - 1) / bytesPerPart + 1; guard count <= 999 else { throw fail("Total Commander split naming supports at most 999 parts. Increase the part size.") }
        let stem = source.deletingPathExtension().lastPathComponent
        guard validName(stem), validName(source.lastPathComponent) else { throw fail("Filename cannot be represented safely in a CRC manifest.") }
        let crcName = stem + (stem == stem.uppercased() ? ".CRC" : ".crc")
        let names = (1...Int(count)).map { stem + String(format: ".%03d", $0) } + [crcName]
        for name in names where (try? info(destination.appendingPathComponent(name))) != nil { throw fail("Destination already exists: " + name) }
        let staging = try stage(in: destination); defer { try? fm.removeItem(at: staging) }
        let input = try readFD(source, expected: before); defer { close(input) }
        var crc: UInt32 = 0xffffffff, completed: UInt64 = 0
        for name in names.dropLast() {
            let output = try outputFD(staging.appendingPathComponent(name)); defer { close(output) }
            try copyBytes(input: input, output: output, count: min(bytesPerPart, total-completed), crc: &crc, task: task) { bytes in completed += bytes; progress?(completed,total) }
            guard fsync(output) == 0 else { throw fail("Cannot flush split output.") }
        }
        try verify(source, fd: input, expected: before); try check(task)
        let ascii = String(source.lastPathComponent.unicodeScalars.map { $0.value < 128 ? Character(String($0)) : "_" })
        let manifest = "filename=\(ascii)\r\nfilenameutf8=\(source.lastPathComponent)\r\nsize=\(total)\r\ncrc32=\(String(format:"%08X",crc ^ 0xffffffff))\r\n"
        try Data(manifest.utf8).write(to: staging.appendingPathComponent(crcName), options: .withoutOverwriting)
        return try commit(names.map { staging.appendingPathComponent($0) }, to: destination, task: task)
    }
    private static func manifestBytes(_ file: URL) throws -> Data {
        let state = try regular(file); guard state.st_size <= 65536 else { throw fail("CRC manifest is too large.") }
        let fd = try readFD(file, expected: state); defer { close(fd) }
        var buffer = [UInt8](repeating: 0, count: Int(state.st_size)), offset = 0
        while offset < buffer.count {
            let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress!.advanced(by: offset), $0.count - offset) }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw fail("CRC manifest read failed.") }; offset += count
        }
        try verify(file, fd: fd, expected: state); return Data(buffer)
    }
    private static func crcInfo(_ file: URL) throws -> (String,UInt64,UInt32) {
        guard try regular(file).st_size <= 65536 else { throw fail("CRC manifest is too large.") }
        let data = try manifestBytes(file)
        var values: [String:Data] = [:]
        for raw in data.split(separator: 10) {
            let line = raw.last == 13 ? raw.dropLast() : raw[...]
            guard !line.isEmpty else { continue }
            guard let equals = line.firstIndex(of: 61), let key = String(data: line[..<equals], encoding: .ascii)?.lowercased(), values[key] == nil else { throw fail("Malformed CRC manifest.") }
            values[key] = Data(line[line.index(after: equals)...])
        }
        let name: String?
        if let utf8 = values["filenameutf8"] { name = String(data:utf8,encoding:.utf8) }
        else { name = values["filename"].flatMap { String(data:$0,encoding:.windowsCP1252) } }
        guard let name, validName(name), let sizeText = values["size"].flatMap({String(data:$0,encoding:.ascii)}), let size = UInt64(sizeText),
              let crcText = values["crc32"].flatMap({String(data:$0,encoding:.ascii)}), crcText.count == 8, let crc = UInt32(crcText,radix:16) else { throw fail("CRC manifest has invalid filename, size or checksum.") }
        return (name,size,crc)
    }
    static func inspect(firstPart: URL) throws -> FilePartsPlan {
        _ = try regular(firstPart)
        let folder = firstPart.deletingLastPathComponent(), name = firstPart.lastPathComponent
        let names = try fm.contentsOfDirectory(atPath: folder.path)
        let regex = try NSRegularExpression(pattern: "^(.*?)([0-9]+)([^0-9]*)$")
        let range = NSRange(name.startIndex..<name.endIndex,in:name)
        var ordered: [(Int,String)] = [], base: String
        if let match = regex.firstMatch(in:name,range:range), !name.hasSuffix("aa"), match.range(at:3).length == 0 || (name as NSString).substring(with:match.range(at:3)).hasPrefix(".") {
            let prefix = (name as NSString).substring(with:match.range(at:1)), digits = (name as NSString).substring(with:match.range(at:2)), suffix = (name as NSString).substring(with:match.range(at:3))
            guard let start = Int(digits), start == 0 || start == 1 else { throw fail("Select the first numbered part (.000 or .001).") }
            for candidate in names where candidate.hasPrefix(prefix) && candidate.hasSuffix(suffix) && candidate.utf16.count == name.utf16.count {
                let middle = String(candidate.dropFirst(prefix.count).dropLast(suffix.count))
                if middle.count == digits.count, middle.allSatisfy(\.isNumber), let number = Int(middle) { ordered.append((number,candidate)) }
            }
            base = prefix.hasSuffix(".") ? String(prefix.dropLast()) : prefix
            ordered.sort { $0.0 < $1.0 }
            guard ordered.first?.0 == start else { throw fail("Earlier numbered parts exist; select the first one.") }
        } else {
            let width = name.reversed().prefix { $0 == "a" }.count
            guard width >= 2, width <= 8 else { throw fail("Select the first Unix alphabetic part ending in aa (or a longer fixed-width a suffix).") }
            let prefix = String(name.dropLast(width)); base = prefix
            for candidate in names where candidate.hasPrefix(prefix) && candidate.count == prefix.count + width {
                let suffix = Array(candidate.suffix(width).utf8)
                if suffix.count == width, suffix.allSatisfy({(97...122).contains($0)}) {
                    let index = suffix.reduce(0) { $0 * 26 + Int($1 - 97) }
                    ordered.append((index,candidate))
                }
            }
            ordered.sort { $0.0 < $1.0 }
        }
        guard !ordered.isEmpty, ordered.count <= 10000 else { throw fail("No supported part sequence was found.") }
        for pair in zip(ordered,ordered.dropFirst()) where pair.1.0 != pair.0.0 + 1 { throw fail("The part sequence contains a gap.") }
        guard ordered[0].1 == name else { throw fail("Select the first part.") }
        let crcMatches = names.filter { $0.lowercased() == (base + ".crc").lowercased() }
        guard crcMatches.count <= 1 else { throw fail("Ambiguous CRC manifests.") }
        let manifest = crcMatches.first.map { folder.appendingPathComponent($0) }, metadata = try manifest.map { try crcInfo($0) }
        let suggested = metadata?.0 ?? (base.isEmpty ? "combined.out" : base)
        guard validName(suggested) else { throw fail("Choose a valid output name.") }
        let parts = ordered.map { folder.appendingPathComponent($0.1) }; for part in parts { _ = try regular(part) }
        return FilePartsPlan(parts:parts,suggestedName:suggested,expectedSize:metadata?.1,expectedCRC32:metadata?.2,manifest:manifest)
    }
    @discardableResult static func combine(firstPart: URL, destination: URL, task: FilePartsTask = FilePartsTask(), progress: ((UInt64,UInt64)->Void)? = nil) throws -> URL {
        try check(task); let plan = try inspect(firstPart:firstPart)
        guard destination.isFileURL, validName(destination.lastPathComponent), (try? info(destination)) == nil else { throw fail("Choose a new output filename; existing files are never overwritten.") }
        let before = try plan.parts.map { try regular($0) }, manifestData = try plan.manifest.map { try manifestBytes($0) }
        var total: UInt64 = 0
        for item in before { let (sum,overflow) = total.addingReportingOverflow(UInt64(item.st_size)); guard !overflow else { throw fail("Combined size overflow.") }; total = sum }
        if let expected = plan.expectedSize, expected != total { throw fail("Part sizes do not match the CRC manifest; a part may be missing.") }
        let staging = try stage(in:destination.deletingLastPathComponent()); defer { try? fm.removeItem(at:staging) }
        let local = staging.appendingPathComponent(destination.lastPathComponent), output = try outputFD(local); defer { close(output) }
        var crc: UInt32 = 0xffffffff, completed: UInt64 = 0
        for (part,state) in zip(plan.parts,before) {
            let input = try readFD(part,expected:state); defer { close(input) }
            try copyBytes(input:input,output:output,count:UInt64(state.st_size),crc:&crc,task:task) { bytes in completed += bytes; progress?(completed,total) }
            try verify(part,fd:input,expected:state)
        }
        for (part,state) in zip(plan.parts,before) { guard signature(try info(part)) == signature(state) else { throw fail("An input part changed during combination.") } }
        if let manifest = plan.manifest, try manifestBytes(manifest) != manifestData { throw fail("CRC manifest changed during combination.") }
        guard try inspect(firstPart:firstPart).parts == plan.parts else { throw fail("Part sequence changed during combination.") }
        if let expected = plan.expectedCRC32, expected != (crc ^ 0xffffffff) { throw fail("Combined CRC32 does not match. No output was committed.") }
        guard fsync(output) == 0 else { throw fail("Cannot flush combined output.") }
        try check(task); _ = try commit([local],to:destination.deletingLastPathComponent(),task:task); return destination
    }
}
