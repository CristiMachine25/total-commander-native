import AppKit

struct FTPProfile: Codable, Equatable, Identifiable {
    enum Security: String, Codable, CaseIterable { case plainFTP, explicitTLS, implicitTLS }
    var id = UUID()
    var name = "New connection"
    var host = ""
    var port = 21
    var username = "anonymous"
    var security: Security = .explicitTLS
    var initialPath = "/"
}

struct FTPEntry: Equatable {
    enum Kind: String { case file, directory, symbolicLink, unknown }
    let name: String
    let kind: Kind
    let size: UInt64?
    let modifiedAt: Date?
}

enum FTPError: LocalizedError {
    case message(String), cancelled
    var errorDescription: String? {
        switch self { case .message(let message): return message; case .cancelled: return "Transfer cancelled." }
    }
}

final class FTPTask: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    private var process: Process?
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    func cancel() {
        lock.lock(); stopped = true; let current = process; lock.unlock()
        if current?.isRunning == true { current?.terminate() }
    }
    fileprivate func attach(_ value: Process?) throws {
        lock.lock(); process = value; let cancelled = stopped; lock.unlock()
        if cancelled { throw FTPError.cancelled }
    }
}

/// Passwords are deliberately absent from FTPProfile and profile persistence.
struct FTPProfileStore {
    let file: URL
    init(file: URL? = nil) {
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Total Commander Native/FTP-profiles.json")
    }
    func load() throws -> [FTPProfile] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        return try JSONDecoder().decode([FTPProfile].self, from: Data(contentsOf: file))
    }
    func save(_ profiles: [FTPProfile]) throws {
        for profile in profiles { try FTPClient.validate(profile) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(profiles).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}

final class FTPClient {
    let profile: FTPProfile
    private let password: String
    private let executable: URL
    init(profile: FTPProfile, password: String, executable: URL = URL(fileURLWithPath: "/usr/bin/curl")) throws {
        try Self.validate(profile)
        guard !Self.hasControls(password), password.utf8.count <= 4096 else { throw FTPError.message("Password contains unsupported control characters or is too long.") }
        self.profile = profile; self.password = password; self.executable = executable
    }
    private static func hasControls(_ value: String) -> Bool { value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) } }
    static func validate(_ profile: FTPProfile) throws {
        guard !profile.host.isEmpty, profile.host.utf8.count <= 253,
              !hasControls(profile.host), !profile.host.contains(where: { "/\\@?# \t".contains($0) }),
              (1...65535).contains(profile.port), !profile.username.contains(":"),
              !hasControls(profile.username), profile.username.utf8.count <= 4096,
              !hasControls(profile.name), profile.name.utf8.count <= 1024 else {
            throw FTPError.message("Enter a host name or IP address, valid port, and username without URL syntax or control characters.")
        }
        _ = try normalizedPath(profile.initialPath)
    }
    static func normalizedPath(_ value: String) throws -> String {
        guard value.hasPrefix("/"), !hasControls(value), !value.contains("\\"), value.utf8.count <= 8192 else {
            throw FTPError.message("Remote paths must start with / and contain no control characters or backslashes.")
        }
        var components: [Substring] = []
        for part in value.split(separator: "/") {
            if part == "." { continue }
            if part == ".." { if !components.isEmpty { components.removeLast() }; continue }
            components.append(part)
        }
        return "/" + components.joined(separator: "/")
    }
    static func childPath(_ folder: String, name: String) throws -> String {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\"), !hasControls(name) else { throw FTPError.message("Enter a single remote filename without separators or control characters.") }
        return try normalizedPath(folder + "/" + name)
    }
    private func remoteURL(_ path: String, directory: Bool) throws -> String {
        let normalized = try Self.normalizedPath(path)
        var url = URLComponents(); url.scheme = profile.security == .implicitTLS ? "ftps" : "ftp"
        url.host = profile.host; url.port = profile.port
        // FTP /%2F means absolute server root, independent of the login directory.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~/"))
        let encoded = normalized.dropFirst().addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        url.percentEncodedPath = "/%2F" + encoded + (directory && !encoded.isEmpty ? "/" : "")
        guard let result = url.url?.absoluteString else { throw FTPError.message("Invalid FTP address.") }
        return result
    }
    private func quote(_ value: String) throws -> String {
        guard !Self.hasControls(value) else { throw FTPError.message("Unsupported control character in transfer settings.") }
        return "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
    /// Only used by tests to verify arguments cannot expose a secret; actual configuration goes through stdin.
    static var processArguments: [String] { ["--disable", "--config", "-"] }

    private func run(path: String, directory: Bool, commands: [String] = [], upload: URL? = nil,
                     download: URL? = nil, listing: Bool = false, task: FTPTask, maxBytes: UInt64? = nil) throws -> Data {
        if task.isCancelled { throw FTPError.cancelled }
        var lines = ["silent", "show-error", "globoff", "connect-timeout = 15", "max-time = 600", "ftp-pasv",
                     "proxy = \"\"", "proto = \"=ftp,ftps\"", "url = \(try remoteURL(path, directory: directory).quotedForCurl())",
                     "user = \(try quote(profile.username + ":" + password))"]
        if profile.security != .plainFTP { lines.append("ssl-reqd") }
        if listing { lines.append("request = \"MLSD\""); lines.append("max-time = 120") }
        if let maxBytes { lines.append("max-filesize = \(max(1, min(maxBytes, UInt64(Int64.max))))") }
        if let upload { lines.append("upload-file = \(try quote(upload.path))") }
        for command in commands { lines.append("quote = \(try quote(command))") }
        if !commands.isEmpty { lines.append("head") }
        let process = Process(); process.executableURL = executable; process.arguments = Self.processArguments
        // No passwords in environment, arguments, a temporary config file or application logs.
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": FileManager.default.homeDirectoryForCurrentUser.path, "LC_ALL": "en_US.UTF-8"]
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin; process.standardError = stderr
        let outputFile: FileHandle?
        if let download { outputFile = try FileHandle(forWritingTo: download); process.standardOutput = outputFile }
        else { outputFile = nil; process.standardOutput = stdout }
        defer { try? outputFile?.close(); try? stdin.fileHandleForWriting.close(); try? task.attach(nil) }
        try task.attach(process); try process.run()
        if task.isCancelled { process.terminate() }
        let group = DispatchGroup(), capture = FTPCapture()
        if download == nil {
            group.enter(); DispatchQueue.global().async {
                defer { group.leave() }
                while let data = try? stdout.fileHandleForReading.read(upToCount: 65536), !data.isEmpty {
                    if !capture.append(data, error: false, limit: 16 * 1024 * 1024), process.isRunning { process.terminate() }
                }
            }
        }
        group.enter(); DispatchQueue.global().async {
            defer { group.leave() }
            while let data = try? stderr.fileHandleForReading.read(upToCount: 4096), !data.isEmpty { _ = capture.append(data, error: true, limit: 65536) }
        }
        do { try stdin.fileHandleForWriting.write(contentsOf: Data((lines.joined(separator: "\n") + "\n").utf8)); try stdin.fileHandleForWriting.close() }
        catch { if process.isRunning { process.terminate() }; process.waitUntilExit(); group.wait(); throw FTPError.message("Could not pass transfer settings to curl.") }
        process.waitUntilExit(); group.wait()
        if task.isCancelled { throw FTPError.cancelled }
        if capture.overflow { throw FTPError.message("The remote directory listing exceeds the supported 16 MiB limit.") }
        guard process.terminationStatus == 0 else {
            var detail = String(data: capture.errors, encoding: .utf8) ?? "Transfer failed."
            if !password.isEmpty { detail = detail.replacingOccurrences(of: password, with: "[redacted]") }
            throw FTPError.message("FTP operation failed (curl \(process.terminationStatus)): \(detail.prefix(2000))")
        }
        return capture.output
    }
    static func parseMLSD(_ data: Data) throws -> [FTPEntry] {
        guard let text = String(data: data, encoding: .utf8) else { throw FTPError.message("This server listing is not UTF-8. Legacy FTP encodings are not supported yet.") }
        var result: [FTPEntry] = [], seen = Set<String>()
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyyMMddHHmmss"; formatter.isLenient = false
        for raw in text.components(separatedBy: "\n") {
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
            if line.isEmpty { continue }
            guard let separator = line.firstIndex(of: " ") else { throw FTPError.message("The server did not return a valid MLSD directory listing.") }
            let factText = line[..<separator], name = String(line[line.index(after: separator)...])
            var facts: [String:String] = [:]
            for pair in factText.split(separator: ";") {
                guard let equal = pair.firstIndex(of: "=") else { throw FTPError.message("Malformed MLSD facts.") }
                facts[String(pair[..<equal]).lowercased()] = String(pair[pair.index(after: equal)...])
            }
            guard let type = facts["type"]?.lowercased() else { throw FTPError.message("MLSD entry omitted its type.") }
            if type == "cdir" || type == "pdir" { continue }
            _ = try childPath("/", name: name)
            guard seen.insert(name).inserted else { throw FTPError.message("Remote listing contains duplicate filenames.") }
            let kind: FTPEntry.Kind = type == "file" ? .file : (type == "dir" ? .directory : (type.hasPrefix("os.unix=slink") ? .symbolicLink : .unknown))
            let size = facts["size"].flatMap(UInt64.init)
            if facts["size"] != nil && size == nil { throw FTPError.message("Invalid MLSD file size.") }
            let modified = facts["modify"].flatMap { formatter.date(from: String($0.prefix(14))) }
            result.append(FTPEntry(name: name, kind: kind, size: size, modifiedAt: modified))
        }
        return result.sorted { a,b in (a.kind == .directory) != (b.kind == .directory) ? a.kind == .directory : a.name.localizedStandardCompare(b.name) == .orderedAscending }
    }
    func list(path: String, task: FTPTask = FTPTask()) throws -> [FTPEntry] {
        try Self.parseMLSD(run(path: path, directory: true, listing: true, task: task))
    }
    func download(remotePath: String, to destination: URL, task: FTPTask = FTPTask(), maxBytes: UInt64? = nil) throws {
        let fm = FileManager.default
        guard destination.isFileURL, (try? fm.attributesOfItem(atPath: destination.path)) == nil else { throw FTPError.message("The download destination already exists or is not a local file.") }
        if let maxBytes {
            let remote = try Self.normalizedPath(remotePath)
            let entry = try list(path: (remote as NSString).deletingLastPathComponent, task: task).first { $0.name == (remote as NSString).lastPathComponent }
            guard let entry, entry.kind == .file, let size = entry.size, size <= maxBytes else { throw FTPError.message("Remote file is not regular or exceeds the download size limit.") }
        }
        let parent = destination.deletingLastPathComponent()
        let temporary = parent.appendingPathComponent(".ftp-download-" + UUID().uuidString)
        guard fm.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw FTPError.message("Cannot create a temporary download in the destination folder.") }
        defer { try? fm.removeItem(at: temporary) }
        _ = try run(path: remotePath, directory: false, download: temporary, task: task, maxBytes: maxBytes)
        if let maxBytes {
            let size = (try fm.attributesOfItem(atPath: temporary.path)[.size] as? NSNumber)?.uint64Value ?? UInt64.max
            guard size <= maxBytes else { throw FTPError.message("Downloaded file exceeds the size limit.") }
        }
        // moveItem refuses an existing destination; no clobber on a concurrent creator.
        try fm.moveItem(at: temporary, to: destination)
    }
    func upload(localFile: URL, remotePath: String, overwrite: Bool = false, task: FTPTask = FTPTask()) throws {
        let fm = FileManager.default
        guard localFile.isFileURL, try fm.attributesOfItem(atPath: localFile.path)[.type] as? FileAttributeType == .typeRegular else { throw FTPError.message("Select a regular local file to upload.") }
        let remote = try Self.normalizedPath(remotePath), parent = (remote as NSString).deletingLastPathComponent, name = (remote as NSString).lastPathComponent
        _ = try Self.childPath(parent, name: name)
        let existing = try list(path: parent, task: task).first { $0.name == name }
        if let existing {
            guard overwrite, existing.kind == .file else { throw FTPError.message("Remote destination already exists: \(name)") }
        }
        // STOR has no portable exclusive-create primitive: caller explicitly controls overwrite consent.
        _ = try run(path: remote, directory: false, upload: localFile, task: task)
    }
    func createDirectory(path: String, task: FTPTask = FTPTask()) throws {
        let path = try Self.normalizedPath(path)
        guard path != "/" else { throw FTPError.message("Choose a new folder name.") }
        _ = try run(path: "/", directory: true, commands: ["MKD " + path], task: task)
    }
    func rename(from source: String, to destination: String, task: FTPTask = FTPTask()) throws {
        let source = try Self.normalizedPath(source), destination = try Self.normalizedPath(destination)
        guard source != "/", destination != "/", source != destination else { throw FTPError.message("Choose a different remote name.") }
        let parent = (destination as NSString).deletingLastPathComponent, name = (destination as NSString).lastPathComponent
        guard !(try list(path: parent, task: task)).contains(where: { $0.name == name }) else { throw FTPError.message("Remote rename destination already exists.") }
        _ = try run(path: "/", directory: true, commands: ["RNFR " + source, "RNTO " + destination], task: task)
    }
}


