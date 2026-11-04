import Foundation

@main struct OperationsTests {
    static var checks = 0
    static func check(_ condition: @autoclosure () throws -> Bool, _ label: String) throws {
        checks += 1
        if try !condition() { throw NSError(domain: "Test", code: checks, userInfo: [NSLocalizedDescriptionKey: label]) }
    }
    static func rejects(_ label: String, _ action: () throws -> Void) throws {
        var rejected = false
        do { try action() } catch { rejected = true }
        try check(rejected, label)
    }
    static func storedZIP(name: String, payload: Data) -> Data {
        func bytes(_ value: UInt32, _ count: Int) -> [UInt8] { (0..<count).map { UInt8((value >> (8 * $0)) & 255) } }
        var crc: UInt32 = 0xffffffff
        for byte in payload { crc ^= UInt32(byte); for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0) } }
        crc ^= 0xffffffff
        let filename = Data(name.utf8)
        var local = Data()
        for (value, length) in [(UInt32(0x04034b50),4),(20,2),(0x800,2),(0,2),(0,2),(0,2),(crc,4),(UInt32(payload.count),4),(UInt32(payload.count),4),(UInt32(filename.count),2),(0,2)] { local.append(contentsOf: bytes(value,length)) }
        local.append(filename); local.append(payload)
        var central = Data()
        for (value,length) in [(UInt32(0x02014b50),4),(20,2),(20,2),(0x800,2),(0,2),(0,2),(0,2),(crc,4),(UInt32(payload.count),4),(UInt32(payload.count),4),(UInt32(filename.count),2),(0,2),(0,2),(0,2),(0,2),(0,4),(0,4)] { central.append(contentsOf: bytes(value,length)) }
        central.append(filename)
        var end = Data()
        for (value,length) in [(UInt32(0x06054b50),4),(0,2),(0,2),(1,2),(1,2),(UInt32(central.count),4),(UInt32(local.count),4),(0,2)] { end.append(contentsOf: bytes(value,length)) }
        return local + central + end
    }
    static func main() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("native-operations-tests-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let left = root.appendingPathComponent("left"), right = root.appendingPathComponent("right")
        try fm.createDirectory(at: left, withIntermediateDirectories: false)
        try fm.createDirectory(at: right, withIntermediateDirectories: false)
        let file = left.appendingPathComponent("sample.txt")
        try Data("abc".utf8).write(to: file)
        let digest = try NativeOperations.sha256(file)
        try check(digest == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "SHA256 known vector")
        try Data("secret".utf8).write(to: left.appendingPathComponent(".hidden.txt"))
        try fm.createSymbolicLink(at: left.appendingPathComponent("cycle"), withDestinationURL: left)
        let report = try NativeOperations.search(root: left, pattern: "*.TXT")
        try check(report.matches.map(\.path) == [file.path], "Search excludes hidden/symlink cycle and matches case-insensitive glob")
        try check(try NativeOperations.search(root: left, pattern: "*", cancelled: { true }).cancelled, "Search cancellation")
        var boundary = Data(repeating: 65, count: 262_143); boundary.append(Data("needle".utf8))
        let large = left.appendingPathComponent("boundary.txt"); try boundary.write(to: large)
        try check(try NativeOperations.search(root: left, pattern: "boundary*", contains: "needle").matches.map(\.path) == [large.path], "Search finds content across block boundary")
        let renamed = try NativeOperations.previewRename(sources: [file], find: "sample", replace: "renamed")
        try NativeOperations.applyRename(renamed)
        try check(fm.fileExists(atPath: left.appendingPathComponent("renamed.txt").path), "Rename committed")
        try rejects("Rename collision rejects") { _ = try NativeOperations.previewRename(sources: [large], find: "boundary", replace: "renamed") }
        try rejects("Rename traversal rejects") { _ = try NativeOperations.previewRename(sources: [large], find: "boundary", replace: "../escape") }
        let a = left.appendingPathComponent("a"), b = left.appendingPathComponent("b")
        try Data("A".utf8).write(to: a); try Data("B".utf8).write(to: b)
        try NativeOperations.applyRename([RenameItem(source:a,destination:b),RenameItem(source:b,destination:a)])
        try check(try Data(contentsOf:a) == Data("B".utf8) && Data(contentsOf:b) == Data("A".utf8), "Two-phase rename supports swap")
        let comparisonA = left.appendingPathComponent("compare"), comparisonB = right.appendingPathComponent("compare")
        try Data("abc".utf8).write(to: comparisonA); try Data("xyz".utf8).write(to: comparisonB)
        let date = Date(timeIntervalSince1970: 123456)
        try fm.setAttributes([.modificationDate:date],ofItemAtPath:comparisonA.path); try fm.setAttributes([.modificationDate:date],ofItemAtPath:comparisonB.path)
        let comparison = try NativeOperations.compare(left:left,right:right)
        try check(comparison.first(where:{$0.relativePath == "compare"})?.status == "Different", "Equal metadata does not imply equal content")
        let tool = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/opt/homebrew/bin/7zz")
        let zip = root.appendingPathComponent("safe.zip")
        try storedZIP(name:"nested/hello.txt",payload:Data("hello".utf8)).write(to:zip)
        let inventory = try NativeOperations.listArchive(archive:zip,tool:tool)
        try check(inventory.count == 1 && inventory[0].path == "nested/hello.txt", "Structured ZIP inventory")
        for bad in ["../escape.txt","/absolute.txt","C:\\escape.txt","nested/../escape.txt"] {
            let archive = root.appendingPathComponent(UUID().uuidString + ".zip")
            try storedZIP(name:bad,payload:Data("bad".utf8)).write(to:archive)
            try rejects("Unsafe ZIP path rejects: \(bad)") { _ = try NativeOperations.listArchive(archive:archive,tool:tool) }
        }
        if fm.isExecutableFile(atPath:tool.path) {
            try NativeOperations.unpack(archive:zip,destination:right,tool:tool)
            try check(try Data(contentsOf:right.appendingPathComponent("nested/hello.txt")) == Data("hello".utf8), "Extraction produces exact content")
            try rejects("Extraction refuses overwrite") { try NativeOperations.unpack(archive:zip,destination:right,tool:tool) }
            let packed = root.appendingPathComponent("packed.zip")
            try NativeOperations.pack(sources:[comparisonA],archive:packed,tool:tool)
            try check(try NativeOperations.listArchive(archive:packed,tool:tool).first?.path == "compare", "Real native7zz pack succeeds")
            try rejects("Packing refuses symlink") { try NativeOperations.pack(sources:[left.appendingPathComponent("cycle")],archive:root.appendingPathComponent("bad.zip"),tool:tool) }
        } else { throw NSError(domain:"Test",code:1,userInfo:[NSLocalizedDescriptionKey:"7zz required to complete archive tests"]) }
        print("PASS: \(checks) native operation assertions")
    }
}
