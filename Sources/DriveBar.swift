import AppKit

struct MountedDrive: Equatable {
    let url: URL
    let name: String

    static func inventory() -> [MountedDrive] {
        let keys: Set<URLResourceKey> = [.volumeNameKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
        return normalized(([URL(fileURLWithPath: "/")] + urls).map {
            MountedDrive(url: $0.standardizedFileURL, name: (try? $0.resourceValues(forKeys: keys).volumeName) ?? $0.lastPathComponent)
        })
    }

    static func normalized(_ drives: [MountedDrive]) -> [MountedDrive] {
        var seen = Set<String>()
        return drives.filter { seen.insert($0.url.standardizedFileURL.path).inserted }
    }

    static func containing(_ url: URL?, in drives: [MountedDrive]) -> URL? {
        guard let url, url.isFileURL else { return nil }
        var path = url.standardizedFileURL.path
        let data = "/System/Volumes/Data"
        if path == data { path = "/" }
        else if path.hasPrefix(data + "/") { path = String(path.dropFirst(data.count)) }
        // A removed volume's stale path must not highlight the system disk.
        return drives.sorted { $0.url.path.count > $1.url.path.count }.first {
            let root = $0.url.standardizedFileURL.path
            if root == "/" { return !path.hasPrefix("/Volumes/") }
            return path == root || path.hasPrefix(root + "/")
        }?.url
    }
}

/// Owns workspace observers; never navigates panes in response to device changes.
final class MountedDriveMonitor {
    private let center: NotificationCenter
    private var tokens: [NSObjectProtocol] = []
    private let inventory: () -> [MountedDrive]
    var changed: (([MountedDrive]) -> Void)?
    private(set) var drives: [MountedDrive]

    init(center: NotificationCenter = NSWorkspace.shared.notificationCenter,
         inventory: @escaping () -> [MountedDrive] = MountedDrive.inventory) {
        self.center = center; self.inventory = inventory; drives = inventory()
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.drives = self.inventory(); self.changed?(self.drives)
            })
        }
    }
    deinit { tokens.forEach { center.removeObserver($0) } }
}

final class DriveBarView: NSScrollView {
    private let buttons = NSStackView()
    private(set) var drives: [MountedDrive] = []
    var onSelect: ((URL) -> Void)?
    private var selectedURL: URL?

    init() {
        super.init(frame: .zero)
        drawsBackground = false; borderType = .noBorder
        hasHorizontalScroller = true; autohidesScrollers = true
        buttons.orientation = .horizontal; buttons.spacing = 3; buttons.alignment = .centerY
        documentView = buttons
        buttons.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            buttons.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            buttons.topAnchor.constraint(equalTo: contentView.topAnchor),
            buttons.heightAnchor.constraint(equalToConstant: 28),
            heightAnchor.constraint(equalToConstant: 34)
        ])
        setAccessibilityLabel("Drive buttons")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ drives: [MountedDrive]) {
        self.drives = drives
        for view in buttons.arrangedSubviews { buttons.removeArrangedSubview(view); view.removeFromSuperview() }
        for (index, drive) in drives.enumerated() {
            let button = NSButton(title: drive.name, target: self, action: #selector(selected(_:)))
            button.setButtonType(.toggle); button.bezelStyle = .smallSquare
            button.image = NSWorkspace.shared.icon(forFile: drive.url.path)
            button.image?.size = NSSize(width: 16, height: 16)
            button.imagePosition = .imageLeading; button.font = .systemFont(ofSize: 11)
            button.tag = index; button.toolTip = drive.url.path
            button.setAccessibilityLabel("Open drive " + drive.name)
            buttons.addArrangedSubview(button)
        }
        select(containing: selectedURL)
    }
    func select(containing url: URL?) {
        selectedURL = url
        let selected = MountedDrive.containing(url, in: drives)
        for case let button as NSButton in buttons.arrangedSubviews {
            button.state = drives[button.tag].url == selected ? .on : .off
        }
    }
    @objc private func selected(_ sender: NSButton) {
        guard drives.indices.contains(sender.tag) else { return }
        onSelect?(drives[sender.tag].url)
        // Navigation may fail; only the successful listing changes selection.
        select(containing: selectedURL)
    }
}
