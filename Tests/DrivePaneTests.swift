import AppKit

/// The disposable Main copy removes @main and exposes only refreshDrives for inventory injection.
/// All navigation, popup construction, layout and selection behavior uses production code.
@main struct DrivePaneTests {
    static func main() throws {
        _ = NSApplication.shared
        var count = 0
        func check(_ value: Bool, _ message: String) { precondition(value, message); count += 1 }
        let fm = FileManager.default
        let fixture = fm.temporaryDirectory.appendingPathComponent("drive-pane-" + UUID().uuidString)
        try fm.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: fixture) }
        let pane = Pane(directory: fixture, title: "DrivePaneTests")
        pane.remembersViewMode = false
        try pane.load(fixture, showHidden: false)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 420), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = pane.view
        pane.view.layoutSubtreeIfNeeded()
        let stack = pane.driveBar.superview as! NSStackView
        check(stack.arrangedSubviews.first === pane.driveBar, "Drive bar is first above each pane")
        check(pane.driveBar.frame.height >= 28 && pane.driveBar.frame.width > 400, "Drive bar gets visible pane width and height")
        var config = CommanderConfiguration()
        config.showDriveList = false
        pane.applyConfiguration(config)
        check(!pane.driveBar.isHidden && pane.volumePopup.superview!.isHidden, "Drive buttons and popup have independent visibility")
        config.showDriveButtons = false; config.showDriveList = true
        pane.applyConfiguration(config)
        check(pane.driveBar.isHidden && !pane.volumePopup.superview!.isHidden, "Drive button toggle applies immediately")
        config.showDriveButtons = true; pane.applyConfiguration(config)
        func buttons() -> [NSButton] { (pane.driveBar.documentView as! NSStackView).arrangedSubviews.compactMap { $0 as? NSButton } }
        func rootSelected() -> Bool {
            guard let index = pane.driveBar.drives.firstIndex(where: { $0.url.path == "/" }) else { return false }
            return buttons()[index].state == .on && pane.volumePopup.indexOfSelectedItem == index + 1
        }
        check(rootSelected(), "Local pane highlights its actual system drive in buttons and popup")
        var profile = FTPProfile(); profile.host = "127.0.0.1"
        let client = try FTPClient(profile: profile, password: "")
        pane.applyListing([], location: .ftp(client, path: "/"), updateHeader: false)
        check(buttons().allSatisfy { $0.state == .off } && pane.volumePopup.indexOfSelectedItem == -1, "FTP clears local drive selection even when header updates are disabled")
        pane.setTreeMode(root: .local(fixture))
        check(rootSelected(), "Tree drive selection follows tree root rather than previous FTP location")
        pane.setBriefMode(false)
        check(buttons().allSatisfy { $0.state == .off }, "Leaving tree restores the underlying FTP selection")
        try pane.load(fixture, showHidden: false)
        var activations = 0, attempted: URL?
        pane.onActivate = { activations += 1 }
        pane.onLocal = { attempted = $0 } // Reject navigation: no successful listing commit.
        pane.volumePopup.selectItem(at: 0)
        pane.volumePopup.sendAction(pane.volumePopup.action!, to: pane.volumePopup.target)
        check(attempted == fm.homeDirectoryForCurrentUser && activations == 1, "Popup routes chosen location through owning pane activation")
        check(rootSelected(), "Rejected popup navigation restores previous drive selection")
        let sameA = MountedDrive(url: fixture.appendingPathComponent("a"), name: "Backup")
        let sameB = MountedDrive(url: fixture.appendingPathComponent("b"), name: "Backup")
        let home = MountedDrive(url: fixture.appendingPathComponent("c"), name: "Home")
        pane.refreshDrives([sameA, sameB, home])
        check(pane.volumePopup.itemTitles == ["Home", "Backup", "Backup", "Home"], "Duplicate disk labels including Home preserve every popup item")
        check(pane.locations.count == pane.volumePopup.numberOfItems, "Popup index mapping stays aligned with locations")
        pane.volumePopup.selectItem(at: 2)
        pane.volumePopup.sendAction(pane.volumePopup.action!, to: pane.volumePopup.target)
        check(attempted == sameB.url, "Second identical label routes to second disk URL")
        buttons()[2].performClick(nil)
        check(attempted == home.url, "Drive button routes its own disk URL despite duplicate labels")
        pane.refreshDrives((0..<20).map { MountedDrive(url: fixture.appendingPathComponent("disk\($0)"), name: "External disk \($0)") })
        pane.view.layoutSubtreeIfNeeded()
        check(pane.driveBar.documentView!.frame.width > pane.driveBar.contentView.bounds.width, "Many drives overflow horizontally without widening pane")
        print("Drive pane integration: \(count) checks passed")
    }
}
