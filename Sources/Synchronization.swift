import AppKit
import CryptoKit
import Darwin

enum SyncDirection: String, CaseIterable { case skip = "Skip", leftToRight = "Left → Right", rightToLeft = "Right → Left" }
enum SyncKind: String { case file, directory, symbolicLink, special }
struct SyncStamp: Equatable {
    let device: dev_t, inode: ino_t, mode: mode_t, size: off_t
    let modifiedSeconds: Int, modifiedNanos: Int, changedSeconds: Int, changedNanos: Int
    init(_ s: stat) { device=s.st_dev; inode=s.st_ino; mode=s.st_mode; size=s.st_size; modifiedSeconds=s.st_mtimespec.tv_sec; modifiedNanos=s.st_mtimespec.tv_nsec; changedSeconds=s.st_ctimespec.tv_sec; changedNanos=s.st_ctimespec.tv_nsec }
    var kind: SyncKind { switch mode & S_IFMT { case S_IFREG: return .file; case S_IFDIR: return .directory; case S_IFLNK: return .symbolicLink; default: return .special } }
    func sameIdentity(_ other: SyncStamp) -> Bool { device == other.device && inode == other.inode && kind == other.kind }
}
struct SyncEntry: Equatable { let stamp: SyncStamp; let digest: String? }
struct SyncDifference {
    let path: String, status: String
    let left: SyncEntry?, right: SyncEntry?
    var direction: SyncDirection
    func allows(_ direction: SyncDirection) -> Bool {
        if direction == .skip { return true }
        let source = direction == .leftToRight ? left : right
        let destination = direction == .leftToRight ? right : left
        guard let source, source.stamp.kind == .file || source.stamp.kind == .directory else { return false }
        return destination == nil || destination?.stamp.kind == source.stamp.kind
    }
}
struct SyncPlan {
    let leftRoot: URL, rightRoot: URL
    let leftRootStamp: SyncStamp, rightRootStamp: SyncStamp
    let left: [String: SyncEntry], right: [String: SyncEntry]
    var differences: [SyncDifference]
}
struct SyncApplyResult { let completed: Int; let cancelled: Bool; let recoveryFiles: [String] }
enum SyncError: LocalizedError { case message(String); var errorDescription: String? { if case .message(let text) = self { return text }; return nil } }

