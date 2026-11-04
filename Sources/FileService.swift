import Foundation
import Darwin

struct FileEntry: Identifiable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let isSymbolicLink: Bool
    let size: Int64
    let modified: Date?
    var id: URL { url }
}

enum FileServiceError: LocalizedError {
    case invalid(String)
    case operationFailed(completed: Int, item: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        case .operationFailed(let count, let item, let reason):
            return "Completed \(count) item(s). Failed on ‘\(item)’: \(reason) Earlier completed changes remain in place."
        }
    }
}

enum FileService {
    private static let fm = FileManager.default

    private static func exists(_ url: URL) -> Bool {
        var info = stat()
        return url.withUnsafeFileSystemRepresentation { pointer in
            guard let pointer = pointer else { return false }
            return lstat(pointer, &info) == 0
        }
    }

    private static func validateName(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else {
            throw FileServiceError.invalid("Enter a nonempty name without /, a null character, . or ...")
        }
    }

    private static func requireDirectory(_ url: URL) throws {
        var directory: ObjCBool = false
        guard url.isFileURL, fm.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue else {
            throw FileServiceError.invalid("The destination is not an accessible folder: \(url.path)")
        }
    }

    private static func canonicalLeaf(_ url: URL) -> URL {
        url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent).standardizedFileURL
    }

    static func list(_ directory: URL, showHidden: Bool) throws -> [FileEntry] {
        try requireDirectory(directory)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        let urls = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys), options: showHidden ? [] : [.skipsHiddenFiles])
        return try urls.map { url in
            let values = try url.resourceValues(forKeys: keys)
            // Directory metadata was prefetched by contentsOfDirectory. Only a
            // symlink needs a target lookup to retain directory-link navigation.
            var directory=values.isDirectory ?? false
            if values.isSymbolicLink == true || values.isDirectory == nil {
                var targetDirectory:ObjCBool=false
                _ = fm.fileExists(atPath:url.path,isDirectory:&targetDirectory)
                directory=targetDirectory.boolValue
            }
            return FileEntry(url: url, name: url.lastPathComponent, isDirectory: directory, isSymbolicLink: values.isSymbolicLink ?? false, size: Int64(values.fileSize ?? 0), modified: values.contentModificationDate)
        }.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    static func transfer(_ sources: [URL], to directory: URL, move: Bool) throws {
        try requireDirectory(directory)
        let destinationDirectory = directory.resolvingSymlinksInPath().standardizedFileURL
        var names = Set<String>()
        var pairs: [(URL, URL)] = []
        for source in sources {
            guard source.isFileURL, exists(source) else { throw FileServiceError.invalid("Source does not exist: \(source.path)") }
            let name = source.lastPathComponent
            guard names.insert(name).inserted else { throw FileServiceError.invalid("More than one selected item has the name ‘\(name)’.") }
            let target = destinationDirectory.appendingPathComponent(name)
            guard canonicalLeaf(source) != target else { throw FileServiceError.invalid("An item cannot be transferred onto itself: \(name)") }
            let values = try source.resourceValues(forKeys: [.isSymbolicLinkKey])
            var isDirectory: ObjCBool = false
            _ = fm.fileExists(atPath: source.path, isDirectory: &isDirectory)
            if isDirectory.boolValue && values.isSymbolicLink != true {
                let original = source.resolvingSymlinksInPath().standardizedFileURL.pathComponents
                let destination = destinationDirectory.pathComponents
                guard !destination.starts(with: original) else { throw FileServiceError.invalid("A folder cannot be transferred into itself or its descendants: \(name)") }
            }
            guard !exists(target) else { throw FileServiceError.invalid("An item named ‘\(name)’ already exists in the destination.") }
            pairs.append((source, target))
        }
        for (index, pair) in pairs.enumerated() {
            do {
                if move { try fm.moveItem(at: pair.0, to: pair.1) }
                else { try fm.copyItem(at: pair.0, to: pair.1) }
            } catch { throw FileServiceError.operationFailed(completed: index, item: pair.0.lastPathComponent, reason: error.localizedDescription) }
        }
    }

    static func rename(_ source: URL, toName: String) throws {
        try validateName(toName)
        guard source.isFileURL, exists(source) else { throw FileServiceError.invalid("Source does not exist: \(source.path)") }
        let target = source.deletingLastPathComponent().appendingPathComponent(toName)
        if source.lastPathComponent == toName { return }
        guard !exists(target) else { throw FileServiceError.invalid("An item named ‘\(toName)’ already exists.") }
        do { try fm.moveItem(at: source, to: target) }
        catch { throw FileServiceError.operationFailed(completed: 0, item: source.lastPathComponent, reason: error.localizedDescription) }
    }

    static func makeDirectory(in directory: URL, name: String) throws {
        try validateName(name)
        try requireDirectory(directory)
        let target = directory.appendingPathComponent(name)
        guard !exists(target) else { throw FileServiceError.invalid("An item named ‘\(name)’ already exists.") }
        do { try fm.createDirectory(at: target, withIntermediateDirectories: false) }
        catch { throw FileServiceError.operationFailed(completed: 0, item: name, reason: error.localizedDescription) }
    }

    /// The UI must obtain explicit confirmation before calling this method.
    /// FileManager removes a symbolic link itself, never its destination.
    static func deletePermanently(_ sources:[URL]) throws {
        for source in sources {
            guard source.isFileURL,source.standardizedFileURL.path != "/",exists(source) else {throw FileServiceError.invalid("Invalid deletion source: \(source.path)")}
        }
        for (index,source) in sources.enumerated() {
            do {try fm.removeItem(at:source)}
            catch {throw FileServiceError.operationFailed(completed:index,item:source.lastPathComponent,reason:error.localizedDescription)}
        }
    }

    static func trash(_ sources: [URL]) throws {
        for source in sources {
            guard source.isFileURL, exists(source) else { throw FileServiceError.invalid("Source does not exist: \(source.path)") }
        }
        for (index, source) in sources.enumerated() {
            do { try fm.trashItem(at: source, resultingItemURL: nil) }
            catch { throw FileServiceError.operationFailed(completed: index, item: source.lastPathComponent, reason: error.localizedDescription) }
        }
    }
}
