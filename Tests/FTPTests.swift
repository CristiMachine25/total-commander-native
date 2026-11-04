import AppKit

@main struct FTPTests {
    static var checks = 0
    static func check(_ condition: @autoclosure () throws -> Bool, _ label: String) throws {
        checks += 1; if try !condition() { throw FTPError.message("Test failed: " + label) }
    }
    static func rejects(_ label: String, _ action: () throws -> Void) throws {
        var rejected = false; do { try action() } catch { rejected = true }; try check(rejected, label)
    }
    static func main() throws {
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent("ftp-tests-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false); defer { try? fm.removeItem(at: root) }
        var p = FTPProfile(); p.host = "127.0.0.1"; p.username = "fixture"; p.security = .plainFTP
        for host in ["bad\nhost", "ftp://localhost", "a@b", "a/b", "a?b"] {
            var invalid = p; invalid.host = host; try rejects("host injection") { try FTPClient.validate(invalid) }
        }
        for name in ["..", "a/b", "a\r\nDELE x", "a\\b"] { try rejects("name injection") { _ = try FTPClient.childPath("/", name: name) } }
        try check(try FTPClient.normalizedPath("/a/../b/./") == "/b", "normalize")
        let listing = Data("type=cdir; .\r\ntype=file;size=42;modify=20240229230709; spaced file.txt\r\ntype=dir; folder\r\n".utf8)
        let entries = try FTPClient.parseMLSD(listing)
        try check(entries.count == 2 && entries[0].kind == .directory && entries[1].name == "spaced file.txt" && entries[1].size == 42 && entries[1].modifiedAt != nil, "MLSD parsing")
        try rejects("MLSD traversal") { _ = try FTPClient.parseMLSD(Data("type=file; ../x\r\n".utf8)) }
        try rejects("MLSD duplicate") { _ = try FTPClient.parseMLSD(Data("type=file; a\r\ntype=file; a\r\n".utf8)) }
        try check(FTPClient.processArguments == ["--disable", "--config", "-"], "credential-free process arguments")
        let store = FTPProfileStore(file: root.appendingPathComponent("profiles.json")); try store.save([p])
        try check(try store.load() == [p], "profile roundtrip")
        try check(!String(data: try Data(contentsOf: store.file), encoding: .utf8)!.contains("password"), "no stored passwords")
        try check((try fm.attributesOfItem(atPath: store.file.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600, "profile permissions")
        guard CommandLine.arguments.count > 1 else { throw FTPError.message("Pass Python with pyftpdlib for integration fixture") }
        let serverRoot = root.appendingPathComponent("server"); try fm.createDirectory(at: serverRoot, withIntermediateDirectories: false)
        let original = Data([0,1,2,255,13,10])
        try original.write(to: serverRoot.appendingPathComponent("spaces ü %#.bin"))
        let script = root.appendingPathComponent("fixture.py"), ready = root.appendingPathComponent("port")
        try """
        import sys
        from pyftpdlib.authorizers import DummyAuthorizer
        from pyftpdlib.handlers import FTPHandler
        from pyftpdlib.servers import FTPServer
        a=DummyAuthorizer(); a.add_user('fixture','temporary-secret',sys.argv[1],perm='elradfmwMT')
        FTPHandler.authorizer=a
        s=FTPServer(('127.0.0.1',0),FTPHandler)
        open(sys.argv[2],'w').write(str(s.socket.getsockname()[1]))
        s.serve_forever()
        """.write(to: script, atomically: true, encoding: .utf8)
        let server = Process(); server.executableURL = URL(fileURLWithPath: CommandLine.arguments[1]); server.arguments = [script.path, serverRoot.path, ready.path]
        server.standardOutput = FileHandle.nullDevice; server.standardError = FileHandle.nullDevice
        try server.run(); defer { if server.isRunning { server.terminate(); server.waitUntilExit() } }
        for _ in 0..<100 { if fm.fileExists(atPath: ready.path) { break }; Thread.sleep(forTimeInterval: 0.05) }
        p.port = Int(try String(contentsOf: ready, encoding: .utf8))!
        let client = try FTPClient(profile: p, password: "temporary-secret")
        try check(try client.list(path: "/").map(\.name) == ["spaces ü %#.bin"], "real FTP list")
        let local = root.appendingPathComponent("download.bin")
        try client.download(remotePath: "/spaces ü %#.bin", to: local)
        try check(try Data(contentsOf: local) == original, "binary download and URL encoding")
        try rejects("bounded download refuses oversize") { try client.download(remotePath: "/spaces ü %#.bin", to: root.appendingPathComponent("oversized"), maxBytes: 5) }
        let bounded = root.appendingPathComponent("bounded")
        try client.download(remotePath: "/spaces ü %#.bin", to: bounded, maxBytes: 6)
        try check(try Data(contentsOf: bounded) == original, "bounded download exact size")
        try rejects("local overwrite refused") { try client.download(remotePath: "/spaces ü %#.bin", to: local) }
        try client.createDirectory(path: "/new folder")
        try check(try client.list(path: "/").contains { $0.name == "new folder" && $0.kind == .directory }, "mkdir")
        try client.upload(localFile: local, remotePath: "/new folder/upload ü.bin")
        try check(try Data(contentsOf: serverRoot.appendingPathComponent("new folder/upload ü.bin")) == original, "binary upload")
        try rejects("remote overwrite refused") { try client.upload(localFile: local, remotePath: "/new folder/upload ü.bin") }
        try client.rename(from: "/new folder/upload ü.bin", to: "/new folder/renamed.bin")
        try check(try client.list(path: "/new folder").map(\.name) == ["renamed.bin"], "rename")
        let cancelled = FTPTask(); cancelled.cancel()
        try rejects("cancel before launch") { _ = try client.list(path: "/", task: cancelled) }
        try rejects("missing download") { try client.download(remotePath: "/missing", to: root.appendingPathComponent("missing")) }
        try check(try fm.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".ftp-download-") }, "partial download cleanup")
        let tree = root.appendingPathComponent("tree")
        try fm.createDirectory(at: tree.appendingPathComponent("nested"), withIntermediateDirectories: true)
        try original.write(to: tree.appendingPathComponent("nested/data.bin"))
        try Data("hidden".utf8).write(to: tree.appendingPathComponent(".hidden"))
        try client.uploadTree(localURL: tree, remotePath: "/tree")
        try check(try client.list(path: "/tree").count == 2, "tree upload includes hidden files")
        let copied = root.appendingPathComponent("tree-copy")
        try client.downloadTree(remotePath: "/tree", to: copied)
        try check(try Data(contentsOf: copied.appendingPathComponent("nested/data.bin")) == original, "recursive binary roundtrip")
        try rejects("tree local overwrite refused") { try client.downloadTree(remotePath: "/tree", to: copied) }
        try rejects("tree remote overwrite refused") { try client.uploadTree(localURL: tree, remotePath: "/tree") }
        try rejects("nonrecursive nonempty deletion refused") { try client.delete(remotePath: "/tree") }
        try check(try client.list(path: "/tree").count == 2, "refused deletion preserves contents")
        try client.delete(remotePath: "/tree", recursive: true)
        try check(!(try client.list(path: "/")).contains { $0.name == "tree" }, "recursive remote deletion")
        try client.delete(remotePath: "/new folder/renamed.bin")
        try check(try client.list(path: "/new folder").isEmpty, "remote file deletion")
        try client.delete(remotePath: "/new folder")
        try rejects("remote root deletion prohibited") { try client.delete(remotePath: "/", recursive: true) }
        try fm.createSymbolicLink(at: tree.appendingPathComponent("link"), withDestinationURL: local)
        try rejects("local symlink preflight rejection") { try client.uploadTree(localURL: tree, remotePath: "/with-link") }
        try check(!(try client.list(path: "/")).contains { $0.name == "with-link" }, "symlink rejection before mutation")
        try rejects("cancelled tree upload") { try client.uploadTree(localURL: tree, remotePath: "/cancelled", task: cancelled) }
        p.security = .explicitTLS
        try rejects("TLS must not downgrade") { _ = try FTPClient(profile: p, password: "temporary-secret").list(path: "/") }
        let cert = root.appendingPathComponent("selfsigned.pem"), key = root.appendingPathComponent("key.pem")
        let openssl = Process(); openssl.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        openssl.arguments = ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key.path, "-out", cert.path, "-days", "1", "-subj", "/CN=localhost"]
        openssl.standardOutput = FileHandle.nullDevice; openssl.standardError = FileHandle.nullDevice
        try openssl.run(); openssl.waitUntilExit(); try check(openssl.terminationStatus == 0, "TLS fixture certificate")
        let tlsScript = root.appendingPathComponent("tls-fixture.py"), tlsReady = root.appendingPathComponent("tls-port")
        var tlsSource = try String(contentsOf: script, encoding: .utf8)
        tlsSource = tlsSource.replacingOccurrences(of: "from pyftpdlib.handlers import FTPHandler", with: "from pyftpdlib.handlers import TLS_FTPHandler as FTPHandler")
        tlsSource = tlsSource.replacingOccurrences(of: "FTPHandler.authorizer=a", with: "FTPHandler.authorizer=a\nFTPHandler.certfile=sys.argv[3]\nFTPHandler.keyfile=sys.argv[4]\nFTPHandler.tls_control_required=True\nFTPHandler.tls_data_required=True")
        try tlsSource.write(to: tlsScript, atomically: true, encoding: .utf8)
        let tlsServer = Process(); tlsServer.executableURL = server.executableURL
        tlsServer.arguments = [tlsScript.path, serverRoot.path, tlsReady.path, cert.path, key.path]
        tlsServer.standardOutput = FileHandle.nullDevice; tlsServer.standardError = FileHandle.nullDevice
        try tlsServer.run(); defer { if tlsServer.isRunning { tlsServer.terminate(); tlsServer.waitUntilExit() } }
        for _ in 0..<100 { if fm.fileExists(atPath: tlsReady.path) { break }; Thread.sleep(forTimeInterval: 0.05) }
        p.port = Int(try String(contentsOf: tlsReady, encoding: .utf8))!
        var tlsFailure = ""
        do { _ = try FTPClient(profile: p, password: "temporary-secret").list(path: "/") } catch { tlsFailure = error.localizedDescription }
        try check(tlsFailure.contains("curl 60"), "untrusted certificate rejected by verification")
        print("FTP: \(checks) checks passed (disposable localhost server)")
    }
}