/// Native copy-only synchronization. No deletion or Windows plugin emulation.
/// Snapshots are complete or throw; every replacement preserves the old file.
enum NativeSynchronization {
    private static let fm = FileManager.default
    private static func failure(_ text: String) -> SyncError { .message(text) }
    private static func checkCancellation(_ cancelled: () -> Bool) throws { if cancelled() { throw failure("Comparison cancelled. No complete synchronization plan is available.") } }
    private static func stamp(_ url: URL) throws -> SyncStamp {
        var s = stat(); guard lstat(url.path, &s) == 0 else { throw failure("Cannot inspect \(url.path): \(String(cString: strerror(errno)))") }; return SyncStamp(s)
    }
    private static func fdStamp(_ fd: Int32) throws -> SyncStamp {
        var s = stat(); guard fstat(fd, &s) == 0 else { throw failure("Cannot inspect opened file.") }; return SyncStamp(s)
    }
    private static func hash(_ fd: Int32, cancelled: () -> Bool) throws -> String {
        guard lseek(fd, 0, SEEK_SET) >= 0 else { throw failure("Cannot seek file for comparison.") }
        var hash = SHA256(); var data = [UInt8](repeating: 0, count: 262144)
        while true {
            try checkCancellation(cancelled)
            let count = read(fd, &data, data.count)
            if count < 0 { if errno == EINTR { continue }; throw failure("Cannot read file: \(String(cString: strerror(errno)))") }
            if count == 0 { break }; hash.update(data: Data(data[0..<count]))
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private static func entry(_ url: URL, cancelled: () -> Bool) throws -> SyncEntry {
        let before = try stamp(url)
        if before.kind != .file { return SyncEntry(stamp: before, digest: nil) }
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw failure("Cannot read \(url.path): \(String(cString: strerror(errno)))") }; defer { close(fd) }
        guard try fdStamp(fd) == before else { throw failure("File changed while opening: \(url.path)") }
        let digest = try hash(fd, cancelled: cancelled)
        guard try fdStamp(fd) == before, try stamp(url) == before else { throw failure("File changed during comparison: \(url.path)") }
        return SyncEntry(stamp: before, digest: digest)
    }
    private static func canonicalRoot(_ url: URL) throws -> URL {
        guard url.isFileURL, try stamp(url).kind == .directory else { throw failure("Choose an ordinary directory, not a link: \(url.path)") }
        guard let path = realpath(url.path, nil) else { throw failure("Cannot resolve \(url.path)") }; defer { free(path) }
        return URL(fileURLWithPath: String(cString: path))
    }
    private static func snapshot(_ root: URL, cancelled: () -> Bool, beforeRead: (URL) throws -> Void) throws -> (SyncStamp, [String: SyncEntry]) {
        let rootStamp = try stamp(root); guard rootStamp.kind == .directory else { throw failure("Synchronization root changed type.") }
        var entries: [String: SyncEntry] = [:]
        func visit(_ directory: URL, prefix: String) throws {
            try checkCancellation(cancelled); try beforeRead(directory)
            let before = try stamp(directory); guard before.kind == .directory else { throw failure("Directory changed during scan: \(directory.path)") }
            let children = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [])
            var collisionKeys = Set<String>()
            for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                try checkCancellation(cancelled); try beforeRead(child)
                let name = child.lastPathComponent
                if [".tc-sync-original-", ".tc-sync-stage-"].contains(where: { name.hasPrefix($0) && UUID(uuidString: String(name.dropFirst($0.count))) != nil }) { continue }
                guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else { throw failure("Unsupported path component.") }
                // Conservative portability: no case/Unicode-colliding names in a plan.
                guard collisionKeys.insert(name.precomposedStringWithCanonicalMapping.lowercased()).inserted else { throw failure("Case or Unicode name collision in \(directory.path)") }
                let relative = prefix.isEmpty ? name : prefix + "/" + name
                let observed = try entry(child, cancelled: cancelled); entries[relative] = observed
                if observed.stamp.kind == .directory { try visit(child, prefix: relative) }
            }
            guard try stamp(directory) == before else { throw failure("Directory changed during scan: \(directory.path)") }
        }
        try visit(root, prefix: "")
        guard try stamp(root) == rootStamp else { throw failure("Root changed during scan.") }
        return (rootStamp, entries)
    }
    static func compare(left: URL, right: URL, byContent: Bool = true, preferNewer: Bool = true,
                        cancelled: () -> Bool = { false }, beforeRead: (URL) throws -> Void = { _ in }) throws -> SyncPlan {
        let a = try canonicalRoot(left), b = try canonicalRoot(right)
        guard a != b, !a.path.hasPrefix(b.path == "/" ? "/" : b.path + "/"), !b.path.hasPrefix(a.path == "/" ? "/" : a.path + "/") else { throw failure("Synchronization roots must be separate, non-overlapping directories.") }
        let (aRoot, lhs) = try snapshot(a, cancelled: cancelled, beforeRead: beforeRead)
        let (bRoot, rhs) = try snapshot(b, cancelled: cancelled, beforeRead: beforeRead)
        var rows: [SyncDifference] = []
        var pathKeys: [String: String] = [:]
        for path in Set(lhs.keys).union(rhs.keys).sorted() {
            let key = path.precomposedStringWithCanonicalMapping.lowercased()
            if let previous = pathKeys[key], previous != path { throw failure("Cross-directory case or Unicode collision: \(previous) / \(path)") }
            pathKeys[key] = path
            try checkCancellation(cancelled)
            let l = lhs[path], r = rhs[path]
            var direction = SyncDirection.skip; let status: String
            if let l, let r {
                if l.stamp.kind != r.stamp.kind { status = "Type conflict — skipped" }
                else if l.stamp.kind == .directory { continue }
                else if l.stamp.kind != .file { status = "Link/special file — unsupported" }
                else {
                    let same = byContent ? l.digest == r.digest : (l.stamp.size == r.stamp.size && l.stamp.modifiedSeconds == r.stamp.modifiedSeconds && l.stamp.modifiedNanos == r.stamp.modifiedNanos)
                    if same { continue }
                    let leftDate = (l.stamp.modifiedSeconds, l.stamp.modifiedNanos), rightDate = (r.stamp.modifiedSeconds, r.stamp.modifiedNanos)
                    status = leftDate == rightDate ? "Different; equal timestamps" : (leftDate > rightDate ? "Left is newer" : "Right is newer")
                    if preferNewer && leftDate != rightDate { direction = leftDate > rightDate ? .leftToRight : .rightToLeft }
                }
            } else {
                let value = l ?? r!
                if value.stamp.kind == .file || value.stamp.kind == .directory { status = l != nil ? "Only left" : "Only right"; direction = l != nil ? .leftToRight : .rightToLeft }
                else { status = "Link/special file — unsupported" }
            }
            rows.append(SyncDifference(path: path, status: status, left: l, right: r, direction: direction))
        }
        // The first tree may have changed while the second was scanned. Recheck identities and bytes.
        let (verifyRoot, verifyEntries) = try snapshot(a, cancelled: cancelled, beforeRead: beforeRead)
        guard verifyRoot == aRoot, verifyEntries == lhs else { throw failure("Left directory changed during comparison. Compare again.") }
        return SyncPlan(leftRoot: a, rightRoot: b, leftRootStamp: aRoot, rightRootStamp: bRoot, left: lhs, right: rhs, differences: rows)
    }
    private static func leafStamp(_ parent: Int32, _ name: String) throws -> SyncStamp? {
        var s = stat()
        if fstatat(parent, name, &s, AT_SYMLINK_NOFOLLOW) == 0 { return SyncStamp(s) }
        if errno == ENOENT { return nil }; throw failure("Cannot inspect destination \(name).")
    }
    private static func openParent(root: URL, rootStamp: SyncStamp, relative: String, entries: inout [String: SyncEntry], create: Bool) throws -> Int32 {
        let pieces = relative.split(separator: "/").map(String.init)
        guard !pieces.isEmpty, pieces.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw failure("Invalid synchronization path.") }
        var fd = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw failure("Cannot open root: \(root.path)") }
        do {
            guard try fdStamp(fd).sameIdentity(rootStamp) else { throw failure("Synchronization root was replaced.") }
            var path = ""
            for part in pieces.dropLast() {
                path = path.isEmpty ? part : path + "/" + part
                var existing = try leafStamp(fd, part)
                if existing == nil, create {
                    guard mkdirat(fd, part, 0o755) == 0 else { throw failure("Cannot create directory \(path).") }
                    existing = try leafStamp(fd, part); entries[path] = SyncEntry(stamp: existing!, digest: nil)
                }
                guard let observed = existing, observed.kind == .directory,
                      let expected = entries[path], observed.sameIdentity(expected.stamp) else { throw failure("Parent directory changed or is a link: \(path)") }
                let next = openat(fd, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else { throw failure("Cannot open directory \(path).") }
                guard try fdStamp(next).sameIdentity(observed) else { close(next); throw failure("Directory changed while opening: \(path)") }
                close(fd); fd = next
            }
            return fd
        } catch { close(fd); throw error }
    }
    private static func verifyFile(parent: Int32, name: String, expected: SyncEntry, cancelled: () -> Bool) throws -> Int32 {
        let fd = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw failure("File disappeared or became a link: \(name)") }
        do {
            guard try fdStamp(fd) == expected.stamp, expected.stamp.kind == .file,
                  try hash(fd, cancelled: cancelled) == expected.digest,
                  try fdStamp(fd) == expected.stamp else { throw failure("File changed since comparison: \(name)") }
            return fd
        } catch { close(fd); throw error }
    }
    static func apply(_ plan: SyncPlan, cancelled: () -> Bool = { false }, progress: (Int, Int, String) -> Void = { _,_,_ in }) throws -> SyncApplyResult {
        let actions = plan.differences.filter { $0.direction != .skip }
        guard actions.allSatisfy({ $0.allows($0.direction) }) else { throw failure("A selected direction involves an unsupported link or type conflict.") }
        guard Set(actions.map(\.path)).count == actions.count else { throw failure("Duplicate synchronization actions.") }
        let (leftStamp, left) = try snapshot(plan.leftRoot, cancelled: cancelled, beforeRead: { _ in })
        let (rightStamp, right) = try snapshot(plan.rightRoot, cancelled: cancelled, beforeRead: { _ in })
        guard leftStamp == plan.leftRootStamp, rightStamp == plan.rightRootStamp, left == plan.left, right == plan.right else { throw failure("Files changed since comparison. No changes applied; compare again.") }
        var currentLeft = left, currentRight = right, completed = 0, recovery: [String] = []
        do {
            for action in actions.sorted(by: { $0.path.split(separator: "/").count == $1.path.split(separator: "/").count ? $0.path < $1.path : $0.path.split(separator: "/").count < $1.path.split(separator: "/").count }) {
                if cancelled() { return SyncApplyResult(completed: completed, cancelled: true, recoveryFiles: recovery) }
                let toRight = action.direction == .leftToRight
                let sourceRoot = toRight ? plan.leftRoot : plan.rightRoot, targetRoot = toRight ? plan.rightRoot : plan.leftRoot
                let sourceRootStamp = toRight ? plan.leftRootStamp : plan.rightRootStamp, targetRootStamp = toRight ? plan.rightRootStamp : plan.leftRootStamp
                var sourceEntries = toRight ? currentLeft : currentRight, targetEntries = toRight ? currentRight : currentLeft
                guard let source = sourceEntries[action.path] else { throw failure("Source is absent: \(action.path)") }
                let sourceParent = try openParent(root: sourceRoot, rootStamp: sourceRootStamp, relative: action.path, entries: &sourceEntries, create: false); defer { close(sourceParent) }
                let targetParent = try openParent(root: targetRoot, rootStamp: targetRootStamp, relative: action.path, entries: &targetEntries, create: true); defer { close(targetParent) }
                let name = (action.path as NSString).lastPathComponent
                if source.stamp.kind == .directory {
                    guard let actual = try leafStamp(sourceParent, name), actual.sameIdentity(source.stamp), actual.kind == .directory else { throw failure("Source directory changed: \(action.path)") }
                    if let existing = try leafStamp(targetParent, name) {
                        guard existing.kind == .directory, let expected = targetEntries[action.path], existing.sameIdentity(expected.stamp) else { throw failure("Destination changed: \(action.path)") }
                    } else { guard mkdirat(targetParent, name, source.stamp.mode & 0o777) == 0 else { throw failure("Cannot create \(action.path).") } }
                    targetEntries[action.path] = SyncEntry(stamp: try leafStamp(targetParent, name)!, digest: nil)
                } else {
                    let sourceFD = try verifyFile(parent: sourceParent, name: name, expected: source, cancelled: cancelled); defer { close(sourceFD) }
                    let temporary = ".tc-sync-stage-" + UUID().uuidString
                    let stage = openat(targetParent, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
                    guard stage >= 0 else { throw failure("Cannot stage \(action.path).") }
                    defer { close(stage); unlinkat(targetParent, temporary, 0) }
                    guard lseek(sourceFD, 0, SEEK_SET) >= 0 else { throw failure("Cannot read source.") }
                    var data = [UInt8](repeating: 0, count: 262144); var copiedHash = SHA256()
                    while true {
                        if cancelled() { return SyncApplyResult(completed: completed, cancelled: true, recoveryFiles: recovery) }
                        let count = read(sourceFD, &data, data.count)
                        if count < 0 { if errno == EINTR { continue }; throw failure("Source read failed: \(action.path)") }
                        if count == 0 { break }; copiedHash.update(data: Data(data[0..<count]))
                        var written = 0
                        while written < count {
                            let amount = data.withUnsafeBytes { write(stage, $0.baseAddress!.advanced(by: written), count - written) }
                            if amount < 0 && errno == EINTR { continue }
                            guard amount > 0 else { throw failure("Destination write failed: \(action.path)") }; written += amount
                        }
                    }
                    guard copiedHash.finalize().map({ String(format: "%02x", $0) }).joined() == source.digest,
                          try fdStamp(sourceFD) == source.stamp, try leafStamp(sourceParent, name) == source.stamp else { throw failure("Source changed while copying: \(action.path)") }
                    var timestamps = [timespec(tv_sec: source.stamp.modifiedSeconds, tv_nsec: source.stamp.modifiedNanos), timespec(tv_sec: source.stamp.modifiedSeconds, tv_nsec: source.stamp.modifiedNanos)]
                    guard fchmod(stage, source.stamp.mode & 0o777) == 0, futimens(stage, &timestamps) == 0, fsync(stage) == 0 else { throw failure("Cannot finalize staged file.") }
                    let recheckedParent = try openParent(root: targetRoot, rootStamp: targetRootStamp, relative: action.path, entries: &targetEntries, create: false)
                    let sameParent = try fdStamp(recheckedParent).sameIdentity(fdStamp(targetParent)); close(recheckedParent)
                    guard sameParent else { throw failure("Destination parent changed before commit: \(action.path)") }
                    let expectedTarget = targetEntries[action.path]
                    if let expectedTarget {
                        let verified = try verifyFile(parent: targetParent, name: name, expected: expectedTarget, cancelled: cancelled); close(verified)
                        let backup = ".tc-sync-original-" + UUID().uuidString
                        guard renameatx_np(targetParent, name, targetParent, backup, UInt32(RENAME_EXCL)) == 0 else { throw failure("Cannot preserve original \(action.path).") }
                        let recoveryPath = targetRoot.appendingPathComponent((action.path as NSString).deletingLastPathComponent).appendingPathComponent(backup).path
                        recovery.append(recoveryPath)
                        do {
                            // Rename changes ctime, so verify identity, size, mtime and bytes of the moved original.
                            guard let saved = try leafStamp(targetParent, backup), saved.sameIdentity(expectedTarget.stamp), saved.size == expectedTarget.stamp.size,
                                  saved.modifiedSeconds == expectedTarget.stamp.modifiedSeconds, saved.modifiedNanos == expectedTarget.stamp.modifiedNanos else { throw failure("Destination changed at commit: \(action.path)") }
                            let savedFD = openat(targetParent, backup, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
                            guard savedFD >= 0 else { throw failure("Cannot verify preserved original.") }; defer { close(savedFD) }
                            guard try hash(savedFD, cancelled: { false }) == expectedTarget.digest else { throw failure("Destination changed at commit: \(action.path)") }
                            guard renameatx_np(targetParent, temporary, targetParent, name, UInt32(RENAME_EXCL)) == 0 else { throw failure("Destination appeared during commit: \(action.path)") }
                        } catch {
                            _ = renameatx_np(targetParent, backup, targetParent, name, UInt32(RENAME_EXCL))
                            throw error
                        }
                    } else {
                        guard try leafStamp(targetParent, name) == nil,
                              renameatx_np(targetParent, temporary, targetParent, name, UInt32(RENAME_EXCL)) == 0 else { throw failure("Destination appeared since comparison: \(action.path)") }
                    }
                    targetEntries[action.path] = SyncEntry(stamp: try leafStamp(targetParent, name)!, digest: source.digest)
                }
                if toRight { currentRight = targetEntries } else { currentLeft = targetEntries }
                completed += 1; progress(completed, actions.count, action.path)
            }
            return SyncApplyResult(completed: completed, cancelled: false, recoveryFiles: recovery)
        } catch { throw failure("Synchronization stopped after \(completed) item(s). Earlier completed copies remain.\n\(error.localizedDescription)" + (recovery.isEmpty ? "" : "\nPreserved originals:\n" + recovery.joined(separator: "\n"))) }
    }
}

private final class SyncCancellation: @unchecked Sendable {
    private let lock = NSLock(); private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

final class SynchronizationController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private static var windows: [SynchronizationController] = []
    static var hasActiveTransfers: Bool { windows.contains { $0.applying } }
    private let leftRoot: URL, rightRoot: URL
    private let table = NSTableView()
    private let content = NSButton(checkboxWithTitle: "Compare by content", target: nil, action: nil)
    private let newer = NSButton(checkboxWithTitle: "Prefer newer files", target: nil, action: nil)
    private let compareButton = NSButton(title: "Compare", target: nil, action: nil)
    private let applyButton = NSButton(title: "Synchronize…", target: nil, action: nil)
    private let stopButton = NSButton(title: "Stop", target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "")
    private let indicator = NSProgressIndicator()
    private var plan: SyncPlan?
    private var token: SyncCancellation?
    private var applying = false
    private let onComplete: () -> Void
    static func show(left: URL, right: URL, onComplete: @escaping () -> Void = {}) {
        let controller = SynchronizationController(left: left, right: right, onComplete: onComplete)
        windows.append(controller); controller.window?.center(); controller.showWindow(nil)
    }
    init(left: URL, right: URL, onComplete: @escaping () -> Void) {
        self.leftRoot = left; self.rightRoot = right; self.onComplete = onComplete
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 600), styleMask: [.titled,.closable,.resizable,.miniaturizable], backing: .buffered, defer: false)
        w.title = "Synchronize Directories"; w.isReleasedWhenClosed = false
        super.init(window: w); w.delegate = self; w.appearance = nil
        content.state = .on; newer.state = .on
        content.target = self; content.action = #selector(optionsChanged)
        newer.target = self; newer.action = #selector(optionsChanged)
        compareButton.target = self; compareButton.action = #selector(compare)
        applyButton.target = self; applyButton.action = #selector(confirmApply); applyButton.isEnabled = false
        stopButton.target = self; stopButton.action = #selector(stop); stopButton.isEnabled = false
        let controls = NSStackView(views: [content,newer,compareButton,applyButton,stopButton]); controls.orientation = .horizontal; controls.spacing = 12
        let paths = NSTextField(wrappingLabelWithString: "Left: \(left.path)\nRight: \(right.path)")
        let note = NSTextField(wrappingLabelWithString: "Copy-only synchronization: nothing is deleted. Review each direction. Replaced originals are retained as hidden .tc-sync-original-* files beside the destination. Recovery files, links and type conflicts are skipped.")
        table.dataSource = self; table.delegate = self; table.rowHeight = 27; table.usesAlternatingRowBackgroundColors = true; table.allowsMultipleSelection = true
        for (id,title,width) in [("path","Relative path",430.0),("status","Comparison",260.0),("direction","Action",220.0)] {
            let column = NSTableColumn(identifier: .init(id)); column.title = title; column.width = width; table.addTableColumn(column)
        }
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true
        let choices = NSStackView(); choices.orientation = .horizontal; choices.spacing = 12
        for (title,tag) in [("Selected: Left → Right",1),("Selected: Right → Left",2),("Selected: Skip",0)] {
            let button = NSButton(title: title, target: self, action: #selector(setSelected(_:))); button.tag = tag; choices.addArrangedSubview(button)
        }
        indicator.style = .bar; indicator.minValue = 0; indicator.maxValue = 1
        let stack = NSStackView(views: [paths,controls,note,scroll,choices,indicator,status]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        w.contentView!.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: w.contentView!.leadingAnchor, constant: 16),stack.trailingAnchor.constraint(equalTo: w.contentView!.trailingAnchor, constant: -16),stack.topAnchor.constraint(equalTo: w.contentView!.topAnchor, constant: 16),stack.bottomAnchor.constraint(equalTo: w.contentView!.bottomAnchor, constant: -16)])
        for view in [paths,note,scroll,indicator,status] { view.translatesAutoresizingMaskIntoConstraints = false; view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        status.stringValue = "Compare both directories to create a complete preview."
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if applying { token?.cancel(); status.stringValue = "Stopping safely after the current commit. Wait before closing."; return false }
        token?.cancel(); return true
    }
    func windowWillClose(_ notification: Notification) { token?.cancel(); Self.windows.removeAll { $0 === self } }
    func numberOfRows(in tableView: NSTableView) -> Int { plan?.differences.count ?? 0 }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let plan, plan.differences.indices.contains(row) else { return nil }
        let value = plan.differences[row]
        if tableColumn?.identifier.rawValue == "direction" {
            let button = NSPopUpButton(); button.addItems(withTitles: SyncDirection.allCases.map(\.rawValue)); button.selectItem(withTitle: value.direction.rawValue)
            for (index,direction) in SyncDirection.allCases.enumerated() { button.item(at: index)?.isEnabled = value.allows(direction) }
            button.autoenablesItems = false; button.tag = row; button.target = self; button.action = #selector(directionChanged(_:)); button.isEnabled = token == nil
            return button
        }
        let label = NSTextField(labelWithString: tableColumn?.identifier.rawValue == "path" ? value.path : value.status); label.lineBreakMode = .byTruncatingMiddle; label.toolTip = label.stringValue; return label
    }
    @objc private func optionsChanged() { guard token == nil else { return }; plan = nil; table.reloadData(); applyButton.isEnabled = false; status.stringValue = "Options changed. Compare again." }
    @objc private func directionChanged(_ sender: NSPopUpButton) {
        guard token == nil, let selected = SyncDirection(rawValue: sender.titleOfSelectedItem ?? ""), plan?.differences.indices.contains(sender.tag) == true,
              plan!.differences[sender.tag].allows(selected) else { return }
        plan!.differences[sender.tag].direction = selected; updateApply()
    }
    @objc private func setSelected(_ sender: NSButton) {
        guard token == nil, plan != nil else { return }
        let direction: SyncDirection = sender.tag == 1 ? .leftToRight : sender.tag == 2 ? .rightToLeft : .skip
        for row in table.selectedRowIndexes where plan!.differences.indices.contains(row) && plan!.differences[row].allows(direction) { plan!.differences[row].direction = direction }
        table.reloadData(); updateApply()
    }
    private func updateApply() { applyButton.isEnabled = token == nil && plan?.differences.contains(where: { $0.direction != .skip }) == true }
    private func setWorking(_ flag: Bool) { compareButton.isEnabled = !flag; content.isEnabled = !flag; newer.isEnabled = !flag; stopButton.isEnabled = flag; if flag { applyButton.isEnabled = false }; table.reloadData() }
    @objc private func stop() { token?.cancel(); status.stringValue = "Stopping… Completed changes will remain." }
    @objc private func compare() {
        guard token == nil else { return }
        plan = nil; let cancel = SyncCancellation(); token = cancel; setWorking(true)
        indicator.isIndeterminate = true; indicator.startAnimation(nil); status.stringValue = "Reading both complete trees and checking contents…"
        let lhs=leftRoot, rhs=rightRoot, byContent=content.state == .on, preferNewer=newer.state == .on
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try NativeSynchronization.compare(left: lhs, right: rhs, byContent: byContent, preferNewer: preferNewer, cancelled: { cancel.cancelled }) }
            DispatchQueue.main.async {
                guard let self else { return }; self.token = nil; self.indicator.stopAnimation(nil); self.indicator.isIndeterminate = false; self.setWorking(false)
                switch result {
                case .success(let plan): self.plan = plan; self.status.stringValue = "\(plan.differences.count) difference(s). Review directions before synchronizing. \(byContent ? "Content comparison." : "Metadata comparison: same size/time can hide different content.")"
                case .failure(let error): self.plan = nil; self.status.stringValue = "No complete plan created. " + error.localizedDescription
                }
                self.table.reloadData(); self.updateApply()
            }
        }
    }
    @objc private func confirmApply() {
        guard token == nil, let plan, let window else { return }
        let selected = plan.differences.filter { $0.direction != .skip }, replacements = plan.differences.filter { $0.direction != .skip && $0.left?.stamp.kind == .file && $0.right?.stamp.kind == .file }.count
        guard !selected.isEmpty else { return }
        let alert = NSAlert(); alert.messageText = "Synchronize \(selected.count) item(s)?"
        alert.informativeText = "\(replacements) existing file(s) will be replaced after revalidation; originals will be retained as hidden recovery files. Nothing will be deleted. Cancellation stops remaining work, not completed copies."
        alert.addButton(withTitle: "Synchronize"); alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in if response == .alertFirstButtonReturn { self?.apply(plan) } }
    }
    private func apply(_ frozen: SyncPlan) {
        let cancel = SyncCancellation(); token = cancel; applying = true; setWorking(true); indicator.doubleValue = 0; status.stringValue = "Revalidating both trees before applying…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try NativeSynchronization.apply(frozen, cancelled: { cancel.cancelled }, progress: { done,total,path in DispatchQueue.main.async { self?.indicator.doubleValue = Double(done)/Double(max(1,total)); self?.status.stringValue = "\(done)/\(total): \(path)" } }) }
            DispatchQueue.main.async {
                guard let self else { return }; self.token = nil; self.applying = false; self.plan = nil; self.setWorking(false); self.applyButton.isEnabled = false
                switch result {
                case .success(let result): self.status.stringValue = "\(result.completed) item(s) completed\(result.cancelled ? "; cancelled" : ""). Compare again before another apply." + (result.recoveryFiles.isEmpty ? "" : "\nPreserved originals:\n" + result.recoveryFiles.joined(separator: "\n"))
                case .failure(let error): self.status.stringValue = error.localizedDescription
                }
                self.onComplete()
            }
        }
    }
}
