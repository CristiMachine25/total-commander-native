import Foundation
import AppKit
import Darwin

@main struct ListerTests {
    static var checks = 0
    static func check(_ condition: @autoclosure () throws -> Bool, _ description: String) throws {
        checks += 1
        if try !condition() { throw NSError(domain: "ListerTests", code: checks, userInfo: [NSLocalizedDescriptionKey: description]) }
    }
    static func rejects(_ description: String, _ action: () throws -> Void) throws {
        var failed = false
        do { try action() } catch { failed = true }
        try check(failed, description)
    }
    static func main() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("lister-tests-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        let empty = root.appendingPathComponent("empty"); try Data().write(to: empty)
        let emptyDoc = try ListerDocument(url: empty)
        try check(emptyDoc.size == 0 && emptyDoc.pageCount == 1, "Empty file has one readable empty page")
        try check(try emptyDoc.page(0).isEmpty, "Empty page read")
        try check(try emptyDoc.hexPage(0) == "(empty file)", "Empty hex display")
        try check(try emptyDoc.textPreview().text.isEmpty, "Empty UTF8 text")
        try rejects("Out of range page rejected") { _ = try emptyDoc.page(1) }
        let boundary = root.appendingPathComponent("boundary")
        var bytes = Data(repeating: 65, count: ListerDocument.pageSize); bytes.append(66)
        try bytes.write(to: boundary)
        let bounded = try ListerDocument(url: boundary)
        try check(bounded.pageCount == 2, "Page count at boundary")
        try check(try bounded.page(0).count == 65_536, "First page is bounded")
        try check(try bounded.page(1) == Data([66]), "Second page exact tail")
        try check(try bounded.hexPage(1).contains("0000000000010000  42"), "Hex offset is absolute")
        let sparse = root.appendingPathComponent("large-sparse")
        fm.createFile(atPath: sparse.path, contents: nil)
        let handle = try FileHandle(forWritingTo: sparse)
        try handle.truncate(atOffset: 2_147_483_649)
        try handle.seek(toOffset: 2_147_483_648); try handle.write(contentsOf: Data([90])); try handle.close()
        let large = try ListerDocument(url: sparse)
        try check(large.pageCount == 32_769, "Large file page count uses 64-bit offsets")
        try check(try large.page(32_768) == Data([90]), "Large sparse file final page reads one byte")
        try rejects("Large image input rejected without reading whole file") { _ = try large.imagePreview() }
        let utf8 = ListerDocument.decodeText(Data("Hello România\n".utf8))
        try check(utf8.text == "Hello România\n" && utf8.encoding == "UTF-8", "UTF8 decode")
        let le = ListerDocument.decodeText(Data([0xff,0xfe,0x41,0,0xe9,0]))
        try check(le.text == "Aé" && le.encoding == "UTF-16 LE (BOM)", "UTF16 LE BOM")
        let be = ListerDocument.decodeText(Data([0xfe,0xff,0,0x41,0,0xe9]))
        try check(be.text == "Aé" && be.encoding == "UTF-16 BE (BOM)", "UTF16 BE BOM")
        let latin = ListerDocument.decodeText(Data([0x63,0x61,0x66,0xe9]))
        try check(latin.text == "café" && latin.encoding == "ISO-8859-1 fallback", "Latin1 explicit fallback")
        let binary = ListerDocument.decodeText(Data([0,1,2,255]))
        try check(binary.isBinary && binary.encoding == "Binary", "Binary detection")
        let partial = ListerDocument.decodeText(Data([0x41,0xc3]), truncated: true)
        try check(partial.text == "A" && partial.encoding == "UTF-8" && partial.truncated, "Truncated UTF8 scalar handled")
        let link = root.appendingPathComponent("link")
        try fm.createSymbolicLink(at: link, withDestinationURL: boundary)
        let linked = try ListerDocument(url: link)
        try check(try linked.page(1) == Data([66]), "Symlink opens resolved regular file")
        try Data("replacement".utf8).write(to: boundary, options: .atomic)
        try check(try linked.page(1) == Data([66]), "Held descriptor does not follow pathname replacement")
        let cycle = root.appendingPathComponent("cycle")
        try fm.createSymbolicLink(at: cycle, withDestinationURL: cycle)
        try rejects("Symlink cycle rejected") { _ = try ListerDocument(url: cycle) }
        try rejects("Directory rejected") { _ = try ListerDocument(url: root) }
        let fifo = root.appendingPathComponent("fifo")
        guard mkfifo(fifo.path, 0o600) == 0 else { throw NSError(domain:"FIFO",code:1) }
        try rejects("FIFO rejected without waiting for a writer") { _ = try ListerDocument(url:fifo) }
        let longText = root.appendingPathComponent("long.txt")
        try Data(repeating:65,count:ListerDocument.textLimit + 10).write(to:longText)
        let preview = try ListerDocument(url:longText).textPreview()
        try check(preview.truncated && preview.text.utf8.count == ListerDocument.textLimit, "Text preview bounded to1MiB")
        let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:2,pixelsHigh:2,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:8,bitsPerPixel:32)!
        bitmap.bitmapData!.initialize(repeating:255,count:16)
        let png = root.appendingPathComponent("tiny.png")
        try bitmap.representation(using:.png,properties:[:])!.write(to:png)
        try check(try ListerDocument(url:png).imagePreview() != nil, "Bounded image thumbnail decodes PNG")
        print("PASS: \(checks) Lister assertions")
    }
}
