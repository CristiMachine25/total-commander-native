import Foundation

/// Injectable transport keeps stale-write behavior testable without a remote account.
protocol RemoteEditTransport {
    func metadata(path: String, task: FTPTask) throws -> FTPEntry
    func fetch(path: String, to: URL, task: FTPTask) throws
    func replace(path: String, from: URL, task: FTPTask) throws
}

struct FTPRemoteEditTransport: RemoteEditTransport {
    let client: FTPClient
    func metadata(path: String, task: FTPTask) throws -> FTPEntry {
        let parent = (path as NSString).deletingLastPathComponent, name = (path as NSString).lastPathComponent
        guard let entry = try client.list(path: parent, task: task).first(where: { $0.name == name }), entry.kind == .file else {
            throw RemoteEditError.notRegular
        }
        return entry
    }
    func fetch(path: String, to: URL, task: FTPTask) throws { try client.download(remotePath: path, to: to, task: task, maxBytes: UInt64(FTPRemoteEditSession.maximumBytes)) }
    func replace(path: String, from: URL, task: FTPTask) throws { try client.upload(localFile: from, remotePath: path, overwrite: true, task: task) }
}

enum RemoteEditError: LocalizedError {
    case notRegular, tooLarge, conflict, closed, verification
    var errorDescription: String? {
        switch self {
        case .notRegular: return "Remote editing requires a regular file."
        case .tooLarge: return "Remote text editing is limited to 4 MiB."
        case .conflict: return "The remote file changed. It was not overwritten; your local edits remain available."
        case .closed: return "This remote edit session has closed."
        case .verification: return "The uploaded contents could not be verified. Keep your local copy and check the remote file before retrying."
        }
    }
}

/// All network methods are synchronous: call off the main thread. Retain until editor closes.
/// Never automatically deletes pending local changes, including on upload failure.
final class FTPRemoteEditSession {
    static let maximumBytes = 4 * 1024 * 1024
    let localURL: URL
    let remotePath: String
    private let directory: URL, transport: RemoteEditTransport
    private let lock = NSRecursiveLock()
    private var baseline: Data
    private var baselineMetadata: FTPEntry
    private var closed = false

    static func prepare(client: FTPClient, remotePath: String, task: FTPTask = FTPTask()) throws -> FTPRemoteEditSession {
        try prepare(transport: FTPRemoteEditTransport(client: client), remotePath: remotePath, task: task)
    }
    static func prepare(transport: RemoteEditTransport, remotePath: String, task: FTPTask = FTPTask()) throws -> FTPRemoteEditSession {
        let path = try FTPClient.normalizedPath(remotePath)
        guard path != "/" else { throw RemoteEditError.notRegular }
        if task.isCancelled { throw FTPError.cancelled }
        let before = try transport.metadata(path: path, task: task)
        try validate(before)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("remote-edit-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            let local = directory.appendingPathComponent((path as NSString).lastPathComponent)
            try transport.fetch(path: path, to: local, task: task)
            let bytes = try read(local)
            let after = try transport.metadata(path: path, task: task)
            guard before == after else { throw RemoteEditError.conflict }
            return FTPRemoteEditSession(directory: directory, localURL: local, remotePath: path, transport: transport, baseline: bytes, metadata: after)
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
    private init(directory: URL, localURL: URL, remotePath: String, transport: RemoteEditTransport, baseline: Data, metadata: FTPEntry) {
        self.directory = directory; self.localURL = localURL; self.remotePath = remotePath
        self.transport = transport; self.baseline = baseline; self.baselineMetadata = metadata
    }
    private static func validate(_ entry: FTPEntry) throws {
        guard entry.kind == .file else { throw RemoteEditError.notRegular }
        guard let size = entry.size, size <= UInt64(maximumBytes) else { throw RemoteEditError.tooLarge }
    }
    private static func read(_ url: URL) throws -> Data {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw RemoteEditError.notRegular }
        guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= maximumBytes else { throw RemoteEditError.tooLarge }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var data = Data()
        while data.count <= maximumBytes {
            let chunk = try handle.read(upToCount: min(65536, maximumBytes + 1 - data.count)) ?? Data()
            if chunk.isEmpty { break }; data.append(chunk)
        }
        guard data.count <= maximumBytes else { throw RemoteEditError.tooLarge }; return data
    }
    var hasPendingChanges: Bool {
        lock.lock(); defer { lock.unlock() }
        return !closed && (try? Self.read(localURL)) != baseline
    }
    /// Caller must request replacement consent before calling. FTP cannot make compare+STOR atomic.
    @discardableResult func uploadSavedChanges(task: FTPTask = FTPTask()) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { throw RemoteEditError.closed }
        if task.isCancelled { throw FTPError.cancelled }
        let edited = try Self.read(localURL)
        guard edited != baseline else { return false }
        let check = directory.appendingPathComponent(".remote-check-" + UUID().uuidString)
        let snapshot = directory.appendingPathComponent(".upload-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: check); try? FileManager.default.removeItem(at: snapshot) }
        let metadata = try transport.metadata(path: remotePath, task: task)
        try Self.validate(metadata)
        guard metadata == baselineMetadata else { throw RemoteEditError.conflict }
        try transport.fetch(path: remotePath, to: check, task: task)
        guard try Self.read(check) == baseline, try transport.metadata(path: remotePath, task: task) == baselineMetadata else { throw RemoteEditError.conflict }
        try edited.write(to: snapshot, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: snapshot.path)
        if task.isCancelled { throw FTPError.cancelled }
        try transport.replace(path: remotePath, from: snapshot, task: task)
        try FileManager.default.removeItem(at: check)
        do {
            let before = try transport.metadata(path: remotePath, task: task); try Self.validate(before)
            try transport.fetch(path: remotePath, to: check, task: task)
            let after = try transport.metadata(path: remotePath, task: task)
            guard try Self.read(check) == edited, before == after else { throw RemoteEditError.verification }
            baseline = edited; baselineMetadata = after
        } catch { throw RemoteEditError.verification }
        return true
    }
    /// Call only after close/discard confirmation. Otherwise pending edits stay at localURL for recovery.
    func discardAndClose() {
        lock.lock(); defer { lock.unlock() }; closed = true
        try? FileManager.default.removeItem(at: directory)
    }
    deinit { if !hasPendingChanges { try? FileManager.default.removeItem(at: directory) } }
}
