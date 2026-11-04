import AppKit

@main struct DriveBarTests {
    static func main() {
        let root = MountedDrive(url: URL(fileURLWithPath: "/"), name: "System")
        let usb = MountedDrive(url: URL(fileURLWithPath: "/Volumes/Test USB"), name: "Test USB")
        let nested = MountedDrive(url: URL(fileURLWithPath: "/Volumes/Test USB/Nested"), name: "Nested")
        let drives = [root, usb, nested]
        func match(_ path: String?) -> URL? { MountedDrive.containing(path.map { URL(fileURLWithPath: $0) }, in: drives) }
        assert(match("/Users/demo") == root.url)
        assert(match("/System/Volumes/Data/Users/demo") == root.url)
        assert(match("/Volumes/Test USB/file.txt") == usb.url)
        assert(match("/Volumes/Test USB/Nested/a") == nested.url)
        assert(match("/Volumes/Test USB backup") == nil)
        assert(match(nil) == nil)
        assert(MountedDrive.normalized([root,usb,root]) == [root,usb])
        let center = NotificationCenter()
        var source = [root], calls = 0
        var monitor: MountedDriveMonitor? = MountedDriveMonitor(center: center, inventory: { source })
        weak var weakMonitor = monitor
        monitor?.changed = { assert($0 == source); calls += 1 }
        source.append(usb)
        center.post(name: NSWorkspace.didMountNotification, object: nil)
        assert(monitor?.drives == source && calls == 1)
        source = [root]
        center.post(name: NSWorkspace.didUnmountNotification, object: nil)
        assert(monitor?.drives == source && calls == 2)
        center.post(name: NSWorkspace.didRenameVolumeNotification, object: nil)
        assert(calls == 3)
        monitor = nil; assert(weakMonitor == nil)
        center.post(name: NSWorkspace.didMountNotification, object: nil)
        assert(calls == 3)
        print("Drive bar: 12 matching, notification and lifecycle checks passed")
    }
}