/// Tree operations preflight a bounded inventory, never follow links, and never silently overwrite.
/// Remote servers can change after preflight; FTP cannot provide atomic tree mutations.
extension FTPClient {
    private struct TreeItem { let path: String; let relative: String; let directory: Bool }
    private func remoteTree(_ path: String, task: FTPTask, allowLinks: Bool = false) throws -> [TreeItem] {
        let root = try Self.normalizedPath(path)
        guard root != "/" else { throw FTPError.message("Select an item, not the remote root.") }
        let parent = (root as NSString).deletingLastPathComponent, name = (root as NSString).lastPathComponent
        guard let entry = try list(path: parent, task: task).first(where: { $0.name == name }) else { throw FTPError.message("Remote item no longer exists.") }
        var result: [TreeItem] = []
        func walk(_ path: String, _ relative: String, _ entry: FTPEntry, _ depth: Int) throws {
            if task.isCancelled { throw FTPError.cancelled }
            guard depth <= 64, result.count < 20000 else { throw FTPError.message("Tree exceeds the limit of 64 levels or 20,000 items.") }
            guard entry.kind == .file || entry.kind == .directory || (allowLinks && entry.kind == .symbolicLink) else {
                throw FTPError.message("Symbolic links and unknown remote item types are not followed: " + entry.name)
            }
            result.append(TreeItem(path: path, relative: relative, directory: entry.kind == .directory))
            if entry.kind == .directory {
                for child in try list(path: path, task: task) {
                    try walk(Self.childPath(path, name: child.name), relative.isEmpty ? child.name : relative + "/" + child.name, child, depth + 1)
                }
            }
        }
        try walk(root, "", entry, 0); return result
    }
    func downloadTree(remotePath: String, to destination: URL, task: FTPTask = FTPTask()) throws {
        let fm = FileManager.default
        guard destination.isFileURL, (try? fm.attributesOfItem(atPath: destination.path)) == nil else { throw FTPError.message("Local destination already exists.") }
        let items = try remoteTree(remotePath, task: task)
        guard items[0].directory else { try download(remotePath: remotePath, to: destination, task: task); return }
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".ftp-tree-" + UUID().uuidString)
        try fm.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: temporary) }
        for item in items.dropFirst() {
            if task.isCancelled { throw FTPError.cancelled }
            let local = temporary.appendingPathComponent(item.relative)
            if item.directory { try fm.createDirectory(at: local, withIntermediateDirectories: false) }
            else { try download(remotePath: item.path, to: local, task: task) }
        }
        if task.isCancelled { throw FTPError.cancelled }
        try fm.moveItem(at: temporary, to: destination)
    }
    func uploadTree(localURL: URL, remotePath: String, task: FTPTask = FTPTask()) throws {
        let fm = FileManager.default, remote = try Self.normalizedPath(remotePath)
        guard localURL.isFileURL, remote != "/" else { throw FTPError.message("Choose a local item and a new remote destination.") }
        var items: [TreeItem] = []
        func walk(_ url: URL, _ relative: String, _ depth: Int) throws {
            if task.isCancelled { throw FTPError.cancelled }
            guard depth <= 64, items.count < 20000 else { throw FTPError.message("Tree exceeds the limit of 64 levels or 20,000 items.") }
            let type = try fm.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
            guard type == .typeDirectory || type == .typeRegular else { throw FTPError.message("Symbolic links and special files are not uploaded: " + url.lastPathComponent) }
            items.append(TreeItem(path: url.path, relative: relative, directory: type == .typeDirectory))
            if type == .typeDirectory {
                for child in try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                    _ = try Self.childPath("/", name: child.lastPathComponent)
                    try walk(child, relative.isEmpty ? child.lastPathComponent : relative + "/" + child.lastPathComponent, depth + 1)
                }
            }
        }
        try walk(localURL, "", 0)
        let parent = (remote as NSString).deletingLastPathComponent, name = (remote as NSString).lastPathComponent
        guard !(try list(path: parent, task: task)).contains(where: { $0.name == name }) else { throw FTPError.message("Remote destination already exists.") }
        for item in items {
            if task.isCancelled { throw FTPError.cancelled }
            let target = item.relative.isEmpty ? remote : remote + "/" + item.relative
            if item.directory { try createDirectory(path: target, task: task) }
            else { try upload(localFile: URL(fileURLWithPath: item.path), remotePath: target, task: task) }
        }
    }
    /// Deletes permanently on the remote server; caller must obtain user confirmation.
    func delete(remotePath: String, recursive: Bool = false, task: FTPTask = FTPTask()) throws {
        let items = try remoteTree(remotePath, task: task, allowLinks: true)
        guard recursive || items.count == 1 else { throw FTPError.message("Folder is not empty; recursive deletion must be explicitly requested.") }
        for item in items.reversed() {
            if task.isCancelled { throw FTPError.cancelled }
            _ = try run(path: "/", directory: true, commands: [(item.directory ? "RMD " : "DELE ") + item.path], task: task)
        }
    }
}

