import AppKit
import ImageIO
import Darwin

struct ListerTextPreview {
    let text: String
    let encoding: String
    let truncated: Bool
    let isBinary: Bool
}

enum ListerError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

/// Holds one read-only descriptor, so later pathname replacement cannot redirect
/// subsequent pages into a different file. Reads are bounded and use pread.
final class ListerDocument {
    static let pageSize = 65_536
    static let textLimit = 1_048_576
    static let imageLimit: UInt64 = 33_554_432
    let url: URL
    let size: UInt64
    private let descriptor: Int32
    var pageCount: UInt64 { max(1, (size + UInt64(Self.pageSize) - 1) / UInt64(Self.pageSize)) }

    init(url: URL) throws {
        guard let resolved = realpath(url.path, nil) else { throw ListerError.message("Cannot resolve file: \(url.path)\n\(String(cString: strerror(errno)))") }
        defer { free(resolved) }
        self.url = URL(fileURLWithPath: String(cString: resolved))
        let fd = Darwin.open(resolved, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw ListerError.message("Cannot open file for reading: \(String(cString: strerror(errno)))") }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size >= 0 else {
            Darwin.close(fd)
            throw ListerError.message("Lister supports regular files only.")
        }
        descriptor = fd
        size = UInt64(info.st_size)
    }
    deinit { Darwin.close(descriptor) }

    private func read(offset: UInt64, count: Int) throws -> Data {
        guard offset <= UInt64(Int64.max), count >= 0, count <= Int(Self.imageLimit) else { throw ListerError.message("Requested preview range is unsupported.") }
        var result = Data(count: count)
        var total = 0
        try result.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            while total < count {
                let amount = pread(descriptor, base.advanced(by: total), count - total, off_t(offset) + off_t(total))
                if amount == 0 { break }
                if amount < 0 {
                    if errno == EINTR { continue }
                    throw ListerError.message("File read failed: \(String(cString: strerror(errno)))")
                }
                total += amount
            }
        }
        result.count = total
        return result
    }
    func page(_ index: UInt64) throws -> Data {
        guard index < pageCount else { throw ListerError.message("Page is outside the file.") }
        let offset = index * UInt64(Self.pageSize)
        return try read(offset: offset, count: Int(min(UInt64(Self.pageSize), size - min(offset, size))))
    }
    func textPreview() throws -> ListerTextPreview {
        let truncated = size > UInt64(Self.textLimit)
        let data = try read(offset: 0, count: Int(min(size, UInt64(Self.textLimit))))
        return Self.decodeText(data, truncated: truncated)
    }
    static func decodeText(_ input: Data, truncated: Bool = false) -> ListerTextPreview {
        var data = input
        var encoding = "UTF-8"
        var decode: String.Encoding = .utf8
        if data.starts(with: [0xff, 0xfe]) { data.removeFirst(2); decode = .utf16LittleEndian; encoding = "UTF-16 LE (BOM)" }
        else if data.starts(with: [0xfe, 0xff]) { data.removeFirst(2); decode = .utf16BigEndian; encoding = "UTF-16 BE (BOM)" }
        else if data.starts(with: [0xef, 0xbb, 0xbf]) { data.removeFirst(3); encoding = "UTF-8 (BOM)" }
        if decode != .utf8 {
            if truncated && data.count % 2 != 0 { data.removeLast() }
            if let text = String(data: data, encoding: decode) { return ListerTextPreview(text: text, encoding: encoding, truncated: truncated, isBinary: false) }
            return ListerTextPreview(text: "Invalid \(encoding) text. Choose Hex to inspect the bytes.", encoding: encoding + " invalid", truncated: truncated, isBinary: true)
        }
        let controls = data.reduce(0) { count, byte in count + ((byte < 32 && byte != 9 && byte != 10 && byte != 13) ? 1 : 0) }
        if data.contains(0) || (!data.isEmpty && Double(controls) / Double(data.count) > 0.05) {
            return ListerTextPreview(text: "Binary content detected. Choose Hex to inspect the file.", encoding: "Binary", truncated: truncated, isBinary: true)
        }
        if let text = String(data: data, encoding: .utf8) { return ListerTextPreview(text: text, encoding: encoding, truncated: truncated, isBinary: false) }
        // A bounded UTF-8 prefix may end inside one multibyte scalar.
        if truncated {
            for count in 1...min(3, data.count) {
                if let text = String(data: data.dropLast(count), encoding: .utf8) {
                    return ListerTextPreview(text: text, encoding: encoding, truncated: true, isBinary: false)
                }
            }
        }
        let text = String(data: data, encoding: .isoLatin1) ?? "Text cannot be decoded. Choose Hex."
        return ListerTextPreview(text: text, encoding: "ISO-8859-1 fallback", truncated: truncated, isBinary: false)
    }
    func hexPage(_ index: UInt64) throws -> String {
        let data = try page(index)
        guard !data.isEmpty else { return "(empty file)" }
        var lines: [String] = []
        lines.reserveCapacity((data.count + 15) / 16)
        let base = index * UInt64(Self.pageSize)
        for offset in stride(from: 0, to: data.count, by: 16) {
            let bytes = data[offset..<min(offset + 16, data.count)]
            let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
            let ascii = String(bytes.map { (32...126).contains($0) ? Character(UnicodeScalar($0)) : "." })
            lines.append(String(format: "%016llX  ", base + UInt64(offset)) + hex.padding(toLength: 47, withPad: " ", startingAt: 0) + "  |" + ascii + "|")
        }
        return lines.joined(separator: "\n")
    }
    func imagePreview() throws -> NSImage? {
        guard size <= Self.imageLimit else { throw ListerError.message("Image preview is limited to 32 MiB input. Hex remains available for the full file.") }
        let data = try read(offset: 0, count: Int(size))
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                      kCGImageSourceThumbnailMaxPixelSize: 2048,
                                      kCGImageSourceCreateThumbnailWithTransform: true,
                                      kCGImageSourceShouldCacheImmediately: false]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}

