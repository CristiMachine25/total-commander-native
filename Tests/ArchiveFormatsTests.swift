import Foundation

@main struct ArchiveFormatsTests {
    static var checks = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ label: String) throws { checks += 1; if try !value() { throw NativeOperationError.message("Test failed: " + label) } }
    static func rejects(_ label: String, _ work: () throws -> Void) throws { var failed = false; do { try work() } catch { failed = true }; try check(failed, label) }
    static func main() throws {
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent("archive-formats-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false); defer { try? fm.removeItem(at: root) }
        let tool = URL(fileURLWithPath: CommandLine.arguments[1]), fixtures = URL(fileURLWithPath: CommandLine.arguments[2])
        let file = root.appendingPathComponent("hello.txt"); try Data("format bytes\n".utf8).write(to: file)
        func run(_ executable: URL, _ args: [String]) throws {
            let p = Process(); p.executableURL = executable; p.arguments = args; p.currentDirectoryURL = root
            p.standardInput = FileHandle.nullDevice; p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            try p.run(); p.waitUntilExit(); guard p.terminationStatus == 0 else { throw NativeOperationError.message("Fixture process failed") }
        }
        for format in ["7z", "tar", "gzip", "bzip2", "xz", "zip"] {
            let ext = format == "gzip" ? "gz" : (format == "bzip2" ? "bz2" : format)
            let archive = root.appendingPathComponent("hello.txt." + ext)
            try run(tool, ["a", "-t" + format, archive.path, "--", file.lastPathComponent])
            let session = try ArchiveBrowserSession(archive: archive, tool: tool)
            try check(session.items.count == 1 && session.items[0].path == "hello.txt", "\(format) inventory")
            try check(try Data(contentsOf: session.readableMember("hello.txt")) == Data("format bytes\n".utf8), "\(format) extract")
            try session.testIntegrity()
            try check(session.isWritableZIP == (format == "zip"), "\(format) mutation capability")
            if format != "zip" { try rejects("\(format) mutation refused") { _ = try ArchiveMutationService.delete(session: session, paths: ["hello.txt"]) } }
        }
        let unicodeFile = root.appendingPathComponent("café.txt"); try Data("unicode".utf8).write(to: unicodeFile)
        for format in ["7z", "tar", "zip"] {
            let url = root.appendingPathComponent("unicode." + format)
            try run(tool, ["a", "-t" + format, url.path, "--", unicodeFile.lastPathComponent])
            let unicode = try ArchiveBrowserSession(archive: url, tool: tool)
            try check(try Data(contentsOf: unicode.readableMember("café.txt")) == Data("unicode".utf8), "Unicode member in " + format)
        }
        let rar = try ArchiveBrowserSession(archive: fixtures.appendingPathComponent("rar-subblock.rar"), tool: tool)
        try check(rar.items.count == 1 && rar.items[0].path == "test.txt", "RAR binary metadata")
        try check(try Data(contentsOf: rar.readableMember("test.txt")) == Data("test text document\r\n".utf8), "RAR decompression")
        let script = root.appendingPathComponent("fixtures.py")
        try """
        import tarfile,io,pathlib,zipfile,struct,zlib
        root=pathlib.Path('.')
        for label,kind,name in [('traversal',tarfile.REGTYPE,'../escape'),('symlink',tarfile.SYMTYPE,'link'),('hardlink',tarfile.LNKTYPE,'hard'),('fifo',tarfile.FIFOTYPE,'fifo')]:
            with tarfile.open(label+'.tar','w') as t:
                item=tarfile.TarInfo(name);item.type=kind;item.linkname='../outside'
                if kind==tarfile.REGTYPE:item.size=3
                t.addfile(item,io.BytesIO(b'bad') if kind==tarfile.REGTYPE else None)
        with tarfile.open('collision.tar','w') as t:
            for name in ['same','SAME']:
                i=tarfile.TarInfo(name);i.size=1;t.addfile(i,io.BytesIO(b'x'))
        with tarfile.open('implicit-case.tar','w') as t:
            for name in ['Dir/a','dir/b']:
                i=tarfile.TarInfo(name);i.size=1;t.addfile(i,io.BytesIO(b'x'))
        with tarfile.open('oversize.tar','w') as t:
            i=tarfile.TarInfo('huge');i.size=536870913;t.fileobj.write(i.tobuf());t.offset+=512
        with tarfile.open('hello.tar.gz','w:gz') as t:t.add('hello.txt',arcname='hello.txt')
        with zipfile.ZipFile('zip64.zip','w',allowZip64=True) as z:
            with z.open('zip64.txt','w',force_zip64=True) as f:f.write(b'zip64 bytes')
        blob=pathlib.Path('zip64.zip').read_bytes();c=blob.index(b'PK\\x01\\x02');e=blob.rfind(b'PK\\x05\\x06')
        central=bytearray(blob[c:e]);packed,unpacked=struct.unpack_from('<II',central,20);n,x=struct.unpack_from('<HH',central,28)
        extra=struct.pack('<HHQQ',1,16,unpacked,packed);struct.pack_into('<II',central,20,0xffffffff,0xffffffff);struct.pack_into('<H',central,30,x+len(extra));central[46+n+x:46+n+x]=extra
        zip64end=struct.pack('<IQHHIIQQQQ',0x06064b50,44,45,45,0,0,1,1,len(central),c)
        locator=struct.pack('<IIQI',0x07064b50,0,c+len(central),1)
        end=struct.pack('<IHHHHIIH',0x06054b50,0,0,65535,65535,0xffffffff,0xffffffff,0)
        pathlib.Path('fullzip64.zip').write_bytes(blob[:c]+central+zip64end+locator+end)
        corrupt=bytearray(blob);n,x=struct.unpack_from('<HH',corrupt,26);corrupt[30+n+x]^=1;pathlib.Path('corrupt.zip').write_bytes(corrupt)
        """.write(to: script, atomically: true, encoding: .utf8)
        try run(URL(fileURLWithPath: "/usr/bin/python3"), [script.path])
        for name in ["traversal", "symlink", "hardlink", "fifo", "collision", "implicit-case", "oversize"] {
            try rejects("hostile TAR \(name)") { _ = try NativeOperations.listArchive(archive: root.appendingPathComponent(name + ".tar"), tool: tool) }
        }
        let tgz = try ArchiveBrowserSession(archive: root.appendingPathComponent("hello.tar.gz"), tool: tool)
        try check(try Data(contentsOf: tgz.readableMember("hello.txt")) == Data("format bytes\n".utf8), "compressed TAR")
        let zip64 = try ArchiveBrowserSession(archive: root.appendingPathComponent("zip64.zip"), tool: tool)
        try check(try Data(contentsOf: zip64.readableMember("zip64.txt")) == Data("zip64 bytes".utf8), "ZIP64 local entry")
        let full64 = try ArchiveBrowserSession(archive: root.appendingPathComponent("fullzip64.zip"), tool: tool)
        try check(try Data(contentsOf: full64.readableMember("zip64.txt")) == Data("zip64 bytes".utf8), "full ZIP64 directory and end records")
        try rejects("CRC mismatch rejected") { _ = try NativeOperations.listArchive(archive: root.appendingPathComponent("corrupt.zip"), tool: tool) }
        try rejects("integrity cancellation") { try full64.testIntegrity(cancelled: {true}) }
        // Disposable fixture password only, never a user credential.
        let protected = root.appendingPathComponent("protected.zip")
        try run(tool, ["a", "-tzip", "-pfixture-password", protected.path, "--", file.lastPathComponent])
        try rejects("encrypted ZIP requires password") { _ = try ArchiveBrowserSession(archive: protected, tool: tool) }
        do { _ = try ArchiveBrowserSession(archive: protected, tool: tool, password: "wrong"); throw NativeOperationError.message("Wrong password accepted") }
        catch is ArchivePasswordRequired { try check(true, "typed incorrect-password error") }
        let encrypted = try ArchiveBrowserSession(archive: protected, tool: tool, password: "fixture-password")
        try check(try Data(contentsOf: encrypted.readableMember("hello.txt")) == Data("format bytes\n".utf8), "encrypted ZIP password in memory")
        try check(!encrypted.isWritableZIP, "password archive is read-only")
        print("Archive formats: \(checks) checks passed")
    }
}