private extension String {
    func quotedForCurl() throws -> String {
        guard !unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw FTPError.message("Invalid URL control character.") }
        return "\"" + replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
private final class FTPCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data(), err = Data(), exceeded = false
    var output: Data { lock.lock(); defer { lock.unlock() }; return out }
    var errors: Data { lock.lock(); defer { lock.unlock() }; return err }
    var overflow: Bool { lock.lock(); defer { lock.unlock() }; return exceeded }
    func append(_ data: Data, error: Bool, limit: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if error { err.append(data.prefix(max(0, limit - err.count))); return true }
        guard out.count + data.count <= limit else { exceeded = true; return false }
        out.append(data); return true
    }
}

/// Independent connection/browser window; no Finder or Windows runtime dependency.
final class FTPBrowserWindow: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private static var windows: [FTPBrowserWindow] = []
    /// UI lifecycle APIs are called on the main thread. Keep quit blocked until cancellation settles.
    static var hasActiveTransfers: Bool { windows.contains { $0.busy } }
    static func cancelAllTransfers() { windows.forEach { $0.task?.cancel() } }
    static func shutdown() {
        cancelAllTransfers()
        for window in windows { window.password.stringValue = ""; window.client = nil }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard busy else { return true }
        let alert = NSAlert(); alert.messageText = "A remote operation is still running."
        alert.informativeText = "Cancel it and wait for cleanup before closing. Interrupted uploads may leave a partial remote file."
        alert.addButton(withTitle: "Keep Open"); alert.addButton(withTitle: "Cancel Operation")
        if alert.runModal() == .alertSecondButtonReturn { cancel() }
        return false
    }
    private let host = NSTextField(string: ""), port = NSTextField(string: "21"), username = NSTextField(string: "anonymous")
    private let password = NSSecureTextField(string: ""), path = NSTextField(string: "/"), profileName = NSTextField(string: "New connection")
    private let security = NSPopUpButton(), saved = NSPopUpButton(), table = NSTableView()
    private let status = NSTextField(wrappingLabelWithString: "Enter an FTP server. Explicit TLS is recommended; plain FTP sends credentials without encryption.")
    private let stop = NSButton(title: "Cancel", target: nil, action: nil)
    private var actionButtons: [NSButton] = [], profiles: [FTPProfile] = [], entries: [FTPEntry] = []
    private let store = FTPProfileStore()
    private let downloadDirectory: URL
    private let onConnect: ((FTPClient, String) -> Void)?
    private var client: FTPClient?, task: FTPTask?, currentPath = "/", busy = false

    init(downloadDirectory: URL, onConnect: ((FTPClient, String) -> Void)? = nil) {
        self.downloadDirectory = downloadDirectory; self.onConnect = onConnect
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: onConnect == nil ? 620 : 245), styleMask: [.titled,.closable,.resizable,.miniaturizable], backing: .buffered, defer: false)
        window.title = "FTP Connect"; window.isReleasedWhenClosed = false
        super.init(window: window); window.delegate = self
        security.addItems(withTitles: ["FTP — unencrypted", "FTP with explicit TLS", "FTPS — implicit TLS"]); security.selectItem(at: 1)
        security.target = self; security.action = #selector(securityChanged)
        saved.addItem(withTitle: "New connection"); saved.target = self; saved.action = #selector(loadProfile)
        profiles = (try? store.load()) ?? []; profiles.forEach { saved.addItem(withTitle: $0.name) }
        host.placeholderString = "Host name or IP"; port.placeholderString = "21"; password.placeholderString = "Password (not saved)"
        profileName.placeholderString = "Profile name"
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Saved:"), saved, NSTextField(labelWithString: "Name:"), profileName],
            [NSTextField(labelWithString: "Host:"), host, NSTextField(labelWithString: "Port:"), port],
            [NSTextField(labelWithString: "User:"), username, NSTextField(labelWithString: "Password:"), password],
            [NSTextField(labelWithString: "Security:"), security, NSTextField(labelWithString: "Remote path:"), path]
        ]); grid.rowSpacing = 8; grid.columnSpacing = 10
        let connect = button("Connect / Go", #selector(connect)), save = button("Save Profile", #selector(saveProfile))
        let up = button("Up", #selector(goUp)), refresh = button("Refresh", #selector(refresh))
        let download = button("Download", #selector(downloadSelected)), upload = button("Upload", #selector(uploadFile))
        let folder = button("New Folder", #selector(newFolder)), rename = button("Rename", #selector(renameSelected))
        stop.target = self; stop.action = #selector(cancel); stop.isEnabled = false
        let controls = NSStackView(views: onConnect == nil ? [connect,save,up,refresh,download,upload,folder,rename,stop] : [connect,save,stop]); controls.spacing = 7
        for (identifier, title, width) in [("name","Name",480.0),("kind","Type",110.0),("size","Size",100.0),("modified","Modified",190.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier)); column.title = title; column.width = width; table.addTableColumn(column)
        }
        table.dataSource = self; table.delegate = self; table.rowHeight = 23; table.usesAlternatingRowBackgroundColors = true
        table.target = self; table.doubleAction = #selector(openSelected)
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        let visibleViews: [NSView] = onConnect == nil ? [grid,controls,scroll,status] : [grid,controls,status]
        let stack = NSStackView(views: visibleViews); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        window.contentView!.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        for view in visibleViews { view.translatesAutoresizingMaskIntoConstraints = false; view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor,constant: 15), stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor,constant: -15), stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor,constant: 15), stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor,constant: -15),host.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),password.widthAnchor.constraint(greaterThanOrEqualToConstant: 180)])
        if onConnect == nil { scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action); actionButtons.append(button); return button
    }
    func display() { Self.windows.append(self); window?.center(); showWindow(nil) }
    func windowWillClose(_ notification: Notification) { task?.cancel(); client = nil; password.stringValue = ""; Self.windows.removeAll { $0 === self } }
    private func profile() throws -> FTPProfile {
        guard let number = Int(port.stringValue) else { throw FTPError.message("Enter a numeric port.") }
        let selectedSecurity = FTPProfile.Security.allCases[security.indexOfSelectedItem]
        let profile = FTPProfile(name: profileName.stringValue, host: host.stringValue.trimmingCharacters(in: .whitespaces), port: number, username: username.stringValue, security: selectedSecurity, initialPath: path.stringValue)
        try FTPClient.validate(profile); return profile
    }
    @objc private func securityChanged() { port.stringValue = security.indexOfSelectedItem == 2 ? "990" : "21" }
    @objc private func loadProfile() {
        guard saved.indexOfSelectedItem > 0, profiles.indices.contains(saved.indexOfSelectedItem - 1) else { return }
        let p = profiles[saved.indexOfSelectedItem - 1]
        profileName.stringValue = p.name; host.stringValue = p.host; port.stringValue = String(p.port); username.stringValue = p.username
        security.selectItem(at: FTPProfile.Security.allCases.firstIndex(of: p.security) ?? 1); path.stringValue = p.initialPath; password.stringValue = ""
        client = nil; entries = []; table.reloadData(); status.stringValue = "Profile loaded. Enter its password, then Connect."
    }
    @objc private func saveProfile() {
        do {
            var p = try profile()
            if let index = profiles.firstIndex(where: { $0.name == p.name }) { p.id = profiles[index].id; profiles[index] = p }
            else { profiles.append(p) }
            try store.save(profiles)
            saved.removeAllItems(); saved.addItem(withTitle: "New connection"); profiles.forEach { saved.addItem(withTitle: $0.name) }
            saved.selectItem(withTitle: p.name); status.stringValue = "Profile saved without its password."
        } catch { status.stringValue = error.localizedDescription }
    }
    @objc private func connect() {
        do {
            let connection = try FTPClient(profile: profile(), password: password.stringValue)
            client = connection
            if let onConnect {
                let destination = try FTPClient.normalizedPath(path.stringValue)
                execute("Connecting…", work: { try connection.list(path: destination, task: $0) }) { [weak self] _ in
                    onConnect(connection, destination); self?.close()
                }
            } else { browse(path.stringValue) }
        }
        catch { status.stringValue = error.localizedDescription }
    }
    private func execute(_ message: String, work: @escaping (FTPTask) throws -> [FTPEntry], success: @escaping ([FTPEntry]) -> Void) {
        guard !busy else { return }
        busy = true; actionButtons.forEach { $0.isEnabled = false }; saved.isEnabled = false; stop.isEnabled = true
        let token = FTPTask(); task = token; status.stringValue = message
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try work(token) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false; self.task = nil; self.actionButtons.forEach { $0.isEnabled = true }; self.saved.isEnabled = true; self.stop.isEnabled = false
                switch result { case .success(let rows): success(rows); case .failure(let error): self.status.stringValue = error.localizedDescription }
            }
        }
    }
    private func browse(_ target: String) {
        guard let client else { status.stringValue = "Connect to a server first."; return }
        do {
            let destination = try FTPClient.normalizedPath(target)
            execute("Reading \(destination)…", work: { try client.list(path: destination, task: $0) }) { [weak self] rows in
                guard let self else { return }; self.currentPath = destination; self.path.stringValue = destination; self.entries = rows; self.table.reloadData(); self.status.stringValue = "\(rows.count) item(s) in \(destination)"
            }
        } catch { status.stringValue = error.localizedDescription }
    }
    @objc private func refresh() { browse(currentPath) }
    @objc private func goUp() { browse((currentPath as NSString).deletingLastPathComponent.isEmpty ? "/" : (currentPath as NSString).deletingLastPathComponent) }
    @objc private func cancel() { task?.cancel(); status.stringValue = "Cancelling… An interrupted upload may leave a partial remote file." }
    private var selected: FTPEntry? { entries.indices.contains(table.selectedRow) ? entries[table.selectedRow] : nil }
    @objc private func openSelected() {
        guard !busy, let selected, selected.kind == .directory else { return }
        if let next = try? FTPClient.childPath(currentPath, name: selected.name) { browse(next) }
    }
    @objc private func downloadSelected() {
        guard let client, let item = selected, item.kind == .file, let window else { status.stringValue = "Select a remote file to download."; return }
        let panel = NSSavePanel(); panel.directoryURL = downloadDirectory; panel.nameFieldStringValue = item.name; panel.title = "Download file (existing files are not overwritten)"
        let remote = try? FTPClient.childPath(currentPath, name: item.name)
        panel.beginSheetModal(for: window) { [weak self] result in
            guard let self, result == .OK, let destination = panel.url, let remote else { return }
            self.execute("Downloading \(item.name)…", work: { token in try client.download(remotePath: remote, to: destination, task: token); return [] }) { [weak self] _ in self?.status.stringValue = "Downloaded to \(destination.path)" }
        }
    }
    @objc private func uploadFile() {
        guard let client, let window else { status.stringValue = "Connect to a server first."; return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false; panel.directoryURL = downloadDirectory
        panel.beginSheetModal(for: window) { [weak self] result in
            guard let self, result == .OK, let local = panel.url, let remote = try? FTPClient.childPath(self.currentPath, name: local.lastPathComponent) else { return }
            self.execute("Uploading \(local.lastPathComponent)…", work: { token in try client.upload(localFile: local, remotePath: remote, task: token); return try client.list(path: self.currentPath, task: token) }) { [weak self] rows in self?.entries = rows; self?.table.reloadData(); self?.status.stringValue = "Upload completed." }
        }
    }
    private func prompt(_ title: String, initial: String, completion: @escaping (String) -> Void) {
        guard let window else { return }
        let alert = NSAlert(); alert.messageText = title; let field = NSTextField(string: initial); field.frame = NSRect(x: 0,y: 0,width: 330,height: 24); alert.accessoryView = field
        alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in if response == .alertFirstButtonReturn { completion(field.stringValue) } }
    }
    @objc private func newFolder() {
        guard let client else { status.stringValue = "Connect to a server first."; return }
        prompt("New remote folder", initial: "") { [weak self] name in
            guard let self else { return }
            do {
                let folder = try FTPClient.childPath(self.currentPath, name: name), parent = self.currentPath
                self.execute("Creating folder…", work: { token in try client.createDirectory(path: folder, task: token); return try client.list(path: parent, task: token) }) { [weak self] rows in self?.entries = rows; self?.table.reloadData(); self?.status.stringValue = "Folder created." }
            } catch { self.status.stringValue = error.localizedDescription }
        }
    }
    @objc private func renameSelected() {
        guard let client, let selected else { status.stringValue = "Select a remote item to rename."; return }
        prompt("Rename remote item", initial: selected.name) { [weak self] name in
            guard let self else { return }
            do {
                let from = try FTPClient.childPath(self.currentPath, name: selected.name), to = try FTPClient.childPath(self.currentPath, name: name), parent = self.currentPath
                self.execute("Renaming…", work: { token in try client.rename(from: from, to: to, task: token); return try client.list(path: parent, task: token) }) { [weak self] rows in self?.entries = rows; self?.table.reloadData(); self?.status.stringValue = "Rename completed." }
            } catch { self.status.stringValue = error.localizedDescription }
        }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard entries.indices.contains(row) else { return nil }
        let e = entries[row], value: String
        switch tableColumn?.identifier.rawValue {
        case "name": value = e.name
        case "kind": value = e.kind.rawValue
        case "size": value = e.size.map(String.init) ?? ""
        default: value = e.modifiedAt.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short) } ?? ""
        }
        let field = NSTextField(labelWithString: value); field.lineBreakMode = .byTruncatingMiddle; return field
    }
}
