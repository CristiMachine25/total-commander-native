import Foundation

@main struct RenameMasksTests {
    static var count = 0
    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        count += 1
        if try !condition() { throw NSError(domain: "RenameMasksTests", code: count, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func rejects(_ message: String, _ work: () throws -> Void) throws {
        var rejected = false; do { try work() } catch { rejected = true }; try check(rejected, message)
    }
    static func main() throws {
        var base = RenameMaskOptions(); base.locale = Locale(identifier: "en_US_POSIX"); base.timeZone = TimeZone(secondsFromGMT: 0)!
        try check(try RenameMaskEngine.render(input: .init(name: "report."), index: 0, total: 1, options: base) == "report.", "Preserve terminal dot")
        let date = ISO8601DateFormatter().date(from: "2024-02-29T23:07:09Z")!
        let input = RenameMaskInput(name: "abcdefghij.TXT", parentName: "Parent", grandparentName: "Grand", size: 42, modifiedAt: date)
        let cases: [(String, String)] = [
            ("[N]", "abcdefghij.TXT"), ("[N1]", "a.TXT"), ("[N2-5]", "bcde.TXT"),
            ("[N2,5]", "bcdef.TXT"), ("[N2-]", "bcdefghij.TXT"), ("[N-8,5]", "cdefg.TXT"),
            ("[N-8-5]", "cdef.TXT"), ("[N2--5]", "bcdef.TXT"), ("[N-5-]", "fghij.TXT"),
            ("[N-1]", "j.TXT"), ("[N99]x", "x.TXT"), ("[A]", "abcdefghij.TXT.TXT"),
            ("[P]_[G]_[S]", "Parent_Grand_42.TXT"), ("[U][N2-5][n]Ab", "BCDEAb.TXT"),
            ("[[]name[]]", "[name].TXT"), ("[YMD]_[hms]_[H][i1]", "20240229_230709_11p.TXT"),
            ("[y]-[M]-[D]", "24-02-29.TXT"), ("[C10+5:3]", "010.TXT"),
            ("[C+5]", "1.TXT"), ("[C:3]", "001.TXT"), ("[c]_[c2]_[c3]", "3_3_3.TXT")
        ]
        for (mask, expected) in cases {
            var options = base; options.nameMask = mask
            try check(try RenameMaskEngine.render(input: input, index: 0, total: 3, options: options) == expected, "Mask \(mask)")
        }
        for (mask, expected) in [("[N02-9]", "000000bc.txt"), ("[N 2-9]", "      bc.txt")] {
            var options = base; options.nameMask = mask
            try check(try RenameMaskEngine.render(input: .init(name: "abc.txt"), index: 0, total: 1, options: options) == expected, "Padding \(mask)")
        }
        var o = base; o.nameMask = "[N2-3]"
        try check(try RenameMaskEngine.render(input: .init(name: "a中😀z.txt"), index: 0, total: 1, options: o) == "中😀.txt", "Unicode characters are not split into code units")
        o = base; o.nameMask = "[N]"; o.extensionMask = "[L][E1-2]"
        try check(try RenameMaskEngine.render(input: input, index: 0, total: 1, options: o) == "abcdefghij.tx", "Extension slicing and case")
        o = base
        try check(try RenameMaskEngine.render(input: .init(name: ".profile"), index: 0, total: 1, options: o) == ".profile", "Native hidden filename preserved")
        o.nameMask = "[I][N]"; o.extensionMask = "[E]"
        try check(try RenameMaskEngine.render(input: .init(name: "folder.backup", isDirectory: true), index: 0, total: 1, options: o) == "folder.backup", "I switch persists into extension mask")
        o = base; o.counterStart = 8; o.counterStep = 2; o.counterDigits = 3; o.nameMask = "[C]"
        try check(try RenameMaskEngine.render(input: input, index: 2, total: 3, options: o) == "012.TXT", "Configured counter")
        o.nameMask = "[C10+5:3]"
        try check(try RenameMaskEngine.render(input: input, index: 2, total: 3, options: o) == "020.TXT", "Inline counter ignores UI values")
        o.nameMask = "[C+1/2]"
        try check(try RenameMaskEngine.render(input: input, index: 3, total: 4, options: o) == "2.TXT", "Grouped counter")
        o.nameMask = "[C]"; o.counterDigits = nil
        try check(try RenameMaskEngine.render(input: input, index: 0, total: 3, options: o) == "08.TXT", "Automatic counter width includes terminal value")
        o.counterStart = 3; o.counterStep = -1; o.counterDigits = 2
        try check(try RenameMaskEngine.render(input: input, index: 2, total: 3, options: o) == "01.TXT", "Decrementing counter")
        o = base; o.nameMask = "[T2][Y]_[T1][Y]_[T3][Y]"; o.openedAt = ISO8601DateFormatter().date(from: "2025-01-01T00:00:00Z")!; o.changedAt = ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z")!
        try check(try RenameMaskEngine.render(input: input, index: 0, total: 1, options: o) == "2025_2024_2026.TXT", "Date source switches")
        o = base; o.search = "A"; o.replacement = "X"; o.includeExtension = false
        let repeated = RenameMaskInput(name: "aaA.AA")
        try check(try RenameMaskEngine.render(input: repeated, index: 0, total: 1, options: o) == "XXX.AA", "Default case-insensitive replacement excludes extension")
        o.replaceFirstOnly = true
        try check(try RenameMaskEngine.render(input: repeated, index: 0, total: 1, options: o) == "XaA.AA", "First replacement only")
        o.caseSensitiveSearch = true
        try check(try RenameMaskEngine.render(input: repeated, index: 0, total: 1, options: o) == "aaX.AA", "Case-sensitive replacement")
        o = base; o.regularExpression = true; o.search = #"(.*) - (.*)\.mp3"#; o.replacement = #"\U$2 - \L$1.mp3"#
        try check(try RenameMaskEngine.render(input: .init(name: "Title - Artist.mp3"), index: 0, total: 1, options: o) == "ARTIST - title.mp3", "TC documented regex replacement with case switches")
        o.replacement = #"\Fhello world.mp3"#
        try check(try RenameMaskEngine.render(input: .init(name: "Title - Artist.mp3"), index: 0, total: 1, options: o) == "Hello World.Mp3", "Replacement case conversion treats literal words as words")
        o = base; o.regularExpression = true; o.search = #"(\d+)"#; o.replacement = "[$1]"; o.includeExtension = false
        try check(try RenameMaskEngine.render(input: .init(name: "a12b34.txt"), index: 0, total: 1, options: o) == "a[12]b[34].txt", "Multiple regex replacements preserve earlier offsets")
        o.substituteEntireName = true; o.replacement = "number-$1"
        try check(try RenameMaskEngine.render(input: .init(name: "a12b34.txt"), index: 0, total: 1, options: o) == "number-12.txt", "Substitute whole matching name segment")
        o = base; o.caseConversion = .firstLetter
        try check(try RenameMaskEngine.render(input: .init(name: "HELLO world.TXT"), index: 0, total: 1, options: o) == "Hello world.txt", "Whole-result case conversion last")
        for bad in ["[Q]", "[N0]", "[N-9223372036854775808]", "[N2,999999]", "[N", "[T4]", "[Caa+1]", "[=plugin.field]", "[C:0]", "[C+1/0]", "[]", "[N]/../bad", "[N]\\bad"] {
            var invalid = base; invalid.nameMask = bad
            try rejects("Reject \(bad)") { _ = try RenameMaskEngine.render(input: input, index: 0, total: 1, options: invalid) }
        }
        o = base; o.nameMask = "[C]"; o.counterStart = Int.max; o.counterStep = 1
        try rejects("Reject integer overflow") { _ = try RenameMaskEngine.render(input: input, index: 1, total: 2, options: o) }
        o = base; o.regularExpression = true; o.search = "("; o.replacement = "$1"
        try rejects("Invalid regex") { _ = try RenameMaskEngine.render(input: input, index: 0, total: 1, options: o) }
        o.search = "(a)"; o.replacement = "$2"
        try rejects("Missing capture") { _ = try RenameMaskEngine.render(input: input, index: 0, total: 1, options: o) }
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent("rename-mask-tests-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false); defer { try? fm.removeItem(at: root) }
        let a = root.appendingPathComponent("one.txt"), b = root.appendingPathComponent("two.txt")
        try Data("one".utf8).write(to: a); try Data("two".utf8).write(to: b)
        o = base; o.nameMask = "[C]"
        let preview = try RenameMaskEngine.preview(sources: [a,b], options: o)
        try check(preview.map { $0.destination.lastPathComponent } == ["1.txt","2.txt"], "Preview preserves caller's counter order")
        try check(fm.fileExists(atPath: a.path) && !fm.fileExists(atPath: preview[0].destination.path), "Preview never mutates files")
        o.nameMask = "same"
        try rejects("Collision between proposed names") { _ = try RenameMaskEngine.preview(sources: [a,b], options: o) }
        o.nameMask = "two"
        try rejects("Existing destination collision") { _ = try RenameMaskEngine.preview(sources: [a], options: o) }
        o = base
        try rejects("Duplicate sources") { _ = try RenameMaskEngine.preview(sources: [a,a], options: o) }
        try rejects("Missing source") { _ = try RenameMaskEngine.preview(sources: [root.appendingPathComponent("missing")], options: o) }
        try rejects("Empty preview") { _ = try RenameMaskEngine.preview(sources: [], options: o) }
        try rejects("Ancestor and descendant together") { _ = try RenameMaskEngine.preview(sources: [root,a], options: o) }
        print("Rename masks: \(count) checks passed")
    }
}
