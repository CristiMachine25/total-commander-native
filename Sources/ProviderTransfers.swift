import Foundation
import CryptoKit
import Darwin

struct ProviderArchiveSessionUpdate {
    let previous: ArchiveBrowserSession
    let replacement: ArchiveBrowserSession
}
struct ProviderTransferResult {
    var copiedCount = 0
    var movedCount = 0
    var updatedArchiveSessions: [ProviderArchiveSessionUpdate] = []
}
struct ProviderTransferFailure: LocalizedError {
    let result: ProviderTransferResult
    let reason: String
    var errorDescription: String? { "Copied \(result.copiedCount), removed \(result.movedCount) source item(s). Completed destination items remain.\n" + reason }
}

/// Synchronous provider transfers; caller supplies background execution and permanent-delete consent.
/// FTP has no server-side compare-and-delete transaction. Revalidation narrows, but cannot remove, that race.
enum ProviderTransferService {
    private static let fm = FileManager.default
    private struct Fingerprint: Equatable { let content: [String:String]; let metadata: [String:String] }
    private static func providerPath(_ location: PaneLocation) -> String {
        switch location { case .local(let url): return url.path; case .archive(_, let path): return path; case .ftp(_, let path): return (try? FTPClient.normalizedPath(path)) ?? path }
    }
    private static func fail(_ text: String) -> FTPError { .message(text) }
    private static func check(_ task: FTPTask) throws { if task.isCancelled { throw FTPError.cancelled } }
    private static func statAt(_ url: URL) throws -> stat {
        var info = stat(); guard lstat(url.path, &info) == 0 else { throw fail("Cannot inspect " + url.path) }; return info
    }
    private static func signature(_ s: stat) -> String {
        "\(s.st_dev):\(s.st_ino):\(s.st_mode):\(s.st_size):\(s.st_mtimespec.tv_sec):\(s.st_mtimespec.tv_nsec):\(s.st_ctimespec.tv_sec):\(s.st_ctimespec.tv_nsec)"
    }
    private static func fingerprint(_ root: URL, task: FTPTask) throws -> Fingerprint {
        var content: [String:String] = [:], metadata: [String:String] = [:]
        func walk(_ url: URL, _ path: String, _ depth: Int) throws {
            try check(task)
            guard depth <= 64, content.count < 20000 else { throw fail("Transfer exceeds 64 levels or 20,000 items.") }
            let before = try statAt(url)
            switch before.st_mode & S_IFMT {
            case S_IFDIR:
                content[path] = "directory"
                for child in try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                    try walk(child, path + "/" + child.lastPathComponent, depth + 1)
                }
            case S_IFREG:
                let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
                guard fd >= 0 else { throw fail("Cannot safely open " + url.path) }; defer { close(fd) }
                var opened = stat(); guard fstat(fd, &opened) == 0, signature(before) == signature(opened) else { throw fail("Source changed before reading.") }
                var hash = SHA256(), buffer = [UInt8](repeating: 0, count: 262144)
                while true {
                    try check(task); let count = read(fd, &buffer, buffer.count)
                    if count < 0 && errno == EINTR { continue }
                    guard count >= 0 else { throw fail("Read failed.") }; if count == 0 { break }
                    hash.update(data: Data(buffer[0..<count]))
                }
                content[path] = "file:" + hash.finalize().map { String(format:"%02x", $0) }.joined()
            default: throw fail("Symbolic links and special files are not transferred: " + url.path)
            }
            guard signature(before) == signature(try statAt(url)) else { throw fail("Item changed while reading: " + url.path) }
            metadata[path] = signature(before)
        }
        try walk(root, "", 0); return Fingerprint(content: content, metadata: metadata)
    }
    private static func safeCopy(_ source: URL, _ target: URL, task: FTPTask, depth: Int = 0) throws {
        try check(task); guard depth <= 64 else { throw fail("Transfer nesting limit exceeded.") }
        let before = try statAt(source)
        switch before.st_mode & S_IFMT {
        case S_IFDIR:
            try fm.createDirectory(at: target, withIntermediateDirectories: false)
            for child in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
                try safeCopy(child, target.appendingPathComponent(child.lastPathComponent), task: task, depth: depth + 1)
            }
        case S_IFREG:
            let input = open(source.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
            guard input >= 0 else { throw fail("Cannot safely open source.") }; defer { close(input) }
            var opened = stat(); guard fstat(input, &opened) == 0, signature(before) == signature(opened) else { throw fail("Source changed before copying.") }
            let output = open(target.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, before.st_mode & 0o777)
            guard output >= 0 else { throw fail("Destination already exists or cannot be created.") }; defer { close(output) }
            var buffer = [UInt8](repeating: 0, count: 262144)
            while true {
                try check(task); let count = read(input, &buffer, buffer.count)
                if count < 0 && errno == EINTR { continue }
                guard count >= 0 else { throw fail("Source read failed.") }; if count == 0 { break }
                var offset = 0
                while offset < count {
                    let written = buffer.withUnsafeBytes { write(output, $0.baseAddress!.advanced(by: offset), count - offset) }
                    if written < 0 && errno == EINTR { continue }
                    guard written > 0 else { throw fail("Destination write failed.") }; offset += written
                }
            }
            guard fsync(output) == 0 else { throw fail("Destination flush failed.") }
        default: throw fail("Links and special files are not copied.")
        }
        guard signature(before) == signature(try statAt(source)) else { throw fail("Source changed while copying.") }
        try fm.setAttributes([.posixPermissions: NSNumber(value: before.st_mode & 0o777), .modificationDate: Date(timeIntervalSince1970: Double(before.st_mtimespec.tv_sec) + Double(before.st_mtimespec.tv_nsec)/1e9)], ofItemAtPath: target.path)
    }
    private static func remoteMetadata(_ location: PaneLocation, entries: [FileEntry], task: FTPTask) throws -> [String:FTPEntry] {
        guard case .ftp(let client, _) = location else { return [:] }
        var result: [String:FTPEntry] = [:]
        func walk(_ path: String, _ value: FTPEntry, _ depth: Int) throws {
            try check(task); guard depth <= 64, result.count < 20000 else { throw fail("Remote tree limit exceeded.") }
            guard value.kind == .file || value.kind == .directory else { throw fail("Remote links or unknown types are not transferred.") }
            result[path] = value
            if value.kind == .directory { for child in try client.list(path: path, task: task) { try walk(FTPClient.childPath(path, name: child.name), child, depth + 1) } }
        }
        let top = try client.list(path: providerPath(location), task: task)
        for entry in entries {
            let path = try location.selectedPath(entry)
            guard let value = top.first(where: { $0.name == entry.name }) else { throw fail("Source disappeared.") }
            try walk(path, value, 0)
        }
        return result
    }
    private static func stage(_ entries: [FileEntry], from source: PaneLocation, into root: URL, task: FTPTask) throws -> [URL] {
        try check(task)
        if case .local = source {
            for entry in entries { _ = try source.selectedPath(entry); try safeCopy(entry.url, root.appendingPathComponent(entry.name), task: task) }
        } else { _ = try source.export(entries, to: root, task: task) }
        try check(task); return entries.map { root.appendingPathComponent($0.name) }
    }
    static func transfer(entries: [FileEntry], source: PaneLocation, target: PaneLocation, move: Bool,
                         task: FTPTask = FTPTask(), progress: ((String) -> Void)? = nil,
                         archiveCommit: ((ArchiveBrowserSession, ArchiveBrowserSession) throws -> ArchiveBrowserSession)? = nil) throws -> ProviderTransferResult {
        var result = ProviderTransferResult()
        let root = fm.temporaryDirectory.appendingPathComponent("provider-transfer-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: root) }
        do {
            try check(task)
            guard !entries.isEmpty, Set(entries.map(\.name)).count == entries.count else { throw fail("Select distinct source items.") }
            let paths = try entries.map { try source.selectedPath($0) }
            guard !entries.contains(where: { $0.isSymbolicLink }) else { throw fail("Symbolic links are not supported in provider transfers.") }
            let targetNames = try target.list(showHidden: true, task: task).map(\.name)
            guard entries.allSatisfy({ !targetNames.contains($0.name) }) else { throw fail("A destination item already exists. Nothing was overwritten.") }
            if case .local = source {
                let destination: URL?
                switch target { case .local(let url): destination = url; case .archive(let session, _): destination = session.original; case .ftp: destination = nil }
                if let destination {
                    let path = destination.resolvingSymlinksInPath().path
                    for entry in entries { let from = entry.url.resolvingSymlinksInPath().path; guard path != from, !path.hasPrefix(from + "/") else { throw fail("Destination is inside the selected source.") } }
                }
            }
            if case .ftp(let a, _) = source, case .ftp(let b, _) = target,
               a.profile.host.lowercased() == b.profile.host.lowercased(), a.profile.port == b.profile.port, a.profile.username == b.profile.username {
                for path in paths { guard providerPath(target) != path, !providerPath(target).hasPrefix(path + "/") else { throw fail("Remote destination is inside the source.") } }
            }
            if case .archive(let a, _) = source, case .archive(let b, let targetPath) = target,
               a.original.resolvingSymlinksInPath() == b.original.resolvingSymlinksInPath() {
                for path in paths { guard targetPath != path, !targetPath.hasPrefix(path + "/") else { throw fail("Archive destination is inside the selected source.") } }
            }
            let beforeRemote = try remoteMetadata(source, entries: entries, task: task)
            var beforeLocal: [String:Fingerprint] = [:]
            if case .local = source { for entry in entries { beforeLocal[entry.name] = try fingerprint(entry.url, task: task) } }
            let staging = root.appendingPathComponent("stage"); try fm.createDirectory(at: staging, withIntermediateDirectories: false)
            progress?("Staging source items")
            let staged = try stage(entries, from: source, into: staging, task: task)
            var expected: [String:Fingerprint] = [:]
            for url in staged { expected[url.lastPathComponent] = try fingerprint(url, task: task) }
            guard beforeRemote == (try remoteMetadata(source, entries: entries, task: task)) else { throw fail("Remote source changed while downloading.") }
            for entry in entries where beforeLocal[entry.name] != nil {
                guard beforeLocal[entry.name] == (try fingerprint(entry.url, task: task)), beforeLocal[entry.name]?.content == expected[entry.name]?.content else { throw fail("Local source changed during staging.") }
            }
            try check(task); progress?("Copying staged items to destination")
            var effectiveTarget = target
            switch target {
            case .local(let destination):
                for url in staged {
                    let temporary = destination.appendingPathComponent(".provider-copy-" + UUID().uuidString)
                    defer { try? fm.removeItem(at: temporary) }
                    try safeCopy(url, temporary, task: task)
                    try check(task); try fm.moveItem(at: temporary, to: destination.appendingPathComponent(url.lastPathComponent)); result.copiedCount += 1
                }
            case .ftp(let client, _):
                for url in staged { try client.uploadTree(localURL: url, remotePath: FTPClient.childPath(providerPath(target), name: url.lastPathComponent), task: task); result.copiedCount += 1 }
            case .archive(let session, let path):
                let stagedReplacement = try ArchiveMutationService.add(session: session, sources: staged, at: path, overwrite: false)
                let replacement = try archiveCommit?(session, stagedReplacement) ?? stagedReplacement
                result.updatedArchiveSessions.append(.init(previous: session, replacement: replacement)); effectiveTarget = .archive(replacement, path: path); result.copiedCount = entries.count
            }
            try check(task); progress?("Verifying destination contents")
            let destinationEntries = try effectiveTarget.list(showHidden: true, task: task).filter { expected[$0.name] != nil }
            guard destinationEntries.count == entries.count else { throw fail("Destination inventory changed during transfer.") }
            let verification = root.appendingPathComponent("destination-check"); try fm.createDirectory(at: verification, withIntermediateDirectories: false)
            let verified = try stage(destinationEntries, from: effectiveTarget, into: verification, task: task)
            for url in verified { guard try fingerprint(url, task: task).content == expected[url.lastPathComponent]?.content else { throw fail("Destination content verification failed. Sources retained.") } }
            guard move else { return result }
            try check(task); progress?("Rechecking sources before removal")
            var effectiveSource = source
            if case .archive(let original, let path) = source, case .archive(let replacement, _) = effectiveTarget, original.original == replacement.original { effectiveSource = .archive(replacement, path: path) }
            let currentEntries = try effectiveSource.list(showHidden: true, task: task).filter { expected[$0.name] != nil }
            guard currentEntries.count == entries.count else { throw fail("Source inventory changed; sources retained.") }
            guard beforeRemote == (try remoteMetadata(source, entries: entries, task: task)) else { throw fail("Remote source metadata changed; sources retained.") }
            let sourceCheck = root.appendingPathComponent("source-check"); try fm.createDirectory(at: sourceCheck, withIntermediateDirectories: false)
            for url in try stage(currentEntries, from: effectiveSource, into: sourceCheck, task: task) {
                guard try fingerprint(url, task: task).content == expected[url.lastPathComponent]?.content else { throw fail("Source contents changed; sources retained.") }
            }
            for entry in entries where beforeLocal[entry.name] != nil { guard beforeLocal[entry.name] == (try fingerprint(entry.url, task: task)) else { throw fail("Local source metadata changed; sources retained.") } }
            guard beforeRemote == (try remoteMetadata(source, entries: entries, task: task)) else { throw fail("Remote source changed during recheck; sources retained.") }
            try check(task)
            switch effectiveSource {
            case .local:
                for entry in entries {
                    try check(task)
                    let quarantine = entry.url.deletingLastPathComponent().appendingPathComponent(".provider-move-" + UUID().uuidString)
                    try fm.moveItem(at: entry.url, to: quarantine)
                    do {
                        // Rename changes ctime, so compare complete bytes/tree after isolating the path.
                        guard try fingerprint(quarantine, task: task).content == expected[entry.name]?.content else { throw fail("Source changed before removal.") }
                        try check(task); try fm.removeItem(at: quarantine); result.movedCount += 1
                    } catch {
                        do { try fm.moveItem(at: quarantine, to: entry.url) } catch { throw fail("Source preserved at recovery path: " + quarantine.path) }
                        throw error
                    }
                }
            case .ftp(let client, _):
                for path in paths { try check(task); try client.delete(remotePath: path, recursive: true, task: task); result.movedCount += 1 }
            case .archive(let session, _):
                let stagedReplacement = try ArchiveMutationService.delete(session: session, paths: paths)
                let replacement = try archiveCommit?(session, stagedReplacement) ?? stagedReplacement
                result.updatedArchiveSessions.append(.init(previous: session, replacement: replacement)); result.movedCount = entries.count
            }
            return result
        } catch { throw ProviderTransferFailure(result: result, reason: error.localizedDescription) }
    }
}
