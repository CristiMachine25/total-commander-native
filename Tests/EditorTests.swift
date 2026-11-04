import Foundation

@main
struct EditorTests {
    static func main() throws {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent("ClassicCommander-Editor-\(UUID().uuidString)")
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: directory) }
        let file = directory.appendingPathComponent("text.txt")
        try Data("Salut, lume! Șț 🚀\n".utf8).write(to: file)
        var document = try TextFileDocument(url: file, editable: true)
        precondition(document.text == "Salut, lume! Șț 🚀\n")
        try manager.setAttributes([.posixPermissions: 0o640], ofItemAtPath: file.path)
        document.text = "Saved UTF-8 ✓\n"
        try document.save()
        check(try String(contentsOf: file, encoding: .utf8) == document.text)
        let permissions = try manager.attributesOfItem(atPath: file.path)[.posixPermissions] as! NSNumber
        precondition(permissions.intValue == 0o640)
        precondition(document.originalBytes == Data(document.text.utf8))
        try Data("External edit".utf8).write(to: file)
        document.text = "Conflicting edit"
        expectFailure("external modification") { try document.save() }
        check(try String(contentsOf: file, encoding: .utf8) == "External edit")

        let binary = directory.appendingPathComponent("binary")
        for bytes: [UInt8] in [[65, 0, 66], [0xff, 0xfe], [1, 2, 3]] {
            try Data(bytes).write(to: binary)
            expectFailure("binary rejection") { _ = try TextFileDocument(url: binary, editable: false) }
        }
        let large = directory.appendingPathComponent("large")
        try Data(repeating: 65, count: TextFileDocument.maximumBytes + 1).write(to: large)
        expectFailure("size rejection") { _ = try TextFileDocument(url: large, editable: true) }
        try Data(repeating: 65, count: TextFileDocument.maximumBytes).write(to: large)
        check(try TextFileDocument(url: large, editable: false).originalBytes.count == TextFileDocument.maximumBytes)
        let link = directory.appendingPathComponent("link")
        try manager.createSymbolicLink(at: link, withDestinationURL: file)
        expectFailure("symlink edit rejection") { _ = try TextFileDocument(url: link, editable: true) }
        check(try TextFileDocument(url: link, editable: false).text == "External edit")
        let relativeLink = directory.appendingPathComponent("relative-link")
        try manager.createSymbolicLink(atPath: relativeLink.path, withDestinationPath: file.lastPathComponent)
        check(try TextFileDocument(url: relativeLink, editable: false).text == "External edit")
        let selfLink = directory.appendingPathComponent("self-link")
        try manager.createSymbolicLink(at: selfLink, withDestinationURL: selfLink)
        expectFailure("self-referential viewer link") { _ = try TextFileDocument(url: selfLink, editable: false) }
        let cycleA = directory.appendingPathComponent("cycle-a")
        let cycleB = directory.appendingPathComponent("cycle-b")
        try manager.createSymbolicLink(atPath: cycleA.path, withDestinationPath: cycleB.lastPathComponent)
        try manager.createSymbolicLink(atPath: cycleB.path, withDestinationPath: cycleA.lastPathComponent)
        expectFailure("two-link viewer cycle") { _ = try TextFileDocument(url: cycleA, editable: false) }
        var chainTarget = file
        for index in 0..<41 {
            let next = directory.appendingPathComponent("chain-\(index)")
            try manager.createSymbolicLink(at: next, withDestinationURL: chainTarget)
            chainTarget = next
        }
        expectFailure("viewer link depth limit") { _ = try TextFileDocument(url: chainTarget, editable: false) }
        var viewer = try TextFileDocument(url: file, editable: false)
        viewer.text = "Read-only changed"
        expectFailure("read-only save") { try viewer.save() }
        var oversized = try TextFileDocument(url: file, editable: true)
        oversized.text = String(repeating: "A", count: TextFileDocument.maximumBytes + 1)
        expectFailure("oversized save") { try oversized.save() }
        var replaced = try TextFileDocument(url: file, editable: true)
        try manager.removeItem(at: file)
        try manager.createSymbolicLink(at: file, withDestinationURL: large)
        replaced.text = "Must not follow swapped link"
        expectFailure("symlink swap") { try replaced.save() }
        check(try Data(contentsOf: large).count == TextFileDocument.maximumBytes)
        print("EditorTests: UTF-8, binary, size boundaries, conflict, permissions, read-only, and symlink checks passed")
    }

    static func check(_ condition: Bool) { precondition(condition) }

    static func expectFailure(_ name: String, _ operation: () throws -> Void) {
        do {
            try operation()
            fatalError("Expected failure: \(name)")
        } catch {}
    }
}
