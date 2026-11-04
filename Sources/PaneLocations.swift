import Foundation

/// A readable local URL plus the ownership needed to keep its backing files alive.
/// Retain this object for as long as a viewer/editor uses `url`.
final class PaneReadableMaterialization {
    let url: URL
    private let owner: AnyObject?
    private let temporaryDirectory: URL?
    init(url: URL, owner: AnyObject? = nil, temporaryDirectory: URL? = nil) {
        self.url = url; self.owner = owner; self.temporaryDirectory = temporaryDirectory
    }
    deinit { if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) } }
}

enum PaneLocationError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

/// Provider calls are synchronous: run listing/materialization/transfers on a worker.
/// Serialize work for a given archive session, whose extraction cache is mutable.
/// Virtual identities are intentionally never file URLs or actual network URLs.
enum PaneLocation: Equatable {
    case local(URL)
    case archive(ArchiveBrowserSession, path: String)
    case ftp(FTPClient, path: String)

    static func == (lhs: PaneLocation, rhs: PaneLocation) -> Bool { lhs.identity == rhs.identity }
    var localDirectory: URL? { if case .local(let url) = self { return url }; return nil }
    private var virtualHost: String {
        switch self {
        case .local: return ""
        case .archive(let session, _): return session.snapshot.deletingLastPathComponent().lastPathComponent.lowercased()
        case .ftp(let client, _): return "session-" + String(UInt(bitPattern: ObjectIdentifier(client)), radix: 16)
        }
    }
    private var virtualScheme: String { if case .archive = self { return "tc-archive" }; return "tc-ftp" }
    private var providerPath: String {
        switch self {
        case .local(let url): return url.path
        case .archive(_, let path): return path
        case .ftp(_, let path): return (try? FTPClient.normalizedPath(path)) ?? path
        }
    }
    private func virtualURL(path: String) -> URL {
        var parts = URLComponents(); parts.scheme = virtualScheme; parts.host = virtualHost
        parts.path = path.hasPrefix("/") ? path : "/" + path
        return parts.url!
    }
    var identity: String {
        switch self {
        case .local(let url): return "local:" + url.standardizedFileURL.path
        default: return virtualURL(path: providerPath).absoluteString
        }
    }
    var displayPath: String {
        switch self {
        case .local(let url): return url.path
        case .archive(let session, let path): return (session.displayOrigin ?? session.original.path) + "!/" + path
        case .ftp(let client, _):
            let scheme = client.profile.security == .plainFTP ? "ftp" : "ftps"
            return "\(scheme)://\(client.profile.host):\(client.profile.port)\(providerPath)"
        }
    }
    var parent: PaneLocation? {
        switch self {
        case .local(let url):
            let clean = url.standardizedFileURL, up = url.deletingLastPathComponent().standardizedFileURL
            return clean == up ? nil : .local(up)
        case .archive(let session, let path):
            return path.isEmpty ? .local(session.original.deletingLastPathComponent()) : .archive(session, path: (path as NSString).deletingLastPathComponent)
        case .ftp(let client, _):
            guard providerPath != "/" else { return nil }
            let path = (providerPath as NSString).deletingLastPathComponent
            return .ftp(client, path: path.isEmpty ? "/" : path)
        }
    }
    func list(showHidden: Bool, task: FTPTask = FTPTask()) throws -> [FileEntry] {
        let entries: [FileEntry]
        switch self {
        case .local(let url):
            guard url.isFileURL else { throw failure("A local pane requires a file URL.") }
            return try FileService.list(url, showHidden: showHidden)
        case .archive(let session, let path):
            entries = try session.children(in: path).map {
                FileEntry(url: virtualURL(path: $0.path), name: $0.name, isDirectory: $0.isDirectory,
                          isSymbolicLink: false, size: Int64(clamping: $0.size), modified: nil)
            }
        case .ftp(let client, _):
            entries = try client.list(path: providerPath, task: task).map {
                FileEntry(url: virtualURL(path: try FTPClient.childPath(providerPath, name: $0.name)), name: $0.name,
                          isDirectory: $0.kind == .directory, isSymbolicLink: $0.kind == .symbolicLink,
                          size: Int64(clamping: $0.size ?? 0), modified: $0.modifiedAt)
            }
        }
        return entries.filter { showHidden || !$0.name.hasPrefix(".") }.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    private func failure(_ message: String) -> PaneLocationError { .message(message) }
    func selectedPath(_ entry: FileEntry) throws -> String {
        switch self {
        case .local(let root):
            guard root.isFileURL, entry.url.isFileURL,
                  PaneLocation.local(entry.url.deletingLastPathComponent()) == PaneLocation.local(root),
                  entry.name == entry.url.lastPathComponent else { throw failure("The selected item does not belong to this local pane.") }
            return entry.url.path
        case .archive(let session, let path):
            let candidate = path.isEmpty ? entry.name : path + "/" + entry.name
            guard let node = session.node(candidate), node.name == entry.name,
                  entry.url == virtualURL(path: candidate), node.isDirectory == entry.isDirectory else {
                throw failure("The selected item does not belong to this archive directory.")
            }
            return candidate
        case .ftp:
            let candidate = try FTPClient.childPath(providerPath, name: entry.name)
            guard entry.url == virtualURL(path: candidate) else { throw failure("The selected item belongs to another remote directory or connection.") }
            return candidate
        }
    }
    func child(_ entry: FileEntry) throws -> PaneLocation {
        let path = try selectedPath(entry)
        guard entry.isDirectory, !entry.isSymbolicLink || localDirectory != nil else { throw failure("Choose a directory. Remote links are not traversed.") }
        switch self {
        case .local: return .local(entry.url)
        case .archive(let session, _): return .archive(session, path: path)
        case .ftp(let client, _): return .ftp(client, path: path)
        }
    }
    private func currentRemote(_ entry: FileEntry, client: FTPClient, task: FTPTask) throws -> FTPEntry {
        _ = try selectedPath(entry)
        guard let fresh = try client.list(path: providerPath, task: task).first(where: { $0.name == entry.name }),
              fresh.kind == .file || fresh.kind == .directory else { throw failure("Remote item disappeared or is an unsupported link/special item: \(entry.name)") }
        return fresh
    }
    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("native-pane-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return root
    }
    func readableMaterialization(_ entry: FileEntry, task: FTPTask = FTPTask(), maxBytes: UInt64? = nil) throws -> PaneReadableMaterialization {
        let path = try selectedPath(entry)
        if let maxBytes,entry.size > 0,UInt64(entry.size)>maxBytes {throw failure("File exceeds preview download limit.")}
        guard !entry.isDirectory else { throw failure("Choose a file to view.") }
        switch self {
        case .local: return PaneReadableMaterialization(url: entry.url)
        case .archive(let session, _): return PaneReadableMaterialization(url: try session.readableMember(path), owner: session)
        case .ftp(let client, _):
            guard try currentRemote(entry, client: client, task: task).kind == .file else { throw failure("Choose a regular remote file.") }
            let root = try temporaryDirectory(), url = root.appendingPathComponent(entry.name)
            do {
                try client.download(remotePath: path, to: url, task: task, maxBytes:maxBytes)
                return PaneReadableMaterialization(url: url, owner: client, temporaryDirectory: root)
            } catch { try? FileManager.default.removeItem(at: root); throw error }
        }
    }
    /// Copies selected immediate children into the local target, never overwriting.
    /// Remote/archive members are staged fully before the local transfer begins.
    @discardableResult func export(_ entries: [FileEntry], to destination: URL, task: FTPTask = FTPTask()) throws -> Int {
        guard destination.isFileURL, !entries.isEmpty else { throw failure("Select items and an ordinary local destination directory.") }
        let values = try destination.resourceValues(forKeys: [.isDirectoryKey,.isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw failure("Choose an ordinary local destination directory.") }
        let paths = try entries.map { try selectedPath($0) }
        guard Set(paths).count == paths.count else { throw failure("Duplicate selected items.") }
        if case .local = self { try FileService.transfer(entries.map(\.url), to: destination, move: false); return entries.count }
        let stage = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: stage) }
        let sources: [URL]
        switch self {
        case .archive(let session, _):
            _ = try session.extract(paths: paths, to: stage)
            sources = paths.map { stage.appendingPathComponent($0) }
        case .ftp(let client, _):
            for (entry, path) in zip(entries, paths) {
                _ = try currentRemote(entry, client: client, task: task)
                try client.downloadTree(remotePath: path, to: stage.appendingPathComponent(entry.name), task: task)
            }
            sources = entries.map { stage.appendingPathComponent($0.name) }
        case .local: fatalError("Handled above")
        }
        try FileService.transfer(sources, to: destination, move: false)
        return entries.count
    }
    @discardableResult func upload(_ sources: [URL], task: FTPTask = FTPTask()) throws -> Int {
        guard case .ftp(let client, _) = self else { throw failure("Uploads require an FTP destination. Archive modification is not supported.") }
        guard !sources.isEmpty, sources.allSatisfy(\.isFileURL) else { throw failure("Select local files or folders to upload.") }
        var names = Set<String>()
        for source in sources { guard names.insert(source.lastPathComponent).inserted else { throw failure("Duplicate upload names.") }; _ = try FTPClient.childPath(providerPath,name:source.lastPathComponent) }
        var completed = 0
        do {
            for source in sources {
                try client.uploadTree(localURL: source, remotePath: FTPClient.childPath(providerPath,name:source.lastPathComponent), task: task)
                completed += 1
            }
            return completed
        } catch { throw failure("Uploaded \(completed) item(s) before stopping. Completed remote items remain.\n\(error.localizedDescription)") }
    }
    func makeDirectory(name: String, task: FTPTask = FTPTask()) throws {
        switch self {
        case .local(let root): try FileService.makeDirectory(in: root, name: name)
        case .ftp(let client, _): try client.createDirectory(path: FTPClient.childPath(providerPath,name:name),task:task)
        case .archive: throw failure("ZIP browsing is read-only; creating folders inside an archive is not supported.")
        }
    }
    func rename(_ entry: FileEntry, toName name: String, task: FTPTask = FTPTask()) throws {
        let path = try selectedPath(entry)
        switch self {
        case .local: try FileService.rename(entry.url,toName:name)
        case .ftp(let client, _): try client.rename(from:path,to:FTPClient.childPath(providerPath,name:name),task:task)
        case .archive: throw failure("Renaming archive members is not supported.")
        }
    }
    func trash(_ entries: [FileEntry]) throws {
        guard case .local = self else { throw failure("Trash is available only for local files. Remote deletion is permanent and requires separate confirmation.") }
        for entry in entries { _ = try selectedPath(entry) }
        try FileService.trash(entries.map(\.url))
    }
}