private final class ListerWindow: NSWindow {
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { performClose(nil); return }
        super.keyDown(with: event)
    }
}

struct ListerAppearance {
    var fontName="Menlo"
    var fontSize:Double=12
    var wordWrap=false
    var sizeText:(Int64)->String = {ByteCountFormatter.string(fromByteCount:$0,countStyle:.file)}
}
final class ListerController: NSWindowController, NSWindowDelegate {
    private static var retained: [ObjectIdentifier: ListerController] = [:]
    private let fileDocument: ListerDocument
    private let text = NSTextView()
    private let image = NSImageView()
    private let scroll = NSScrollView()
    private let status = NSTextField(labelWithString: "")
    private let selector = NSSegmentedControl(labels: ["Text", "Hex", "Image"], trackingMode: .selectOne, target: nil, action: nil)
    private let previous = NSButton(title: "Previous page", target: nil, action: nil)
    private let next = NSButton(title: "Next page", target: nil, action: nil)
    private var page: UInt64 = 0

    static var appearanceProvider:()->ListerAppearance = {ListerAppearance()}
    private let appearance=ListerController.appearanceProvider()
    static func open(url: URL) throws {
        let controller = try ListerController(fileDocument: ListerDocument(url: url))
        retained[ObjectIdentifier(controller)] = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }
    private init(fileDocument: ListerDocument) throws {
        self.fileDocument = fileDocument
        let window = ListerWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 680), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Lister — " + fileDocument.url.lastPathComponent
        window.minSize = NSSize(width: 620, height: 380)
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.appearance = nil
        let path = NSTextField(labelWithString: fileDocument.url.path)
        path.lineBreakMode = .byTruncatingMiddle
        path.isSelectable = true
        path.toolTip = fileDocument.url.path
        selector.target = self; selector.action = #selector(changePreviewMode)
        selector.selectedSegment = 0
        previous.target = self; previous.action = #selector(previousPage)
        next.target = self; next.action = #selector(nextPage)
        let close = NSButton(title: "Close", target: self, action: #selector(closeLister))
        close.keyEquivalent = "\u{1b}"
        close.keyEquivalentModifierMask = []
        let toolbar = NSStackView(views: [selector, previous, next, close]); toolbar.spacing = 8
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.borderType = .bezelBorder
        text.isEditable = false; text.isSelectable = true
        text.isRichText = false; text.importsGraphics = false
        text.minSize = NSSize(width: 0, height: 0)
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.frame = NSRect(x: 0, y: 0, width: 916, height: 500)
        text.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        text.isHorizontallyResizable = true; text.isVerticallyResizable = true
        text.textContainer?.widthTracksTextView = false
        text.textContainer?.containerSize = NSSize(width: 100_000, height: CGFloat.greatestFiniteMagnitude)
        text.autoresizingMask = [.width]
        image.imageScaling = .scaleProportionallyDown
        status.font = NSFont.systemFont(ofSize: 11)
        status.lineBreakMode = .byTruncatingMiddle
        let stack = NSStackView(views: [path, toolbar, scroll, status]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        guard let content = window.contentView else { throw ListerError.message("Could not create the viewer window.") }
        content.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),path.widthAnchor.constraint(equalTo: stack.widthAnchor),scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),status.widthAnchor.constraint(equalTo: stack.widthAnchor),scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200)])
        window.center()
        // Text detection is bounded. Recognized image files start in Image mode;
        // arbitrary binary data starts in Hex rather than a misleading text view.
        let preview = try fileDocument.textPreview()
        if preview.isBinary { selector.selectedSegment = 1 }
        if ["png", "jpg", "jpeg", "gif", "tif", "tiff", "bmp", "heic", "webp"].contains(fileDocument.url.pathExtension.lowercased()), fileDocument.size <= ListerDocument.imageLimit { selector.selectedSegment = 2 }
        try updatePreview()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private func updatePreview() throws {
        previous.isEnabled = selector.selectedSegment == 1 && page > 0
        next.isEnabled = selector.selectedSegment == 1 && page + 1 < fileDocument.pageCount
        let size = appearance.sizeText(Int64(fileDocument.size))
        let hex=selector.selectedSegment==1,wrap=appearance.wordWrap && !hex
        text.font=hex ? NSFont.monospacedSystemFont(ofSize:appearance.fontSize,weight:.regular) : NSFont(name:appearance.fontName,size:appearance.fontSize) ?? NSFont.systemFont(ofSize:appearance.fontSize)
        text.isHorizontallyResizable = !wrap;scroll.hasHorizontalScroller = !wrap
        text.textContainer?.widthTracksTextView=wrap
        text.textContainer?.containerSize=NSSize(width:wrap ? max(1,scroll.contentSize.width) : 100_000,height:CGFloat.greatestFiniteMagnitude)
        if wrap {text.setFrameSize(NSSize(width:max(1,scroll.contentSize.width),height:text.frame.height))}
        switch selector.selectedSegment {
        case 1:
            scroll.documentView = text
            text.string = try fileDocument.hexPage(page)
            status.stringValue = "\(size) • Hex • Offset \(page * UInt64(ListerDocument.pageSize)) • Page \(page + 1) of \(fileDocument.pageCount) • Read only"
        case 2:
            if let preview = try fileDocument.imagePreview() {
                image.image = preview
                image.frame = NSRect(origin: .zero, size: NSSize(width: max(300, scroll.contentSize.width), height: max(200, scroll.contentSize.height)))
                image.autoresizingMask = [.width, .height]
                scroll.documentView = image
                status.stringValue = "\(size) • Image thumbnail, at most 2048 pixels • Read only"
            } else {
                scroll.documentView = text; text.string = "No supported image could be decoded. Choose Text or Hex."
                status.stringValue = "\(size) • Image unavailable • Read only"
            }
        default:
            scroll.documentView = text
            let preview = try fileDocument.textPreview(); text.string = preview.text
            status.stringValue = "\(size) • \(preview.encoding) • Offset 0" + (preview.truncated ? " • First 1 MiB only; use Hex for remaining bytes" : "") + " • Read only"
        }
        text.scrollToBeginningOfDocument(nil)
    }
    private func updateOrReport() {
        do { try updatePreview() }
        catch { status.stringValue = error.localizedDescription; scroll.documentView = text; text.string = error.localizedDescription }
    }
    @objc private func changePreviewMode() { updateOrReport() }
    @objc private func previousPage() { if page > 0 { page -= 1 }; updateOrReport() }
    @objc private func nextPage() { if page + 1 < fileDocument.pageCount { page += 1 }; updateOrReport() }
    @objc private func closeLister() { window?.performClose(nil) }
    func windowWillClose(_ notification: Notification) { Self.retained.removeValue(forKey: ObjectIdentifier(self)) }
}
