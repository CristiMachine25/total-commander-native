import AppKit

/// Bounded, UTF-8-only file access shared by the native viewer and editor.
struct TextFileDocument {
    static let maximumBytes = 4 * 1024 * 1024
    let url: URL
    private(set) var originalBytes: Data
    var text: String
    let editable: Bool

    enum FileError: LocalizedError {
        case tooLarge, notText, notRegular, symbolicLink, cyclicLink, conflict, readOnly
        var errorDescription: String? {
            switch self {
            case .tooLarge: return "Text files must be no larger than 4 MiB."
            case .notText: return "This file is not supported UTF-8 text (binary and NUL-containing files cannot be opened)."
            case .notRegular: return "Only regular files can be opened as text."
            case .symbolicLink: return "Editing symbolic links is disabled. Open the original file to edit it."
            case .cyclicLink: return "This symbolic link is cyclic or exceeds the supported limit of 40 links."
            case .conflict: return "The file changed on disk. Your edits have not been saved. Copy your edits elsewhere and reopen the file before trying again."
            case .readOnly: return "This document is read-only."
            }
        }
    }

    init(url: URL, editable: Bool) throws {
        self.url = url.standardizedFileURL
        self.editable = editable
        originalBytes = try Self.read(url: self.url, rejectLinks: editable)
        guard !originalBytes.contains(0), let decoded = String(data: originalBytes, encoding: .utf8),
              !decoded.unicodeScalars.contains(where: { $0.value < 32 && ![9, 10, 12, 13].contains($0.value) }) else {
            throw FileError.notText
        }
        text = decoded
    }

    private static func read(url: URL, rejectLinks: Bool) throws -> Data {
        let manager = FileManager.default
        var target = url.standardizedFileURL
        var visited = Set<URL>()
        var linkCount = 0
        var attributes = try manager.attributesOfItem(atPath: target.path)
        while attributes[.type] as? FileAttributeType == .typeSymbolicLink {
            if rejectLinks { throw FileError.symbolicLink }
            guard linkCount < 40, visited.insert(target).inserted else { throw FileError.cyclicLink }
            linkCount += 1
            let destination = try manager.destinationOfSymbolicLink(atPath: target.path)
            target = (destination.hasPrefix("/")
                ? URL(fileURLWithPath: destination)
                : target.deletingLastPathComponent().appendingPathComponent(destination)).standardizedFileURL
            attributes = try manager.attributesOfItem(atPath: target.path)
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw FileError.notRegular }
        guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= maximumBytes else { throw FileError.tooLarge }
        let handle = try FileHandle(forReadingFrom: target)
        defer { try? handle.close() }
        var data = Data()
        while data.count <= maximumBytes {
            let chunk = try handle.read(upToCount: min(64 * 1024, maximumBytes + 1 - data.count)) ?? Data()
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        guard data.count <= maximumBytes else { throw FileError.tooLarge }
        return data
    }

    mutating func save() throws {
        guard editable else { throw FileError.readOnly }
        let newBytes = Data(text.utf8)
        guard newBytes.count <= Self.maximumBytes else { throw FileError.tooLarge }
        guard !newBytes.contains(0), !text.unicodeScalars.contains(where: { $0.value < 32 && ![9, 10, 12, 13].contains($0.value) }) else { throw FileError.notText }
        let diskBytes = try Self.read(url: url, rejectLinks: true)
        guard diskBytes == originalBytes else { throw FileError.conflict }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        try (newBytes as NSData).write(to: url, options: .atomic)
        if let permissions = attributes[.posixPermissions] {
            try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        }
        originalBytes = newBytes
    }
}

final class EditorController: NSWindowController, NSWindowDelegate, NSTextViewDelegate, NSUserInterfaceValidations {
    private static var openControllers: [ObjectIdentifier: EditorController] = [:]
    private var fileDocument: TextFileDocument
    private let onSaved: ((URL) -> Void)?
    private let shouldCloseHook: (() -> Bool)?
    private let onClosed: (() -> Void)?
    private let textView = NSTextView()
    private let status = NSTextField(labelWithString: "")
    private var dirty: Bool { Data(textView.string.utf8) != fileDocument.originalBytes }

