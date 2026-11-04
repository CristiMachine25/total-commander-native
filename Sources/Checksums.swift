import Foundation
import CryptoKit
import Darwin

enum ChecksumAlgorithm: String, CaseIterable {
    case sha256, sha1, md5, sfv
    var length: Int { switch self { case .sha256: return 64; case .sha1: return 40; case .md5: return 32; case .sfv: return 8 } }
}
struct ChecksumRecord { let path: String; let expected: String }
enum ChecksumService {
    private static func openRegular(_ url: URL) throws -> FileHandle {
        let fd = open(url.path,O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw NativeOperationError.message("Cannot open regular file: \(url.path)") }
        var statInfo = stat()
        guard fstat(fd,&statInfo) == 0, statInfo.st_mode & S_IFMT == S_IFREG else { close(fd); throw NativeOperationError.message("Not a regular file: \(url.path)") }
        return FileHandle(fileDescriptor:fd,closeOnDealloc:true)
    }
    static func digest(_ url: URL, algorithm: ChecksumAlgorithm) throws -> String {
        let file = try openRegular(url); defer { try? file.close() }
        var sha256 = SHA256(), sha1 = Insecure.SHA1(), md5 = Insecure.MD5(), crc: UInt32 = 0xffffffff
        while let data = try file.read(upToCount: 262144), !data.isEmpty {
            switch algorithm {
            case .sha256: sha256.update(data:data)
            case .sha1: sha1.update(data:data)
            case .md5: md5.update(data:data)
            case .sfv: for b in data { crc ^= UInt32(b); for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0) } }
            }
        }
        switch algorithm {
        case .sha256: return sha256.finalize().map { String(format:"%02x",$0) }.joined()
        case .sha1: return sha1.finalize().map { String(format:"%02x",$0) }.joined()
        case .md5: return md5.finalize().map { String(format:"%02x",$0) }.joined()
        case .sfv: return String(format:"%08X",crc ^ 0xffffffff)
        }
    }
    static func create(sources: [URL], destination: URL, algorithm: ChecksumAlgorithm) throws {
        var lines: [String] = []
        for url in sources {
            guard url.deletingLastPathComponent().standardizedFileURL == destination.deletingLastPathComponent().standardizedFileURL else { throw NativeOperationError.message("Save the checksum manifest beside the selected files.") }
            let name = url.lastPathComponent
            guard !name.contains("\n"), !name.contains("\r"), !name.contains("\\") else { throw NativeOperationError.message("Filename cannot be represented in this checksum format: \(name)") }
            if algorithm == .sfv && (name.hasPrefix(";") || name.hasPrefix("#")) { throw NativeOperationError.message("SFV cannot represent comment-prefixed filenames") }
            let hash = try digest(url,algorithm:algorithm)
            lines.append(algorithm == .sfv ? name + " " + hash : hash + " *" + name)
        }
        try Data((lines.joined(separator:"\r\n") + "\r\n").utf8).write(to:destination,options:.withoutOverwriting)
    }
    static func parse(_ text: String, algorithm: ChecksumAlgorithm) throws -> [ChecksumRecord] {
        var records: [ChecksumRecord] = []
        for raw in text.components(separatedBy:.newlines) {
            if raw.isEmpty || raw.hasPrefix(";") || raw.hasPrefix("#") { continue }
            let hash: String, path: String
            if algorithm == .sfv {
                guard let space = raw.lastIndex(of:" ") else { throw NativeOperationError.message("Invalid SFV line") }
                path = String(raw[..<space]); hash = String(raw[raw.index(after:space)...])
            } else {
                guard raw.count > algorithm.length + 2 else { throw NativeOperationError.message("Invalid checksum line") }
                hash = String(raw.prefix(algorithm.length)); let rest = String(raw.dropFirst(algorithm.length))
                guard rest.hasPrefix(" *") || rest.hasPrefix("  ") else { throw NativeOperationError.message("Invalid checksum separator") }
                path = String(rest.dropFirst(2))
            }
            guard hash.count == algorithm.length, hash.allSatisfy({ $0.isHexDigit }), !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.split(separator:"/").contains(".."), !path.contains("\0") else { throw NativeOperationError.message("Invalid or unsafe checksum entry") }
            records.append(ChecksumRecord(path:path,expected:hash))
        }
        guard !records.isEmpty else { throw NativeOperationError.message("No checksum records found") }; return records
    }
    static func verify(manifest: URL, algorithm: ChecksumAlgorithm) throws -> [(String,String)] {
        let handle = try openRegular(manifest); defer { try? handle.close() }
        let data = try handle.read(upToCount:16*1024*1024 + 1) ?? Data()
        guard data.count <= 16*1024*1024, let text = String(data:data,encoding:.utf8) else { throw NativeOperationError.message("Manifest must be UTF-8 and at most 16 MiB") }
        let records = try parse(text,algorithm:algorithm)
        let root = manifest.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        return records.map { record in
            do {
                let url = root.appendingPathComponent(record.path).resolvingSymlinksInPath().standardizedFileURL
                guard url.path.hasPrefix(root.path + "/") else { throw NativeOperationError.message("Path escapes manifest folder") }
                let actual = try digest(url,algorithm:algorithm)
                return (record.path, actual.lowercased() == record.expected.lowercased() ? "OK" : "MISMATCH")
            } catch { return (record.path,"ERROR: " + error.localizedDescription) }
        }
    }
}
