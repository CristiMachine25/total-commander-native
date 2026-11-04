import AppKit

private var fileToolWindows: [NSWindowController] = []
final class TextCompareController: NSWindowController, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) { fileToolWindows.removeAll { $0 === self } }
    init(left: URL, right: URL) throws {
        func read(_ url:URL) throws -> String {
            let a = try FileManager.default.attributesOfItem(atPath:url.path)
            guard a[.type] as? FileAttributeType == .typeRegular, (a[.size] as? NSNumber)?.intValue ?? Int.max <= 4*1024*1024 else { throw FileServiceError.invalid("Text comparison supports regular files up to 4 MiB") }
            return try String(contentsOf:url,encoding:.utf8)
        }
        let a=try read(left), b=try read(right)
        guard a.components(separatedBy:"\n").count <= 2000, b.components(separatedBy:"\n").count <= 2000 else { throw FileServiceError.invalid("Text diff currently supports up to 2,000 lines per file; use checksums for larger files.") }
        let w=NSWindow(contentRect:NSRect(x:0,y:0,width:1100,height:700),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        w.title="Compare by Contents — \(left.lastPathComponent) ↔ \(right.lastPathComponent)"; w.isReleasedWhenClosed=false
        super.init(window:w); w.delegate = self
        let split=NSSplitView(); split.isVertical=true; split.dividerStyle = .thin
        let linesA=a.components(separatedBy:"\n"), linesB=b.components(separatedBy:"\n")
        let differences=linesB.difference(from:linesA)
        var removed=Set<Int>(),added=Set<Int>()
        for change in differences { switch change { case .remove(let offset,_,_): removed.insert(offset); case .insert(let offset,_,_): added.insert(offset) } }
        for (url,lines,changed,color) in [(left,linesA,removed,NSColor.systemRed),(right,linesB,added,NSColor.systemGreen)] {
            let text=NSTextView(); text.isEditable=false; text.isRichText=true; text.font = .monospacedSystemFont(ofSize:12,weight:.regular)
            let content=NSMutableAttributedString(string:"")
            for (i,line) in lines.enumerated() {
                var attrs:[NSAttributedString.Key:Any] = [.font:NSFont.monospacedSystemFont(ofSize:12,weight:.regular),.foregroundColor:NSColor.textColor]
                if changed.contains(i) { attrs[.backgroundColor] = color.withAlphaComponent(0.22) }
                content.append(NSAttributedString(string:String(format:"%6d  ",i+1)+line+"\n",attributes:attrs))
            }
            text.textStorage?.setAttributedString(content)
            let scroll=NSScrollView(); scroll.documentView=text; scroll.hasVerticalScroller=true; scroll.hasHorizontalScroller=true
            let path=NSTextField(labelWithString:url.path); path.lineBreakMode = .byTruncatingMiddle
            let stack=NSStackView(views:[path,scroll]); stack.orientation = .vertical; stack.alignment = .leading
            scroll.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true; split.addArrangedSubview(stack)
        }
        let detail=NSTextField(labelWithString:a == b ? "Files are identical" : "\(removed.count) removed / \(added.count) added lines")
        let stack=NSStackView(views:[split,detail]); stack.orientation = .vertical; stack.alignment = .leading
        w.contentView=stack; split.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true
        w.center(); fileToolWindows.append(self); showWindow(nil)
    }
    required init?(coder:NSCoder) { fatalError() }
}
extension CommanderController {
    @objc func compareFiles() {
        guard requireLocalPane(),requireLocalPane(otherPane) else {return}
        guard let a=activePane.currentEntry, !a.isDirectory else { return }
        let candidate=otherPane.directory.appendingPathComponent(a.name)
        let b=FileManager.default.fileExists(atPath:candidate.path) ? candidate : otherPane.currentEntry?.url
        guard let b else { showMessage("Compare by Contents","Select the other file in the opposite pane."); return }
        do { _ = try TextCompareController(left:a.url,right:b) } catch { showError(error) }
    }
    @objc func calculateSpace() {
        guard requireLocalPane() else {return}
        let urls=activePane.selectedURLs
        guard !urls.isEmpty else { return }
        runOperation("Calculating occupied space",success:"Calculation complete") { [weak self] in
            var size:Int64=0, files=0, folders=0
            for root in urls {
                let rootValues=try root.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey,.fileSizeKey])
                if rootValues.isSymbolicLink == true { continue }
                if rootValues.isDirectory != true { size += Int64(rootValues.fileSize ?? 0); files += 1; continue }
                folders += 1
                var scanError:Error?
                guard let scan=FileManager.default.enumerator(at:root,includingPropertiesForKeys:[.isDirectoryKey,.isSymbolicLinkKey,.fileSizeKey],errorHandler:{ _,error in scanError=error; return false }) else { throw FileServiceError.invalid("Cannot scan \(root.path)") }
                for case let url as URL in scan {
                    let v=try url.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey,.fileSizeKey])
                    if v.isSymbolicLink == true { scan.skipDescendants(); continue }
                    if v.isDirectory == true { folders += 1 } else { size += Int64(v.fileSize ?? 0); files += 1 }
                }
                if let scanError { throw scanError }
            }
            let text="\(files) files, \(folders) folders\n\(size) bytes (\(ByteCountFormatter.string(fromByteCount:size,countStyle:.file)))"
            DispatchQueue.main.async { self?.showMessage("Occupied Space",text) }
        }
    }
}
