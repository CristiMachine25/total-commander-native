import Foundation

@main struct ProviderTransfersTests {
    static var count = 0
    static func check(_ condition: @autoclosure () throws -> Bool, _ label: String) throws {
        count += 1; if try !condition() { throw FTPError.message("Test failed: " + label) }
    }
    static func rejects(_ label: String, _ action: () throws -> Void) throws {
        var rejected = false; do { try action() } catch { rejected = true }; try check(rejected, label)
    }
    static func main() throws {
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent("provider-tests-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false); defer { try? fm.removeItem(at: root) }
        func folder(_ name: String) throws -> URL { let url = root.appendingPathComponent(name); try fm.createDirectory(at: url, withIntermediateDirectories: true); return url }
        func entries(_ url: URL) throws -> [FileEntry] { try PaneLocation.local(url).list(showHidden: true) }
        let source = try folder("source"), target = try folder("target")
        try fm.createDirectory(at: source.appendingPathComponent("tree/sub"), withIntermediateDirectories: true)
        try Data("bytes".utf8).write(to: source.appendingPathComponent("tree/sub/a"))
        let copy = try ProviderTransferService.transfer(entries: entries(source), source: .local(source), target: .local(target), move: false)
        try check(copy.copiedCount == 1 && copy.movedCount == 0, "recursive copy result")
        try check(try Data(contentsOf: target.appendingPathComponent("tree/sub/a")) == Data("bytes".utf8), "recursive content")
        try rejects("collision refusal") { _ = try ProviderTransferService.transfer(entries: entries(source), source: .local(source), target: .local(target), move: true) }
        try check(fm.fileExists(atPath: source.appendingPathComponent("tree").path), "collision preserves source")
        let moved = try folder("moved")
        let move = try ProviderTransferService.transfer(entries: entries(source), source: .local(source), target: .local(moved), move: true)
        try check(move.movedCount == 1 && (try entries(source)).isEmpty, "recursive local move")
        let altered = try folder("altered"), alteredTarget = try folder("altered-target")
        let file = altered.appendingPathComponent("text"); try Data("old".utf8).write(to: file)
        try rejects("source change prevents move removal") {
            _ = try ProviderTransferService.transfer(entries: entries(altered), source: .local(altered), target: .local(alteredTarget), move: true, progress: { label in
                if label == "Rechecking sources before removal" { try! Data("new".utf8).write(to: file) }
            })
        }
        try check(try Data(contentsOf: file) == Data("new".utf8), "changed source retained")
        let cancelSource = try folder("cancel-source"), cancelTarget = try folder("cancel-target")
        try Data("keep".utf8).write(to: cancelSource.appendingPathComponent("file"))
        let task = FTPTask()
        try rejects("cancel after copy retains source") {
            _ = try ProviderTransferService.transfer(entries: entries(cancelSource), source: .local(cancelSource), target: .local(cancelTarget), move: true, task: task, progress: { if $0 == "Verifying destination contents" { task.cancel() } })
        }
        try check(fm.fileExists(atPath: cancelSource.appendingPathComponent("file").path), "cancel retains source")
        try rejects("self-descendant refusal") { _ = try ProviderTransferService.transfer(entries: entries(moved), source: .local(moved), target: .local(moved.appendingPathComponent("tree/sub")), move: true) }
        let links = try folder("links"); try fm.createSymbolicLink(at: links.appendingPathComponent("link"), withDestinationURL: file)
        try rejects("links refused") { _ = try ProviderTransferService.transfer(entries: entries(links), source: .local(links), target: .local(target), move: false) }
        guard CommandLine.arguments.count >= 3 else { throw FTPError.message("Pass bundled7zz and Python with pyftpdlib") }
        let tool = URL(fileURLWithPath: CommandLine.arguments[1]), zip = root.appendingPathComponent("fixture.zip")
        try NativeOperations.pack(sources: [moved.appendingPathComponent("tree")], archive: zip, tool: tool)
        let session = try ArchiveBrowserSession(archive: zip, tool: tool), archive = PaneLocation.archive(session, path: "")
        let unpacked = try folder("unpacked")
        let archiveMove = try ProviderTransferService.transfer(entries: archive.list(showHidden: true), source: archive, target: .local(unpacked), move: true)
        try check(archiveMove.movedCount == 1 && archiveMove.updatedArchiveSessions.count == 1, "archive source move updates session")
        let emptySession = archiveMove.updatedArchiveSessions[0].replacement
        try check(try PaneLocation.archive(emptySession, path: "").list(showHidden: true).isEmpty, "archive source members removed")
        let packed = try ProviderTransferService.transfer(entries: entries(unpacked), source: .local(unpacked), target: .archive(emptySession, path: ""), move: true)
        try check(packed.movedCount == 1 && (try entries(unpacked)).isEmpty, "move local into archive")
        let packedSession = packed.updatedArchiveSessions[0].replacement
        try check(try PaneLocation.archive(packedSession, path: "").list(showHidden: true).count == 1, "archive target has tree")
        try rejects("same archive descendant refusal") {
            _ = try ProviderTransferService.transfer(entries: PaneLocation.archive(packedSession, path: "").list(showHidden: true), source: .archive(packedSession, path: ""), target: .archive(packedSession, path: "tree/sub"), move: true)
        }
        let sameZip = root.appendingPathComponent("same.zip"); try fm.copyItem(at: zip, to: sameZip)
        let sameSession = try ArchiveBrowserSession(archive: sameZip, tool: tool)
        let within = try ProviderTransferService.transfer(entries: PaneLocation.archive(sameSession, path: "tree/sub").list(showHidden: true), source: .archive(sameSession, path: "tree/sub"), target: .archive(sameSession, path: ""), move: true)
        try check(within.movedCount == 1 && within.updatedArchiveSessions.count == 2, "same archive move chains both replacements")
        let finalArchive = within.updatedArchiveSessions.last!.replacement
        try check(try PaneLocation.archive(finalArchive, path: "").list(showHidden: true).contains { $0.name == "a" }, "same archive destination survives source removal")
        let hookZip = root.appendingPathComponent("hook.zip"); try fm.copyItem(at: zip, to: hookZip)
        let hookSession = try ArchiveBrowserSession(archive: hookZip, tool: tool)
        var hookCalled = false
        try rejects("archive writeback failure blocks source removal") {
            _ = try ProviderTransferService.transfer(entries: entries(altered), source: .local(altered), target: .archive(hookSession, path: ""), move: true, archiveCommit: { _, _ in
                hookCalled = true; throw FTPError.message("Injected outer archive writeback failure")
            })
        }
        try check(hookCalled && fm.fileExists(atPath: file.path), "archive commit hook runs before move source removal")
        let serverRoot = try folder("server"), ready = root.appendingPathComponent("port"), script = root.appendingPathComponent("server.py")
        try """
        import sys
        from pyftpdlib.authorizers import DummyAuthorizer
        from pyftpdlib.handlers import FTPHandler
        from pyftpdlib.servers import FTPServer
        a=DummyAuthorizer();a.add_user('fixture','temporary',sys.argv[1],perm='elradfmwMT');FTPHandler.authorizer=a
        s=FTPServer(('127.0.0.1',0),FTPHandler)
        open(sys.argv[2],'w').write(str(s.socket.getsockname()[1]));s.serve_forever()
        """.write(to: script, atomically: true, encoding: .utf8)
        let server = Process(); server.executableURL = URL(fileURLWithPath: CommandLine.arguments[2]); server.arguments = [script.path, serverRoot.path, ready.path]
        server.standardOutput = FileHandle.nullDevice; server.standardError = FileHandle.nullDevice
        try server.run(); defer { if server.isRunning { server.terminate(); server.waitUntilExit() } }
        for _ in 0..<100 { if fm.fileExists(atPath: ready.path) { break }; Thread.sleep(forTimeInterval: 0.05) }
        var profile = FTPProfile(); profile.host = "127.0.0.1"; profile.username = "fixture"; profile.security = .plainFTP; profile.port = Int(try String(contentsOf: ready, encoding: .utf8))!
        let client = try FTPClient(profile: profile, password: "temporary"), remote = PaneLocation.ftp(client, path: "/")
        let intoFTP = try ProviderTransferService.transfer(entries: entries(moved), source: .local(moved), target: remote, move: false)
        try check(intoFTP.copiedCount == 1, "local to FTP recursive")
        let ftpOut = try folder("ftp-out")
        let fromFTP = try ProviderTransferService.transfer(entries: remote.list(showHidden: true), source: remote, target: .local(ftpOut), move: true)
        try check(fromFTP.movedCount == 1 && (try remote.list(showHidden: true)).isEmpty, "FTP to local move")
        try check(try Data(contentsOf: ftpOut.appendingPathComponent("tree/sub/a")) == Data("bytes".utf8), "FTP move bytes verified")
        let archiveToFTP = try ProviderTransferService.transfer(entries: PaneLocation.archive(packedSession, path: "").list(showHidden: true), source: .archive(packedSession, path: ""), target: remote, move: false)
        try check(archiveToFTP.copiedCount == 1, "archive to FTP")
        try client.createDirectory(path: "/other")
        let selected = try remote.list(showHidden: true).filter { $0.name == "tree" }
        let remoteMove = try ProviderTransferService.transfer(entries: selected, source: remote, target: .ftp(client, path: "/other"), move: true)
        try check(remoteMove.movedCount == 1 && (try client.list(path: "/other")).contains { $0.name == "tree" }, "FTP to FTP move")
        try Data("before".utf8).write(to: serverRoot.appendingPathComponent("changing"))
        let conflictTarget = try folder("ftp-conflict")
        try rejects("FTP source modification prevents deletion") {
            _ = try ProviderTransferService.transfer(entries: remote.list(showHidden: true).filter { $0.name == "changing" }, source: remote, target: .local(conflictTarget), move: true, progress: { label in
                if label == "Rechecking sources before removal" { try! Data("after!".utf8).write(to: serverRoot.appendingPathComponent("changing")) }
            })
        }
        try check(try Data(contentsOf: serverRoot.appendingPathComponent("changing")) == Data("after!".utf8), "changed FTP source retained")
        print("Provider transfers: \(count) checks passed")
    }
}
