import AppKit
import ObjectiveC

private var quickViewAssociation: UInt8 = 0
private final class QuickViewText: NSTextView {
    var closePreview:(()->Void)?
    override func keyDown(with event:NSEvent) {
        let m=event.modifierFlags.intersection([.control,.shift,.option,.command])
        if m == [.control],event.charactersIgnoringModifiers?.lowercased() == "q" { closePreview?();return }
        super.keyDown(with:event)
    }
}
private final class QuickViewCoordinator:NSObject {
    // One worker limits stale rapid-selection materializations. Generation checks suppress stale UI.
    private static let worker=DispatchQueue(label:"native.quickview",qos:.userInitiated)
    weak var commander:CommanderController?
    weak var source:Pane?
    weak var target:Pane?
    var generation=0
    var task:FTPTask?
    var document:ListerDocument?
    var lease:PaneReadableMaterialization?
    var page:UInt64=0
    var identity=""
    let root=NSView()
    let title=NSTextField(labelWithString:"Quick View")
    let detail=NSTextField(labelWithString:"")
    let modes=NSSegmentedControl(labels:["Auto","Text","Hex","Image"],trackingMode:.selectOne,target:nil,action:nil)
    let text=QuickViewText()
    let scroll=NSScrollView()
    let image=NSImageView()
    let previous=NSButton(title:"Previous",target:nil,action:nil)
    let next=NSButton(title:"Next",target:nil,action:nil)
    init(commander:CommanderController,source:Pane,target:Pane) {
        self.commander=commander;self.source=source;self.target=target
        super.init()
        root.wantsLayer=true;root.layer?.backgroundColor=NSColor.windowBackgroundColor.cgColor
        let close=NSButton(title:"Close · Ctrl+Q",target:self,action:#selector(closeView))
        previous.target=self;previous.action=#selector(previousPage);next.target=self;next.action=#selector(nextPage)
        modes.selectedSegment=0;modes.target=self;modes.action=#selector(modeChanged)
        title.lineBreakMode = .byTruncatingMiddle;detail.lineBreakMode = .byTruncatingMiddle
        text.isEditable=false;text.isRichText=false;text.font = .monospacedSystemFont(ofSize:12,weight:.regular)
        text.isSelectable=true;text.minSize = .zero
        text.maxSize=NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
        text.frame=NSRect(x:0,y:0,width:500,height:500)
        text.isHorizontallyResizable=true;text.isVerticallyResizable=true
        text.textContainer?.widthTracksTextView=false
        text.textContainer?.containerSize=NSSize(width:100_000,height:CGFloat.greatestFiniteMagnitude)
        text.autoresizingMask=[.width]
        text.closePreview={ [weak self] in self?.closeView() }
        scroll.documentView=text;scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=true
        image.imageScaling = .scaleProportionallyUpOrDown
        let content=NSView();content.addSubview(scroll);content.addSubview(image)
        for v in [scroll,image] { v.translatesAutoresizingMaskIntoConstraints=false;NSLayoutConstraint.activate([v.leadingAnchor.constraint(equalTo:content.leadingAnchor),v.trailingAnchor.constraint(equalTo:content.trailingAnchor),v.topAnchor.constraint(equalTo:content.topAnchor),v.bottomAnchor.constraint(equalTo:content.bottomAnchor)]) }
        let actions=NSStackView(views:[previous,next,close]);actions.orientation = .horizontal
        let stack=NSStackView(views:[title,modes,content,detail,actions]);stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=6
        root.addSubview(stack);stack.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:root.leadingAnchor),stack.trailingAnchor.constraint(equalTo:root.trailingAnchor),stack.topAnchor.constraint(equalTo:root.topAnchor),stack.bottomAnchor.constraint(equalTo:root.bottomAnchor),content.widthAnchor.constraint(equalTo:stack.widthAnchor),content.heightAnchor.constraint(greaterThanOrEqualToConstant:180),title.widthAnchor.constraint(equalTo:stack.widthAnchor),detail.widthAnchor.constraint(equalTo:stack.widthAnchor)])
        target.showQuickView(root)
        refresh()
    }
    deinit { task?.cancel() }
    @objc func closeView() {
        generation += 1;task?.cancel();task=nil;target?.hideQuickView();document=nil;lease=nil
        if let commander {
            objc_setAssociatedObject(commander,&quickViewAssociation,nil,.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            if let source { commander.window.makeFirstResponder(source.fileResponder) }
        }
    }
    func message(_ value:String) {
        image.isHidden=true;scroll.isHidden=false;text.string=value;detail.stringValue="";previous.isEnabled=false;next.isEnabled=false
    }
    func refresh() {
        guard let source else { closeView();return }
        let entry=source.currentEntry, location=source.location
        let current=location.identity+"|"+(entry?.url.absoluteString ?? "..")+"|"+String(entry?.size ?? 0)+"|"+String(entry?.modified?.timeIntervalSince1970 ?? 0)
        guard current != identity else { return }
        identity=current;generation += 1;let token=generation;task?.cancel();document=nil;lease=nil;page=0
        title.stringValue="Quick View — "+(entry?.name ?? location.displayPath)
        guard let entry else { message("\(location.displayPath)\n\(source.entries.count) visible items\nSelect a file to preview.");return }
        guard !entry.isDirectory else { message("Directory: \(entry.name)\nProvider: \(location.displayPath)\nEnter the directory to list its contents. Recursive size is not calculated by Quick View.");return }
        // Preflight the provider-advertised size before downloading an entire remote member.
        guard location.localDirectory != nil || entry.size <= 32*1024*1024 else { message("Remote/archive Quick View is limited to 32 MiB files. Use F3 or download the file explicitly.");return }
        let request=FTPTask();task=request;message("Loading preview…")
        Self.worker.async { [weak self] in
            guard !request.isCancelled else { return }
            do {
                let materialization=try location.readableMaterialization(entry,task:request,maxBytes:location.localDirectory == nil ? 33_554_432 : nil)
                guard !request.isCancelled else { return }
                let doc=try ListerDocument(url:materialization.url)
                DispatchQueue.main.async { [weak self] in
                    guard let self,self.generation == token,!request.isCancelled else { return }
                    self.lease=materialization;self.document=doc;self.render()
                }
            } catch { DispatchQueue.main.async { [weak self] in guard let self,self.generation == token else { return };self.message(error.localizedDescription) } }
        }
    }
    @objc func modeChanged() { page=0;render() }
    @objc func previousPage() { if page > 0 { page -= 1;render() } }
    @objc func nextPage() { if let document,page+1 < document.pageCount { page += 1;render() } }
    func render() {
        guard let doc=document else { return }
        generation += 1;let token=generation, mode=modes.selectedSegment, selectedPage=page,config=commander?.runtimeConfig ?? CommanderConfiguration()
        Self.worker.async { [weak self] in
            do {
                var value="",information="",preview:NSImage?
                var hex=mode == 2
                if mode == 3 { preview=try doc.imagePreview();if preview == nil { throw ListerError.message("No supported image detected.") } }
                else if mode == 0,doc.size <= ListerDocument.imageLimit { preview=try? doc.imagePreview() }
                if preview != nil { information="Image · \(config.sizeString(Int64(doc.size))) · bounded thumbnail" }
                else {
                    if mode == 0 || mode == 1 {
                        let decoded=try doc.textPreview();hex=mode == 0 && decoded.isBinary
                        if !hex { value=decoded.text;information="\(decoded.encoding) · \(config.sizeString(Int64(doc.size)))"+(decoded.truncated ? " · first 1 MiB" : "") }
                    }
                    if hex { value=try doc.hexPage(selectedPage);information="Hex · page \(selectedPage+1)/\(doc.pageCount) · offset \(selectedPage * UInt64(ListerDocument.pageSize))" }
                }
                let output=value,info=information,picture=preview,isHex=hex
                DispatchQueue.main.async { [weak self] in
                    guard let self,self.generation == token else { return }
                    self.image.image=picture;self.image.isHidden=picture == nil;self.scroll.isHidden=picture != nil
                    let wrap=config.viewerWordWrap && !isHex
                    self.text.font=isHex ? .monospacedSystemFont(ofSize:config.viewerFontSize,weight:.regular) : NSFont(name:config.viewerFontName,size:config.viewerFontSize) ?? .systemFont(ofSize:config.viewerFontSize)
                    self.text.isHorizontallyResizable = !wrap;self.scroll.hasHorizontalScroller = !wrap
                    self.text.textContainer?.widthTracksTextView=wrap
                    self.text.textContainer?.containerSize=NSSize(width:wrap ? max(1,self.scroll.contentSize.width) : 100_000,height:CGFloat.greatestFiniteMagnitude)
                    if wrap {self.text.setFrameSize(NSSize(width:max(1,self.scroll.contentSize.width),height:self.text.frame.height))}
                    self.text.string=output;self.text.scrollToBeginningOfDocument(nil);self.detail.stringValue=info
                    self.previous.isEnabled=isHex && selectedPage > 0;self.next.isEnabled=isHex && selectedPage+1 < doc.pageCount
                }
            } catch { DispatchQueue.main.async { [weak self] in guard let self,self.generation == token else { return };self.message(error.localizedDescription) } }
        }
    }
}
extension CommanderController {
    @objc func toggleQuickView() {
        if let current=objc_getAssociatedObject(self,&quickViewAssociation) as? QuickViewCoordinator { current.closeView();return }
        let preview=QuickViewCoordinator(commander:self,source:activePane,target:otherPane)
        objc_setAssociatedObject(self,&quickViewAssociation,preview,.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    func reconfigureQuickView() {(objc_getAssociatedObject(self,&quickViewAssociation) as? QuickViewCoordinator)?.render()}
    func updateQuickView() { (objc_getAssociatedObject(self,&quickViewAssociation) as? QuickViewCoordinator)?.refresh() }
}
