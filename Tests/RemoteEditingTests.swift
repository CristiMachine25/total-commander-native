import Foundation

private final class MockRemote: RemoteEditTransport {
    var bytes = Data("original".utf8), date = Date(timeIntervalSince1970: 100)
    var kind = FTPEntry.Kind.file, reportedSize: UInt64?, replacements = 0
    var failUpload = false, corruptUpload = false, changeDuringFetch = false
    func metadata(path: String, task: FTPTask) throws -> FTPEntry {
        FTPEntry(name: "edit.txt", kind: kind, size: reportedSize ?? UInt64(bytes.count), modifiedAt: date)
    }
    func fetch(path: String, to: URL, task: FTPTask) throws {
        try bytes.write(to: to)
        if changeDuringFetch { date = date.addingTimeInterval(1) }
    }
    func replace(path: String, from: URL, task: FTPTask) throws {
        if failUpload { throw FTPError.message("fixture transfer failure") }
        replacements += 1; bytes = try Data(contentsOf: from); date = date.addingTimeInterval(1)
        if corruptUpload { bytes = Data("corrupted".utf8) }
    }
}
@main struct RemoteEditingTests {
    static var count = 0
    static func check(_ condition: @autoclosure () throws -> Bool, _ label: String) throws {
        count += 1; if try !condition() { throw FTPError.message("Test failed: " + label) }
    }
    static func rejects(_ label: String, _ action: () throws -> Void) throws {
        var rejected = false; do { try action() } catch { rejected = true }; try check(rejected, label)
    }
    static func main() throws {
        let remote = MockRemote(), fm = FileManager.default
        let session = try FTPRemoteEditSession.prepare(transport: remote, remotePath: "/edit.txt")
        defer { session.discardAndClose() }
        try check(try Data(contentsOf: session.localURL) == remote.bytes, "materialize original")
        try check(!session.hasPendingChanges, "initial clean")
        try check(try !session.uploadSavedChanges(), "no-op save avoids upload")
        try Data("modified".utf8).write(to: session.localURL)
        try check(session.hasPendingChanges, "pending local edit")
        try check(try session.uploadSavedChanges(), "successful upload")
        try check(remote.bytes == Data("modified".utf8) && !session.hasPendingChanges, "verified upload updates baseline")
        try Data("next edit".utf8).write(to: session.localURL)
        remote.bytes = Data("outsider".utf8) // Same length+mtime as baseline: byte comparison must still catch it.
        try rejects("same-size same-time remote conflict") { try session.uploadSavedChanges() }
        try check(remote.replacements == 1 && session.hasPendingChanges, "conflict preserves both remote and local")
        remote.bytes = Data("modified".utf8); remote.date = remote.date.addingTimeInterval(1)
        try rejects("metadata changed") { try session.uploadSavedChanges() }
        let cancelled = FTPTask(); cancelled.cancel()
        try rejects("prepare cancellation") { _ = try FTPRemoteEditSession.prepare(transport: remote, remotePath: "/edit.txt", task: cancelled) }
        try rejects("save cancellation") { try session.uploadSavedChanges(task: cancelled) }
        remote.kind = .symbolicLink
        try rejects("remote symbolic link refused") { _ = try FTPRemoteEditSession.prepare(transport: remote, remotePath: "/edit.txt") }
        remote.kind = .file; remote.reportedSize = UInt64(FTPRemoteEditSession.maximumBytes + 1)
        try rejects("oversized remote refused") { _ = try FTPRemoteEditSession.prepare(transport: remote, remotePath: "/edit.txt") }
        remote.reportedSize = nil; remote.changeDuringFetch = true
        try rejects("prepare detects in-flight metadata change") { _ = try FTPRemoteEditSession.prepare(transport: remote, remotePath: "/edit.txt") }
        remote.changeDuringFetch = false
        let failureSession = try FTPRemoteEditSession.prepare(transport: remote, remotePath: "/edit.txt")
        defer { failureSession.discardAndClose() }
        try Data("failed edit".utf8).write(to: failureSession.localURL)
        remote.failUpload = true
        try rejects("transport failure propagated") { try failureSession.uploadSavedChanges() }
        try check(failureSession.hasPendingChanges && fm.fileExists(atPath: failureSession.localURL.path), "failed save retains local recovery file")
        remote.failUpload = false; remote.corruptUpload = true
        try rejects("post-upload verification detects corruption") { try failureSession.uploadSavedChanges() }
        try check(failureSession.hasPendingChanges, "verification failure retains pending state")
        let local = session.localURL; session.discardAndClose()
        try check(!fm.fileExists(atPath: local.path), "explicit discard cleanup")
        try rejects("closed session save refused") { try session.uploadSavedChanges() }
        print("Remote editing: \(count) checks passed")
    }
}