    static func open(url: URL, editable: Bool, onSaved: ((URL) -> Void)? = nil,
                     shouldClose: (() -> Bool)? = nil, onClosed: (() -> Void)? = nil) throws {
        let controller = EditorController(fileDocument: try TextFileDocument(url: url, editable: editable), onSaved: onSaved, shouldClose: shouldClose, onClosed: onClosed)
        openControllers[ObjectIdentifier(controller)] = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    static func requestCloseAll() -> Bool {
        for controller in Array(openControllers.values) {
            guard controller.confirmClose() else { return false }
            controller.close()
        }
        return true
    }

    private init(fileDocument: TextFileDocument, onSaved: ((URL) -> Void)?, shouldClose: (() -> Bool)?, onClosed: (() -> Void)?) {
        self.fileDocument = fileDocument; self.onSaved = onSaved; self.shouldCloseHook = shouldClose; self.onClosed = onClosed
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.title = "\(fileDocument.editable ? "Edit" : "View") — \(fileDocument.url.lastPathComponent)"
        window.representedURL = fileDocument.url
        window.minSize = NSSize(width: 440, height: 280)
        window.center()

        let content = NSView()
        window.contentView = content
        let path = NSTextField(labelWithString: fileDocument.url.path)
        path.lineBreakMode = .byTruncatingMiddle
        path.isSelectable = true
        path.toolTip = fileDocument.url.path
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .bezelBorder
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isEditable = fileDocument.editable
        textView.isSelectable = true
        textView.allowsUndo = fileDocument.editable
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.backgroundColor = NSColor(calibratedRed: 0.025, green: 0.06, blue: 0.22, alpha: 1)
        textView.textColor = NSColor(calibratedRed: 0.87, green: 0.94, blue: 1, alpha: 1)
        textView.insertionPointColor = .white
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 860, height: CGFloat.greatestFiniteMagnitude)
        textView.string = fileDocument.text
        textView.delegate = self
        scroll.documentView = textView
        let save = NSButton(title: "Save", target: self, action: #selector(saveDocument(_:)))
        save.isEnabled = fileDocument.editable
        save.keyEquivalent = "s"
        save.keyEquivalentModifierMask = .command
        let closeButton = NSButton(title: "Close", target: self, action: #selector(closeClicked(_:)))
        for view in [path, scroll, status, save, closeButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            path.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            path.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            path.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: path.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: save.topAnchor, constant: -10),
            save.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
            save.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
            closeButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            closeButton.centerYAnchor.constraint(equalTo: save.centerYAnchor),
            status.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            status.centerYAnchor.constraint(equalTo: save.centerYAnchor),
            status.trailingAnchor.constraint(lessThanOrEqualTo: save.leadingAnchor, constant: -8)
        ])
        updateStatus()
        window.makeFirstResponder(textView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func textDidChange(_ notification: Notification) { updateStatus() }

    private func updateStatus() {
        window?.isDocumentEdited = fileDocument.editable && dirty
        status.stringValue = "UTF-8 • \(textView.string.utf8.count) bytes • \(fileDocument.editable ? (dirty ? "Unsaved changes" : "Saved") : "Read-only")"
    }

    @objc func saveDocument(_ sender: Any?) { _ = save() }

    private func save() -> Bool {
        guard fileDocument.editable else { return true }
        fileDocument.text = textView.string
        do {
            try fileDocument.save()
            updateStatus()
            onSaved?(fileDocument.url)
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        item.action == #selector(saveDocument(_:)) ? fileDocument.editable : true
    }

    @objc private func closeClicked(_ sender: Any?) { window?.performClose(sender) }

    private func confirmClose() -> Bool {
        guard confirmLocalClose() else { return false }
        return shouldCloseHook?() ?? true
    }
    private func confirmLocalClose() -> Bool {
        guard fileDocument.editable && dirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to “\(fileDocument.url.lastPathComponent)”?"
        alert.informativeText = "Your unsaved changes will be lost if you discard them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[2].keyEquivalent = "\u{1b}"
        switch alert.runModal() {
        case .alertFirstButtonReturn: return save()
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { confirmClose() }
    func windowWillClose(_ notification: Notification) { onClosed?(); Self.openControllers.removeValue(forKey: ObjectIdentifier(self)) }
}
