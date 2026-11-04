import AppKit
import Darwin

private final class DirectoryTreeNode:NSObject {
    let location:PaneLocation
    let name:String
    weak var parent:DirectoryTreeNode?
    var children:[DirectoryTreeNode]=[]
    var loaded=false,loading=false
    var error:String?
    var task:FTPTask?
    init(location:PaneLocation,name:String,parent:DirectoryTreeNode?=nil){self.location=location;self.name=name;self.parent=parent}
    deinit {task?.cancel()}
}
private final class DirectoryOutline:NSOutlineView {
    var keyHandler:((NSEvent)->Bool)?
    var activate:(()->Void)?
    override func becomeFirstResponder()->Bool{activate?();return super.becomeFirstResponder()}
    override func keyDown(with event:NSEvent){if keyHandler?(event)==true{return};super.keyDown(with:event)}
}
final class DirectoryTreeView:NSView,NSOutlineViewDataSource,NSOutlineViewDelegate {
    weak var pane:Pane?
    var onOpenLocation:((PaneLocation)->Void)?
    private var revealTarget:PaneLocation?
    private let outline=DirectoryOutline()
    private let message=NSTextField(labelWithString:"Expand a folder; Return opens it in the opposite pane.")
    private var root:DirectoryTreeNode?
    private var generation=0
    private var nodeCount=0
    private var showHidden=false
    private var configuration=CommanderConfiguration()
    var responder:NSResponder {outline}
    var visibleFolderNames:[String] {(0..<outline.numberOfRows).compactMap{(outline.item(atRow:$0) as? DirectoryTreeNode)?.name}}
    var rootIsLoading:Bool {root?.loading ?? false}
    var selectedLocation:PaneLocation? {(outline.item(atRow:outline.selectedRow) as? DirectoryTreeNode)?.location}
    override init(frame:NSRect){
        super.init(frame:frame)
        let column=NSTableColumn(identifier:.init("folder"));column.title="Directory tree";column.width=350
        outline.addTableColumn(column);outline.outlineTableColumn=column;outline.headerView=nil;outline.delegate=self;outline.dataSource=self;outline.rowHeight=22;outline.target=self;outline.doubleAction=#selector(openSelected)
        outline.setAccessibilityLabel("Directory tree")
        outline.activate={ [weak self] in self?.pane?.onActivate?() }
        outline.keyHandler={ [weak self] event in self?.handleKey(event) ?? false }
        let scroll=NSScrollView();scroll.documentView=outline;scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=true
        let stack=NSStackView(views:[scroll,message]);stack.orientation = .vertical;stack.alignment = .leading
        addSubview(stack);stack.translatesAutoresizingMaskIntoConstraints=false;message.lineBreakMode = .byTruncatingMiddle;message.font = .systemFont(ofSize:11)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:leadingAnchor),stack.trailingAnchor.constraint(equalTo:trailingAnchor),stack.topAnchor.constraint(equalTo:topAnchor),stack.bottomAnchor.constraint(equalTo:bottomAnchor),scroll.widthAnchor.constraint(equalTo:stack.widthAnchor),scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:150),message.widthAnchor.constraint(equalTo:stack.widthAnchor)])
    }
    required init?(coder:NSCoder){fatalError()}
    override func viewDidChangeEffectiveAppearance(){super.viewDidChangeEffectiveAppearance();refreshAppearanceRendering()}
    func refreshAppearanceRendering(){outline.backgroundColor=AppearanceSettings.palette(configuration,appearance:effectiveAppearance).background.nsColor;outline.reloadData()}
    func applyConfiguration(_ config:CommanderConfiguration) {
        let ignoreChanged=configuration.ignoreListEnabled != config.ignoreListEnabled || configuration.ignorePatterns != config.ignorePatterns
        configuration=config;outline.rowHeight=max(config.rowHeight,Double(config.iconSize+4));outline.backgroundColor=AppearanceSettings.palette(config,appearance:effectiveAppearance).background.nsColor
        let changed=showHidden != config.showHidden || ignoreChanged;showHidden=config.showHidden
        outline.reloadData();if changed,root != nil {refresh()}
    }
    private func canonicalDirectory(_ url:URL)->URL {
        guard let path=realpath(url.path,nil) else{return url.standardizedFileURL}
        defer{free(path)};return URL(fileURLWithPath:String(cString:path),isDirectory:true)
    }
    func setRoot(_ location:PaneLocation,showHidden:Bool){
        cancel();revealTarget=nil;self.showHidden=showHidden;generation += 1;nodeCount=1
        let canonical:PaneLocation
        if case .local(let url)=location {canonical = .local(canonicalDirectory(url))}else{canonical=location}
        root=DirectoryTreeNode(location:canonical,name:canonical.displayPath);outline.reloadData();outline.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
        if let root {load(root)}
    }
    func refresh(){if let root{setRoot(root.location,showHidden:showHidden)}}
    func cancel(){
        func stop(_ node:DirectoryTreeNode){node.task?.cancel();for child in node.children{stop(child)}}
        if let root{stop(root)};generation += 1
    }
    func outlineView(_ outlineView:NSOutlineView,numberOfChildrenOfItem item:Any?)->Int {item == nil ? (root == nil ? 0:1):(item as? DirectoryTreeNode)?.children.count ?? 0}
    func outlineView(_ outlineView:NSOutlineView,child index:Int,ofItem item:Any?)->Any {if let item=item as? DirectoryTreeNode{return item.children[index]};return root!}
    func outlineView(_ outlineView:NSOutlineView,isItemExpandable item:Any)->Bool {guard let node=item as? DirectoryTreeNode else{return false};return !node.loaded || !node.children.isEmpty}
    func outlineView(_ outlineView:NSOutlineView,viewFor tableColumn:NSTableColumn?,item:Any)->NSView? {
        guard let node=item as? DirectoryTreeNode else{return nil}
        let cell=NSTableCellView(),text=NSTextField(labelWithString:node.name+(node.loading ? " …":"")),icon=NSImageView()
        icon.image=configuration.iconMode == .none ? nil:NSImage(systemSymbolName:"folder.fill",accessibilityDescription:"Folder");icon.contentTintColor = .systemBlue
        let font=NSFont(name:configuration.fileFontName,size:configuration.fileFontSize) ?? NSFont.systemFont(ofSize:configuration.fileFontSize)
        text.font=configuration.fileFontBold ? NSFontManager.shared.convert(font,toHaveTrait:.boldFontMask):font;text.textColor=outline.row(forItem:node)==outline.selectedRow ? AppearanceSettings.palette(configuration,appearance:effectiveAppearance).selectionForeground.nsColor:AppearanceSettings.palette(configuration,appearance:effectiveAppearance).foreground.nsColor
        cell.addSubview(icon);cell.addSubview(text);cell.imageView=icon;cell.textField=text;text.lineBreakMode = .byTruncatingMiddle;cell.toolTip=node.location.displayPath
        icon.translatesAutoresizingMaskIntoConstraints=false;text.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([icon.leadingAnchor.constraint(equalTo:cell.leadingAnchor),icon.centerYAnchor.constraint(equalTo:cell.centerYAnchor),icon.widthAnchor.constraint(equalToConstant:CGFloat(configuration.iconSize)),icon.heightAnchor.constraint(equalToConstant:CGFloat(configuration.iconSize)),text.leadingAnchor.constraint(equalTo:icon.trailingAnchor,constant:5),text.trailingAnchor.constraint(equalTo:cell.trailingAnchor),text.centerYAnchor.constraint(equalTo:cell.centerYAnchor)])
        return cell
    }
    func outlineViewItemWillExpand(_ notification:Notification){if let node=notification.userInfo?["NSObject"] as? DirectoryTreeNode {load(node)}}
    func outlineView(_ outlineView:NSOutlineView,rowViewForItem item:Any)->NSTableRowView? {let view=PaneSelectionRow();view.selectionColor=AppearanceSettings.palette(configuration,appearance:effectiveAppearance).selectionBackground.nsColor;return view}
    func outlineViewSelectionDidChange(_ notification:Notification){
        if let node=outline.item(atRow:outline.selectedRow) as? DirectoryTreeNode{message.stringValue=node.error ?? node.location.displayPath}
        let range=outline.rows(in:outline.visibleRect)
        if range.location != NSNotFound {for row in range.location..<min(outline.numberOfRows,range.location+range.length){(outline.view(atColumn:0,row:row,makeIfNecessary:false) as? NSTableCellView)?.textField?.textColor=row==outline.selectedRow ? AppearanceSettings.palette(configuration,appearance:effectiveAppearance).selectionForeground.nsColor:AppearanceSettings.palette(configuration,appearance:effectiveAppearance).foreground.nsColor}}
    }
    private func load(_ node:DirectoryTreeNode){
        guard !node.loaded,!node.loading,nodeCount<20000 else{return}
        node.loading=true;let token=generation,task=FTPTask(),hidden=showHidden,ignore=configuration.ignoreListEnabled,patterns=configuration.ignorePatterns;node.task=task
        DispatchQueue.global(qos:.userInitiated).async { [weak self,weak node] in
            guard let node else{return}
            let result=Result {try node.location.list(showHidden:hidden,task:task).filter{$0.isDirectory && !$0.isSymbolicLink && (!ignore || patterns.isEmpty || !PanelFilter.matches(name:$0.name,mask:patterns))}.map{(try node.location.child($0),$0.name)}}
            DispatchQueue.main.async { [weak self,weak node] in
                guard let self,let node,self.generation==token,!task.isCancelled else{return}
                node.loading=false;node.task=nil
                switch result {
                case .success(let children):
                    guard self.nodeCount+children.count<=20000 else{node.error="Tree limit of 20,000 directories reached.";self.message.stringValue=node.error!;return}
                    node.children=children.map{DirectoryTreeNode(location:$0.0,name:$0.1,parent:node)};node.loaded=true;self.nodeCount += children.count
                    self.outline.reloadItem(node,reloadChildren:true);self.outline.expandItem(node);self.continueReveal()
                case .failure(let error):node.error=error.localizedDescription;self.message.stringValue=error.localizedDescription;self.outline.reloadItem(node)
                }
            }
        }
    }
    func reveal(_ location:PaneLocation){if case .local(let url)=location{revealTarget = .local(canonicalDirectory(url))}else{revealTarget=location};continueReveal()}
    private func continueReveal(){
        guard let target=revealTarget,let root else{return}
        var chain:[PaneLocation]=[],cursor:PaneLocation?=target
        for _ in 0..<256 {
            guard let current=cursor else{break};chain.append(current)
            if current==root.location{break};cursor=current.parent
        }
        guard chain.last==root.location else{revealTarget=nil;return}
        var node=root
        for next in chain.reversed().dropFirst() {
            if !node.loaded{load(node);return}
            var child=node.children.first(where:{$0.location==next})
            if child == nil {
                // The already-open pane proves this ancestor belongs to its path. macOS
                // hides ancestors such as /private even when their descendants are open.
                // Keep that known branch visible, but never override an explicit ignore rule.
                let name=next.shortName
                guard nodeCount<20000, !configuration.ignoreListEnabled || configuration.ignorePatterns.isEmpty || !PanelFilter.matches(name:name,mask:configuration.ignorePatterns) else {revealTarget=nil;return}
                let known=DirectoryTreeNode(location:next,name:name,parent:node)
                node.children.append(known);node.children.sort{$0.name.localizedStandardCompare($1.name) == .orderedAscending}
                nodeCount += 1;outline.reloadItem(node,reloadChildren:true);child=known
            }
            outline.expandItem(node);node=child!
        }
        let row=outline.row(forItem:node)
        if row>=0{outline.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false);outline.scrollRowToVisible(row)}
        revealTarget=nil
    }
    @objc private func openSelected(){if let location=selectedLocation{if let onOpenLocation{onOpenLocation(location)}else{pane?.onTreeOpen?(location)}}}
    private func handleKey(_ event:NSEvent)->Bool {
        let m=event.modifierFlags.intersection([.control,.shift,.option,.command]),key=event.keyCode
        if m.isEmpty {
            if key==36 || key==76 {openSelected();return true}
            if key==69 || key==124 {if let node=outline.item(atRow:outline.selectedRow) as? DirectoryTreeNode{load(node);outline.expandItem(node)};return true}
            if key==78 || key==123 {if let node=outline.item(atRow:outline.selectedRow) as? DirectoryTreeNode{if outline.isItemExpanded(node){outline.collapseItem(node)}else if let parent=node.parent{let row=outline.row(forItem:parent);outline.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)}};return true}
            if key==120 {refresh();return true}
            if key==125 || key==126 || key==115 || key==119 || key==116 || key==121{return false}
            if key==48 {return pane?.onKey?(event) ?? false}
            // Hidden file rows must never receive mutation/view commands from tree focus.
            NSSound.beep();return true
        }
        if m == [.control],event.charactersIgnoringModifiers?.lowercased()=="r" {refresh();return true}
        if [UInt16(122),120,100].contains(key),m == [.control] || m == [.control,.shift] {return pane?.onKey?(event) ?? false}
        return true
    }
}
