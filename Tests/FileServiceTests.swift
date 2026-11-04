import Foundation

@main
struct FileServiceTests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ClassicCommander-tests-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        var checks = 0
        func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
            guard try condition() else { throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
            checks += 1
        }
        func rejects(_ action: () throws -> Void) throws {
            do { try action() } catch { checks += 1; return }
            throw NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected rejection"])
        }
        let src = root.appendingPathComponent("source")
        let dest = root.appendingPathComponent("destination")
        try FileService.makeDirectory(in: root, name: "source")
        try FileService.makeDirectory(in: root, name: "destination")
        try FileService.makeDirectory(in: src, name: "nested folder")
        let nested = src.appendingPathComponent("nested folder")
        let file = src.appendingPathComponent("școală notes.txt")
        let payload = Data("Conținut cu spații 🌿".utf8)
        try payload.write(to: file)
        try payload.write(to: nested.appendingPathComponent("child.txt"))
        try payload.write(to: src.appendingPathComponent(".hidden"))
        let dirLink = src.appendingPathComponent("folder alias")
        try fm.createSymbolicLink(at: dirLink, withDestinationURL: nested)
        let fileLink=src.appendingPathComponent("file alias")
        try fm.createSymbolicLink(at:fileLink,withDestinationURL:file)
        let broken = src.appendingPathComponent("broken link")
        try fm.createSymbolicLink(atPath: broken.path, withDestinationPath: "missing")
        let entries = try FileService.list(src, showHidden: false)
        try check(!entries.contains { $0.name == ".hidden" }, "Hidden filtering")
        try check(entries.prefix(2).allSatisfy { $0.isDirectory }, "Folders first")
        try check(entries.first { $0.name == dirLink.lastPathComponent }?.isSymbolicLink == true, "Symlink flag")
        try check(entries.first { $0.name == dirLink.lastPathComponent }?.isDirectory == true, "Symlink directory navigation")
        try check(entries.first{$0.name==fileLink.lastPathComponent}?.isDirectory == false && entries.first{$0.name==fileLink.lastPathComponent}?.isSymbolicLink == true,"File symlink stays a file")
        try check(entries.first{$0.name==broken.lastPathComponent}?.isDirectory == false && entries.first{$0.name==broken.lastPathComponent}?.isSymbolicLink == true,"Broken symlink remains listed without becoming a directory")
        try check(entries.first{$0.name==nested.lastPathComponent}?.isDirectory == true && entries.first{$0.name==file.lastPathComponent}?.isDirectory == false,"Prefetched metadata classifies ordinary files and directories")
        try check(try FileService.list(src, showHidden: true).count == entries.count + 1, "Show hidden")
        try FileService.transfer([file, nested, dirLink, broken], to: dest, move: false)
        try check(try Data(contentsOf: dest.appendingPathComponent(file.lastPathComponent)) == payload, "Unicode copy contents")
        try check(try Data(contentsOf: dest.appendingPathComponent("nested folder/child.txt")) == payload, "Recursive copy")
        try check(try fm.destinationOfSymbolicLink(atPath: dest.appendingPathComponent("folder alias").path) == nested.path, "Preserve directory symlink")
        try check(try fm.destinationOfSymbolicLink(atPath: dest.appendingPathComponent("broken link").path) == "missing", "Preserve broken symlink")
        try rejects { try FileService.transfer([file], to: dest, move: false) }
        try rejects { try FileService.transfer([file], to: src, move: false) }
        try rejects { try FileService.transfer([src], to: nested, move: false) }
        try rejects { try FileService.transfer([src], to: dirLink, move: false) }
        let destinationAlias = root.appendingPathComponent("source alias")
        try fm.createSymbolicLink(at: destinationAlias, withDestinationURL: src)
        try rejects { try FileService.transfer([file], to: destinationAlias, move: true) }
        let unique = src.appendingPathComponent("unique.txt")
        try payload.write(to: unique)
        try rejects { try FileService.transfer([unique, file], to: dest, move: false) }
        try check(!fm.fileExists(atPath: dest.appendingPathComponent("unique.txt").path), "Batch collision preflight")
        try rejects { try FileService.transfer([unique, unique], to: dest, move: false) }
        try rejects { try FileService.transfer([broken], to: dest, move: false) }
        try FileService.rename(unique, toName: "renamed ü.txt")
        let renamed = src.appendingPathComponent("renamed ü.txt")
        try check(fm.fileExists(atPath: renamed.path), "Rename")
        try rejects { try FileService.rename(renamed, toName: "broken link") }
        for invalid in ["", ".", "..", "a/b", "a\0b"] {
            try rejects { try FileService.makeDirectory(in: src, name: invalid) }
            try rejects { try FileService.rename(renamed, toName: invalid) }
        }
        try rejects { try FileService.makeDirectory(in: src, name: "broken link") }
        try FileService.transfer([renamed], to: dest, move: true)
        try check(!fm.fileExists(atPath: renamed.path), "Move removes source")
        try check(try Data(contentsOf: dest.appendingPathComponent(renamed.lastPathComponent)) == payload, "Move preserves content")
        let removeRoot=root.appendingPathComponent("delete-fixture")
        try fm.createDirectory(at:removeRoot,withIntermediateDirectories:false)
        let removeFile=removeRoot.appendingPathComponent("file");try payload.write(to:removeFile)
        let keepFolder=root.appendingPathComponent("keep-folder");try fm.createDirectory(at:keepFolder,withIntermediateDirectories:false)
        try payload.write(to:keepFolder.appendingPathComponent("keep"))
        let removeLink=removeRoot.appendingPathComponent("folder-link");try fm.createSymbolicLink(at:removeLink,withDestinationURL:keepFolder)
        try FileService.deletePermanently([removeLink])
        try check(try Data(contentsOf:keepFolder.appendingPathComponent("keep"))==payload,"Permanent deletion removes link, not linked folder")
        try rejects{try FileService.deletePermanently([removeFile,removeRoot.appendingPathComponent("missing")])}
        try check(fm.fileExists(atPath:removeFile.path),"Permanent deletion preflight rejects missing source before removing earlier files")
        try FileService.deletePermanently([removeRoot])
        try check(!fm.fileExists(atPath:removeRoot.path),"Permanent deletion removes confirmed nonempty fixture directory")
        try rejects{try FileService.deletePermanently([URL(fileURLWithPath:"/")])}
        let message = FileServiceError.operationFailed(completed: 2, item: "failed.txt", reason: "I/O failure").localizedDescription
        try check(message.contains("2") && message.contains("failed.txt") && message.contains("remain"), "Partial failure reporting")
        print("PASS: \(checks) filesystem checks; temporary fixtures cleaned on exit. Trash was not exercised.")
    }
}
