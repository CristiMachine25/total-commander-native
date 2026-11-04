import AppKit

let navy = NSColor(srgbRed: 0.94, green: 0.94, blue: 0.94, alpha: 1)
let cyan = NSColor(srgbRed: 0.12, green: 0.37, blue: 0.65, alpha: 1)
let yellow = NSColor.systemRed
let mono = NSFont(name:"Tahoma",size:13) ?? NSFont.systemFont(ofSize:13)

func label(_ text: String, color: NSColor = .black, size: CGFloat = 13) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = NSFont(name:"Tahoma",size:size) ?? NSFont.systemFont(ofSize:size)
    field.textColor = color
    field.lineBreakMode = .byTruncatingMiddle
    return field
}

final class CommanderTable: NSTableView {
    var keyHandler: ((NSEvent) -> Bool)?
    var focusHandler: (() -> Void)?
    var contextMenuHandler: ((Int) -> NSMenu?)?
    var selectAllHandler: (() -> Void)?
    override func selectAll(_ sender: Any?) { selectAllHandler?() }
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { focusHandler?() }
        return result
    }
    override func menu(for event:NSEvent)->NSMenu? {contextMenuHandler?(row(at:convert(event.locationInWindow,from:nil)))}
    override func rightMouseDown(with event:NSEvent) {if let menu=menu(for:event){NSMenu.popUpContextMenu(menu,with:event,for:self)}}
    override func mouseDown(with event:NSEvent) {
        if event.modifierFlags.contains(.control) {rightMouseDown(with:event);return}
        super.mouseDown(with:event)
    }
    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true { return }
        super.keyDown(with: event)
    }
}

final class BlueRow: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        cyan.withAlphaComponent(isEmphasized ? 0.32 : 0.16).setFill()
        bounds.fill()
    }
}

final class Pane: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let view = NSView()
    let table = CommanderTable()
    private let fileScroll=NSScrollView()
    private let briefScroll=NSScrollView()
    private let fileContainer=BriefViewport()
    let briefGrid=BriefGridView(frame:.zero)
    private let thumbnailScroll=NSScrollView()
    let thumbnailGrid=ThumbnailGridView(frame:.zero)
    let directoryTree=DirectoryTreeView(frame:.zero)
    private var driveRowView:NSView?
    private var storedHeader:NSTableHeaderView?
    private let viewPreferenceKey:String
    private(set) var configuration=CommanderConfiguration()
    var remembersViewMode=false
    private(set) var viewMode:PaneViewMode = .full
    var isTreeMode:Bool {viewMode == .tree}
    var selectedLocation:PaneLocation? {isTreeMode ? directoryTree.selectedLocation:nil}
    var onTreeOpen:((PaneLocation)->Void)?
    var singleClickOpen:Bool {configuration.singleClickOpen}
    var fileMask=""
    var showProgramsOnly=false
    var selectedOnly:Set<URL>?

    let path = NSTextField()
    let footer = label("", color: cyan, size: 11)
    let heading = label("", color: yellow)
    var directory: URL
    var location: PaneLocation
    var loadGeneration = 0
    var loadTask: FTPTask?
    var isLoading = false
    var entries: [FileEntry] = []
    private var listedEntries:[FileEntry]=[]
    var refreshListedEntries:[FileEntry] {listedEntries}
    private var configurationApplied=false
    private var cachedFont:NSFont=mono
    private let systemIcons:NSCache<NSURL,NSImage>={let cache=NSCache<NSURL,NSImage>();cache.countLimit=512;return cache}()
    var marked = Set<URL>()
    var onSelectionChanged: (() -> Void)?
    private var normalContent: NSView?
    private(set) var quickViewOverlay: NSView?
    var onActivate: (() -> Void)?
    var onOpen: (() -> Void)?
    var onPath: ((String) -> Void)?
    var onLocal: ((URL) -> Void)?
    var onKey: ((NSEvent) -> Bool)?
    var onContextMenu: ((Int) -> NSMenu?)?
    var contextMenuAllowed: (() -> Bool)?
    var backHistory: [PaneLocation] = []
    var forwardHistory: [PaneLocation] = []
    var tabs: [PaneLocation] = []
    var selectedTab = 0
    var lockedTabRoots:[Int:URL] = [:]
    let tabControl = CommanderTabControl()
    let volumePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    var locations: [URL] = []
    var onTab: ((Int) -> Void)?
    var sortColumn = "name"
    var ascending = true
    var filter = ""
    var brief = false
    var savedSelection = Set<URL>()
    var active = false { didSet { updateAppearance() } }
    private let format: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "dd.MM.yy HH:mm"; return f
    }()

    init(directory: URL, title: String) {
        viewPreferenceKey="pane.viewMode."+title
        self.directory = directory
        self.location = .local(directory)
        self.tabs = [.local(directory)]
        super.init()
        view.wantsLayer = true
        view.layer?.backgroundColor = navy.cgColor
        view.layer?.borderWidth = 1
        view.layer?.borderColor = cyan.cgColor
        heading.stringValue = title
        locations = [FileManager.default.homeDirectoryForCurrentUser, URL(fileURLWithPath: "/")] + (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []).filter { $0.path != "/" }
        for (index, location) in locations.enumerated() { volumePopup.addItem(withTitle: index == 0 ? "Home" : (location.path == "/" ? "/" : location.lastPathComponent)) }
        volumePopup.target = self; volumePopup.action = #selector(volumeSelected)
        volumePopup.font = mono
        path.font = mono
        path.isBezeled = false
        path.drawsBackground = true
        path.textColor = .black
        path.backgroundColor = .white
        path.focusRingType = .none
        path.placeholderString = "Folder path — Return to open"
        path.target = self; path.action = #selector(pathEntered)
        path.toolTip = "Enter a folder path. ⌘L focuses the active path field."
        let scroll = fileScroll
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.backgroundColor = navy
        table.backgroundColor = .white
        table.rowHeight = 21
        table.intercellSpacing = NSSize(width: 8, height: 0)
        table.usesAlternatingRowBackgroundColors = false
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = false
        table.style = .plain
        table.gridColor = cyan.withAlphaComponent(0.25)
        table.gridStyleMask = [.solidVerticalGridLineMask]
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.dataSource = self; table.delegate = self
        table.target = self; table.doubleAction = #selector(doubleClick);table.action = #selector(singleClick)
        table.focusRingType = .none
        table.setAccessibilityLabel("\(title) files")
        table.keyHandler = { [weak self] event in
            guard let self else {return false}
            if self.brief,self.briefGrid.handleNavigation(event) {return true}
            if self.viewMode == .thumbnails,self.thumbnailGrid.handleNavigation(event) {return true}
            return self.onKey?(event) ?? false
        }
        table.focusHandler = { [weak self] in self?.onActivate?() }
        table.contextMenuHandler = { [weak self] row in self?.contextMenu(forRow:row) }
        table.selectAllHandler = { [weak self] in
            guard let self = self else { return }
            self.marked = Set(self.entries.filter{self.configuration.selectionIncludesDirectories || !$0.isDirectory}.map(\.url))
            self.table.reloadData(); self.updateFooter()
        }
        for (id, title, width) in [("name", "Name", 225.0), ("ext", "Ext", 50.0), ("size", "Size", 80.0), ("date", "Date", 130.0), ("attr", "Attr", 40.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title; column.width = width
            column.minWidth = id == "name" ? 130 : width
            column.headerCell.font = NSFont(name:"Tahoma-Bold",size:12) ?? NSFont.systemFont(ofSize:12,weight:.semibold)
            column.minWidth=32;column.maxWidth=1200
            table.addTableColumn(column)
        }
        storedHeader=table.headerView
        scroll.documentView = table
        briefGrid.pane=self;briefScroll.documentView=briefGrid
        briefScroll.hasHorizontalScroller=true;briefScroll.hasVerticalScroller=false;briefScroll.autohidesScrollers=false;briefScroll.backgroundColor = .white
        thumbnailGrid.pane=self;thumbnailScroll.documentView=thumbnailGrid
        thumbnailScroll.hasVerticalScroller=true;thumbnailScroll.backgroundColor = .white
        directoryTree.pane=self
        for child in [scroll,briefScroll,thumbnailScroll,directoryTree] {fileContainer.addSubview(child)}
        briefScroll.isHidden=true;thumbnailScroll.isHidden=true;directoryTree.isHidden=true
        for child in [scroll,briefScroll,thumbnailScroll,directoryTree] {
            child.translatesAutoresizingMaskIntoConstraints=false
            NSLayoutConstraint.activate([child.leadingAnchor.constraint(equalTo:fileContainer.leadingAnchor),child.trailingAnchor.constraint(equalTo:fileContainer.trailingAnchor),child.topAnchor.constraint(equalTo:fileContainer.topAnchor),child.bottomAnchor.constraint(equalTo:fileContainer.bottomAnchor)])
        }
        fileContainer.resized={ [weak self] in if self?.brief == true {self?.briefGrid.updateGeometry()};if self?.viewMode == .thumbnails {self?.thumbnailGrid.updateGeometry()} }

        tabControl.segmentStyle = .smallSquare
        tabControl.trackingMode = .selectOne; tabControl.target = self; tabControl.action = #selector(tabClicked)
        tabControl.closeOnDoubleClick = { [weak self] in self?.configuration.tabsCloseOnDoubleClick ?? false }
        updateTabs()
        let driveRow = NSStackView(views: [volumePopup, heading]);driveRowView=driveRow; driveRow.orientation = .horizontal; driveRow.spacing = 8
        let stack = NSStackView(views: [driveRow, tabControl, path, fileContainer, footer])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 3
        normalContent = stack
        view.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        for v in [path, fileContainer, footer] {
            v.translatesAutoresizingMaskIntoConstraints = false
            v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            fileContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 180)
        ])
    }

    var fileResponder:NSResponder {switch viewMode {case .brief:return briefGrid;case .thumbnails:return thumbnailGrid;case .tree:return directoryTree.responder;case .full:return table}}
    func setBriefMode(_ enabled:Bool) {setFileViewMode(enabled ? .brief:.full)}
    @discardableResult func setThumbnailMode()->Bool {
        guard location.localDirectory != nil else{return false};setFileViewMode(.thumbnails);return true
    }
    func setTreeMode(root:PaneLocation) {
        setFileViewMode(.tree);directoryTree.setRoot(root,showHidden:configuration.showHidden)
    }
    private func setFileViewMode(_ mode:PaneViewMode) {
        if viewMode == .tree,mode != .tree {directoryTree.cancel()}
        viewMode=mode;brief=mode == .brief
        fileScroll.isHidden=mode != .full;briefScroll.isHidden=mode != .brief;thumbnailScroll.isHidden=mode != .thumbnails;directoryTree.isHidden=mode != .tree
        if remembersViewMode {UserDefaults.standard.set(mode.rawValue,forKey:viewPreferenceKey)}
        path.isHidden=mode == .tree || !configuration.showCurrentDirectory;updateTabs()
        view.layoutSubtreeIfNeeded();briefGrid.updateGeometry();thumbnailGrid.updateGeometry()
        if mode == .brief {briefGrid.revealSelection()};if mode == .thumbnails {thumbnailGrid.revealSelection()}
        if active {view.window?.makeFirstResponder(fileResponder)}
    }
    func restoreViewMode() {
        guard remembersViewMode else{return}
        switch PaneViewMode(rawValue:UserDefaults.standard.string(forKey:viewPreferenceKey) ?? "full") ?? .full {
        case .brief:setBriefMode(true)
        case .thumbnails:_=setThumbnailMode()
        case .tree:setTreeMode(root:.local(URL(fileURLWithPath:"/")))
        case .full:setBriefMode(false)
        }
    }
    func applyConfiguration(_ input:CommanderConfiguration) {
        let next=input.normalized(),previous=configuration
        guard !configurationApplied || next != previous else{return}
        let firstApply = !configurationApplied
        let refilter=firstApply || next.ignoreListEnabled != previous.ignoreListEnabled || next.ignorePatterns != previous.ignorePatterns
        let resort=refilter || next.directoriesFirst != previous.directoriesFirst || next.caseSensitiveSort != previous.caseSensitiveSort
        configuration=next;configurationApplied=true
        let base=NSFont(name:configuration.fileFontName,size:configuration.fileFontSize) ?? NSFont.systemFont(ofSize:configuration.fileFontSize)
        cachedFont=configuration.fileFontBold ? NSFontManager.shared.convert(base,toHaveTrait:.boldFontMask):base
        footer.isHidden = !configuration.showStatusBar
        driveRowView?.isHidden = !configuration.showDriveList;path.isHidden = viewMode == .tree || !configuration.showCurrentDirectory
        table.headerView=configuration.showColumnHeaders ? storedHeader:nil
        table.rowHeight=max(configuration.rowHeight,Double(configuration.iconSize+4));table.backgroundColor=configuration.background.nsColor
        fileScroll.backgroundColor=configuration.background.nsColor;briefScroll.backgroundColor=configuration.background.nsColor
        for column in table.tableColumns {
            let key=column.identifier.rawValue;column.isHidden = !configuration.visibleColumns.contains(key) || (key == "ext" && configuration.extensionStyle == .afterName)
            column.width=configuration.columnWidths[key] ?? column.width
        }
        if firstApply || configuration.thumbnailSize != previous.thumbnailSize {
            thumbnailGrid.pixels=configuration.thumbnailSize;thumbnailGrid.invalidateListing()
        }
        directoryTree.applyConfiguration(configuration);updateTabs()
        if resort {
            let selected=Set(table.selectedRowIndexes.compactMap{ $0>0 && $0<=entries.count ? entries[$0-1].url:nil })
            if refilter {entries=displayEntries(listedEntries)}
            sortEntries();table.reloadData()
            let rows=IndexSet(entries.enumerated().compactMap{selected.contains($0.element.url) ? $0.offset+1:nil})
            table.selectRowIndexes(rows.isEmpty ? IndexSet(integer:0):rows,byExtendingSelection:false)
        } else {
            let selection=table.selectedRowIndexes
            table.reloadData();table.selectRowIndexes(selection,byExtendingSelection:false)
        }
        briefGrid.updateGeometry();updateDriveHeading();updateFooter()
    }
    var configuredFont:NSFont {cachedFont}
    func systemIcon(for entry:FileEntry)->NSImage {
        let key=entry.url as NSURL
        if let icon=systemIcons.object(forKey:key) {return icon}
        let icon=NSWorkspace.shared.icon(forFile:entry.url.path)
        systemIcons.setObject(icon,forKey:key);return icon
    }
    func itemBackground(row:Int)->NSColor {configuration.alternatingRowBackground && row%2 == 1 ? configuration.alternatingBackground.nsColor:configuration.background.nsColor}
    func itemColor(marked:Bool,selected:Bool)->NSColor {selected ? configuration.selectionForeground.nsColor:(marked ? configuration.markedForeground.nsColor:configuration.foreground.nsColor)}
    func showQuickView(_ overlay:NSView) {
        quickViewOverlay?.removeFromSuperview()
        normalContent?.isHidden=true
        quickViewOverlay=overlay;view.addSubview(overlay);overlay.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([overlay.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:4),overlay.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-4),overlay.topAnchor.constraint(equalTo:view.topAnchor,constant:4),overlay.bottomAnchor.constraint(equalTo:view.bottomAnchor,constant:-4)])
    }
    func hideQuickView() {
        quickViewOverlay?.removeFromSuperview();quickViewOverlay=nil;normalContent?.isHidden=false
    }
    @objc private func volumeSelected() { let index = volumePopup.indexOfSelectedItem; if locations.indices.contains(index) { onActivate?();if isTreeMode {setTreeMode(root:.local(locations[index]))}else{onLocal?(locations[index])} } }
    @objc private func tabClicked() { onTab?(tabControl.selectedSegment) }
    func updateTabs() {
        tabControl.isHidden = viewMode == .tree || !configuration.showFolderTabs || (!configuration.tabsAlwaysVisible && tabs.count < 2)
        tabControl.segmentCount = tabs.count
        for (i,u) in tabs.enumerated() {
            let label=(configuration.tabsShowLockAsterisk && lockedTabRoots[i] != nil ? "*" : "")+String(u.shortName.prefix(configuration.tabTitleMaximum))
            tabControl.setLabel(label,forSegment:i)
            tabControl.setWidth(max(40,(label as NSString).size(withAttributes:[.font:tabControl.font ?? NSFont.systemFont(ofSize:12)]).width+24),forSegment:i)
        }
        tabControl.selectedSegment = selectedTab
    }
    func storeTab() { tabs[selectedTab] = location; updateTabs() }
    @objc private func pathEntered() { onActivate?(); onPath?(path.stringValue) }
    @objc private func singleClick() {if configuration.singleClickOpen,table.clickedRow>=0,NSApp.currentEvent?.modifierFlags.intersection([.control,.shift,.option,.command]).isEmpty != false {onActivate?();onOpen?()}}
    @objc private func doubleClick() { if !configuration.singleClickOpen,table.clickedRow >= 0 { onActivate?(); onOpen?() } }
    func numberOfRows(in tableView: NSTableView) -> Int { entries.count + 1 }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let identifier=NSUserInterfaceItemIdentifier("pane.row")
        let view=(tableView.makeView(withIdentifier:identifier,owner:self) as? PaneSelectionRow) ?? PaneSelectionRow()
        view.identifier=identifier;view.selectionColor=configuration.selectionBackground.nsColor;view.backgroundColor=itemBackground(row:row);return view
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row <= entries.count else { return nil }
        let key = tableColumn?.identifier.rawValue ?? "name"
        let text: String
        if row == 0 {
            text = key == "name" ? "[..]" : (key == "size" ? "<UP>" : "")
        } else {
            let e = entries[row - 1]
            switch key {
            case "ext": text = e.isDirectory ? "" : e.url.pathExtension
            case "attr": text = e.isSymbolicLink ? "link" : (e.isDirectory ? "d---" : "-a--")
            case "size": text = e.isDirectory ? "<DIR>" : configuration.sizeString(e.size)
            case "date": text = e.modified.map { configuration.dateString($0) } ?? "—"
            default:
                let prefix = marked.contains(e.url) ? "✓ " : ""
                text = prefix + (e.isDirectory ? "[" + e.name + "]" : (configuration.extensionStyle == .afterName || (e.name as NSString).pathExtension.isEmpty ? e.name : (e.name as NSString).deletingPathExtension))
            }
        }
        let hasIcon=key == "name" && configuration.iconMode != .none
        let identifier=NSUserInterfaceItemIdentifier("pane.cell.\(key).\(hasIcon ? configuration.iconSize:0)")
        let reused=tableView.makeView(withIdentifier:identifier,owner:self)
        let container=hasIcon ? ((reused as? NSTableCellView) ?? NSTableCellView()):nil
        let cell=container?.textField ?? (reused as? NSTextField) ?? label("")
        cell.stringValue=text;cell.font=configuredFont
        cell.textColor=itemColor(marked:row>0 && marked.contains(entries[row-1].url),selected:table.selectedRowIndexes.contains(row))
        cell.alignment=key == "size" ? .right:.left
        cell.toolTip=row == 0 ? "Parent folder":entries[row-1].url.path
        guard let container else {cell.identifier=identifier;return cell}
        container.identifier=identifier
        let entry=row == 0 ? nil:entries[row-1]
        let symbol=row == 0 ? "arrow.up.backward":(entry?.isSymbolicLink == true ? "link":(entry?.isDirectory == true ? "folder.fill":"doc"))
        let icon=container.imageView ?? NSImageView()
        icon.image=NSImage(systemSymbolName:symbol,accessibilityDescription:row == 0 ? "Parent folder":(entry?.isDirectory == true ? "Folder":"File"))
        icon.imageScaling = .scaleProportionallyDown
        if configuration.iconMode == .system,let entry,location.localDirectory != nil {icon.image=systemIcon(for:entry)}
        icon.contentTintColor=entry?.isDirectory == true ? .systemBlue:.secondaryLabelColor
        if container.textField == nil {
            // Reuse the label, image and constraints as rows enter/leave the viewport.
            container.imageView=icon;container.textField=cell
            container.addSubview(icon);container.addSubview(cell)
            icon.translatesAutoresizingMaskIntoConstraints=false;cell.translatesAutoresizingMaskIntoConstraints=false
            cell.lineBreakMode = .byTruncatingMiddle;cell.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
            NSLayoutConstraint.activate([icon.leadingAnchor.constraint(equalTo:container.leadingAnchor,constant:2),icon.centerYAnchor.constraint(equalTo:container.centerYAnchor),icon.widthAnchor.constraint(equalToConstant:CGFloat(configuration.iconSize)),icon.heightAnchor.constraint(equalToConstant:CGFloat(configuration.iconSize)),cell.leadingAnchor.constraint(equalTo:icon.trailingAnchor,constant:5),cell.trailingAnchor.constraint(equalTo:container.trailingAnchor,constant:-2),cell.centerYAnchor.constraint(equalTo:container.centerYAnchor)])
        }
        container.toolTip=row == 0 ? "Parent folder":entry?.name
        container.setAccessibilityLabel(row == 0 ? "Parent folder":entry!.name)
        return container
    }
    func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
        let column = tableColumn.identifier.rawValue
        if sortColumn == column { ascending.toggle() } else { sortColumn = column; ascending = true }
        let selected = Set(table.selectedRowIndexes.compactMap { row in row > 0 && row <= entries.count ? entries[row-1].url : nil })
        sortEntries(); table.reloadData()
        let rows = IndexSet(entries.enumerated().compactMap { selected.contains($0.element.url) ? $0.offset + 1 : nil })
        table.selectRowIndexes(rows.isEmpty ? IndexSet(integer: 0) : rows, byExtendingSelection: false)
        updateFooter()
    }
    func sortEntries() {
        guard sortColumn != "unsorted" else{return}
        func compareName(_ a:String,_ b:String)->ComparisonResult {configuration.caseSensitiveSort ? a.compare(b):a.localizedStandardCompare(b)}
        entries.sort { a,b in
            if configuration.directoriesFirst,a.isDirectory != b.isDirectory { return a.isDirectory }
            let comparison: ComparisonResult
            switch sortColumn {
            case "ext": comparison = compareName((a.name as NSString).pathExtension,(b.name as NSString).pathExtension)
            case "size": comparison = a.size == b.size ? compareName(a.name,b.name) : (a.size < b.size ? .orderedAscending : .orderedDescending)
            case "date": comparison = (a.modified ?? .distantPast).compare(b.modified ?? .distantPast)
            default: comparison = configuration.caseSensitiveSort ? a.name.compare(b.name):compareName(a.name,b.name)
            }
            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }
    func tableViewSelectionDidChange(_ notification: Notification) { updateFooter(); if brief {briefGrid.revealSelection()};if viewMode == .thumbnails {thumbnailGrid.revealSelection()}; refreshVisibleColors();onSelectionChanged?() }
    private func refreshVisibleColors() {
        let range=table.rows(in:table.visibleRect)
        guard range.location != NSNotFound else{return}
        for row in range.location..<min(table.numberOfRows,range.location+range.length) {
            for column in table.tableColumns.indices {
                let view=table.view(atColumn:column,row:row,makeIfNecessary:false)
                let field=(view as? NSTextField) ?? (view as? NSTableCellView)?.textField
                field?.textColor=itemColor(marked:row>0 && row<=entries.count && marked.contains(entries[row-1].url),selected:table.selectedRowIndexes.contains(row))
            }
        }
    }
    func load(_ url: URL, showHidden: Bool) throws {
        let next = PaneLocation.local(url.standardizedFileURL)
        let listing = try next.list(showHidden:showHidden)
        applyListing(listing,location:next)
    }
    func applyListing(_ listing:[FileEntry], location next:PaneLocation,updateHeader:Bool=true) {
        briefGrid.resetSelectionAnchor();systemIcons.removeAllObjects()
        let old=currentEntry?.url, same=location.identity == next.identity
        location=next
        if let local=next.localDirectory { directory=local }
        listedEntries=listing;entries=displayEntries(listing);sortEntries()
        thumbnailGrid.invalidateListing()
        if viewMode == .thumbnails,next.localDirectory == nil {setBriefMode(false)}
        marked=same ? marked.intersection(Set(entries.map(\.url))) : []
        path.stringValue=next.displayPath
        if updateHeader {updateDriveHeading()}
        table.reloadData()
        let row=same ? entries.firstIndex(where:{$0.url == old}).map{$0+1} ?? 0 : 0
        table.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false);table.scrollRowToVisible(row);updateFooter()
    }
    private func displayEntries(_ listing:[FileEntry])->[FileEntry] {
        return listing.filter { entry in
            (filter.isEmpty || entry.name.localizedCaseInsensitiveContains(filter)) &&
            (fileMask.isEmpty || entry.isDirectory || PanelFilter.matches(name:entry.name,mask:fileMask)) &&
            (!showProgramsOnly || entry.isDirectory || PanelFilter.isProgram(entry)) &&
            (selectedOnly == nil || selectedOnly!.contains(entry.url)) &&
            (!configuration.ignoreListEnabled || configuration.ignorePatterns.isEmpty || !PanelFilter.matches(name:entry.name,mask:configuration.ignorePatterns))
        }
    }
    private func updateDriveHeading() {
        if let local=location.localDirectory,let attributes=try? FileManager.default.attributesOfFileSystem(forPath:local.path),let free=attributes[.systemFreeSize] as? NSNumber,let total=attributes[.systemSize] as? NSNumber {
            heading.stringValue="\(configuration.footerSizeString(free.int64Value)) of \(configuration.footerSizeString(total.int64Value)) free"
        }else{heading.stringValue=location.shortName}
    }
    var selectedEntries:[FileEntry] {
        if !marked.isEmpty {return entries.filter{marked.contains($0.url)}}
        return table.selectedRowIndexes.compactMap{row in row>0 && row<=entries.count ? entries[row-1]:nil}
    }
    var currentEntry: FileEntry? {
        let i = table.selectedRow - 1
        return entries.indices.contains(i) ? entries[i] : nil
    }
    var selectedURLs: [URL] {
        if !marked.isEmpty { return entries.filter { marked.contains($0.url) }.map(\.url) }
        return table.selectedRowIndexes.compactMap { row in
            row > 0 && row <= entries.count ? entries[row - 1].url : nil
        }
    }
    func toggleMark() {
        guard let entry = currentEntry else { return }
        if marked.contains(entry.url) { marked.remove(entry.url) } else { marked.insert(entry.url) }
        let next = min(table.selectedRow + 1, entries.count)
        table.reloadData(); table.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        table.scrollRowToVisible(next); updateFooter()
    }
    func clearMarks() { marked.removeAll(); table.reloadData(); updateFooter() }
    func updateFooter() {
        if brief {briefGrid.updateGeometry()};if viewMode == .thumbnails {thumbnailGrid.updateGeometry()}
        let selected=selectedEntries,count=selected.count
        let total=selected.filter{!$0.isDirectory}.reduce(Int64(0)) {sum,entry in let (value,overflow)=sum.addingReportingOverflow(max(0,entry.size));return overflow ? Int64.max:value}
        footer.stringValue = "\(entries.count) items  ·  \(count) selected · \(configuration.footerSizeString(total))" + (marked.isEmpty ? "" : "  ·  Space marks, Esc clears")
    }
    private func updateAppearance() {
        view.layer?.borderColor = (active ? NSColor.black : NSColor.darkGray.withAlphaComponent(0.45)).cgColor
        view.layer?.borderWidth = 1
        path.backgroundColor = active ? NSColor(srgbRed: 0.22, green: 0.55, blue: 0.94, alpha: 1) : NSColor.gray
        path.textColor = .white
        heading.textColor = active ? NSColor.black : NSColor.darkGray
        table.needsDisplay = true;briefGrid.needsDisplay=true;thumbnailGrid.needsDisplay=true
    }
}

class CommanderController: NSObject, NSWindowDelegate, NSUserInterfaceValidations {
    let window: NSWindow
    let left: Pane
    let right: Pane
    var activeIndex = 0
    var activePane: Pane { activeIndex == 0 ? left : right }
    var otherPane: Pane { activeIndex == 0 ? right : left }
    let status = label("Ready", color: cyan, size: 11)
    private var buttons: [NSButton] = []
    private let workQueue = DispatchQueue(label: "classic-commander.file-operations", qos: .userInitiated)
    var busy = false
    var showHidden = false
    let remember: Bool
    private var keyMonitor: Any?
    var runtimeConfig = CommanderConfiguration.load()
    var menuRow: NSStackView!
    var buttonBar: NSStackView!
    var barScroll: NSScrollView!
    var barHeight: NSLayoutConstraint?
    var barConfiguration = CommanderButtonBar()
    var barEditor: ButtonBarEditor?
    var functionBar: NSStackView!
    var quickSearchText=""
    var quickSearchTime:TimeInterval=0
    var providerClipboard: (PaneLocation,[FileEntry])?
    var providerClipboardChange = -1
    var commandField: NSTextField!
    var splitView: NSSplitView!
    var splitInitialized = false
    var materializations: [PaneReadableMaterialization] = []
    var archiveParents: [ObjectIdentifier:PaneLocation] = [:]
    var deferredArchiveUpdates: [(ArchiveBrowserSession,ArchiveBrowserSession)] = []
    var archiveLeases: [ObjectIdentifier:PaneReadableMaterialization] = [:]

    init(initial: URL? = nil, remember: Bool = true) {
        self.remember = remember
        let home = FileManager.default.homeDirectoryForCurrentUser
        let prefs = UserDefaults.standard
        let l = initial ?? prefs.string(forKey: "leftPath").map { URL(fileURLWithPath: $0) } ?? home
        let r = initial ?? prefs.string(forKey: "rightPath").map { URL(fileURLWithPath: $0) } ?? home
        left = Pane(directory: l, title: "LEFT")
        right = Pane(directory: r, title: "RIGHT")
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 700), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        if !remember {runtimeConfig=CommanderConfiguration()}
        window.title = "Total Commander Native — Development"
        window.subtitle = ""
        window.minSize = NSSize(width: 920, height: 440)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = navy
        let root = NSView(); root.wantsLayer = true; root.layer?.backgroundColor = navy.cgColor
        window.contentView = root
        let top = NSStackView(); menuRow = top; top.orientation = .horizontal; top.spacing = 12
        for title in ["Files", "Mark", "Commands", "Net", "Show", "Configuration", "Start", "Help"] {
            let b = NSButton(title: title, target: self, action: #selector(openMenuButton(_:)))
            b.isBordered = false; b.font = .systemFont(ofSize: 13); top.addArrangedSubview(b)
        }
        barConfiguration = remember ? CommanderButtonBar.load() : CommanderButtonBar()
        let strip=CommanderButtonStrip();buttonBar=strip;strip.orientation = .horizontal;strip.spacing=6
        strip.configure = { [weak self] in self?.configureButtonBar() }
        let toolbar=NSScrollView();barScroll=toolbar;toolbar.hasHorizontalScroller=true;toolbar.hasVerticalScroller=false;toolbar.autohidesScrollers=true;toolbar.drawsBackground=false;toolbar.documentView=strip
        strip.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([strip.leadingAnchor.constraint(equalTo:toolbar.contentView.leadingAnchor),strip.topAnchor.constraint(equalTo:toolbar.contentView.topAnchor)])
        barHeight=toolbar.heightAnchor.constraint(equalToConstant:48);barHeight?.isActive=true
        rebuildButtonBar()
        let command = NSTextField(); command.placeholderString = "Command line — cd /path or run a command"; command.font = mono
        command.target = self; command.action = #selector(runCommand(_:)); commandField = command
        let panes = NSSplitView(); splitView = panes; panes.isVertical = true; panes.dividerStyle = .thin; panes.addArrangedSubview(left.view); panes.addArrangedSubview(right.view)
        let actionBar = NSStackView(); functionBar = actionBar; actionBar.orientation = .horizontal; actionBar.distribution = .fillEqually; actionBar.spacing = 3
        let names = ["Help", "Refresh", "View", "Edit", "Copy", "Move", "NewFolder", "Delete", "Menu", "Left menu"]
        for (i, name) in names.enumerated() {
            let b = NSButton(title: "F\(i + 1) \(name)", target: self, action: #selector(functionButton(_:)))
            b.tag = i + 1; b.bezelStyle = .smallSquare; b.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
            b.contentTintColor = cyan
            b.toolTip = "\(name) — F\(i + 1) (you may need Fn on a Mac keyboard)"
            if (3...8).contains(i + 1) { actionBar.addArrangedSubview(b) }; buttons.append(b)
        }
        let quitButton = NSButton(title: "Alt+F4 Exit", target: self, action: #selector(exitApp)); quitButton.bezelStyle = .smallSquare; actionBar.addArrangedSubview(quitButton)
        let workArea = NSStackView(views:[separateTrees.leftView,panes,separateTrees.rightView]);workArea.orientation = .horizontal;workArea.spacing=4;workArea.distribution = .fill
        panes.setContentHuggingPriority(.defaultLow,for:.horizontal)
        for child in [separateTrees.leftView,panes,separateTrees.rightView] {child.heightAnchor.constraint(equalTo:workArea.heightAnchor).isActive=true}
        let stack = NSStackView(views: [top, toolbar, workArea, status, command, actionBar]); stack.orientation = .vertical; stack.spacing = 4; stack.alignment = .leading
        root.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        for v in [top, toolbar, workArea, status, command, actionBar] {
            v.translatesAutoresizingMaskIntoConstraints = false; v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 5), stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -5),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 5), stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -5),
            actionBar.heightAnchor.constraint(equalToConstant: 28)
        ])
        for (i, pane) in [left, right].enumerated() {
            pane.onActivate = { [weak self] in self?.activate(i, focus: false) }
            pane.onTab = { [weak self, weak pane] index in
                guard let self, let pane, pane.tabs.indices.contains(index), !self.busy else { return }
                self.activate(i)
                // A click on the current tab is focus, not Refresh. Reloading here
                // would leave FTP tabs busy before their double-click close arrives.
                if index != pane.selectedTab {self.selectTab(index,pane:pane)}
            }
            pane.tabControl.onClose = { [weak self,weak pane] index in guard let self,let pane else{return};self.activate(i);self.closeFolderTab(index,pane:pane) }
            pane.tabControl.contextMenu = { [weak self,weak pane] index in guard let pane else{return nil};return self?.tabContextMenu(index,pane:pane) }
            pane.onOpen = { [weak self] in self?.openCurrent() }
            pane.onSelectionChanged = { [weak self] in self?.updateQuickView() }
            pane.onLocal = { [weak self,weak pane] url in guard let pane else{return};self?.navigate(url,pane:pane) }
            pane.onPath = { [weak self] text in self?.go(text) }
            pane.onKey = { [weak self] event in self?.handleKey(event) ?? false }
            do { try pane.load(pane.directory, showHidden: false) }
            catch { try? pane.load(home, showHidden: false); status.stringValue = "Could not reopen saved folder: \(error.localizedDescription)" }
        }
        applyAppearancePreferences()
        restoreSession()
        for pane in [left,right] {
            pane.remembersViewMode=remember
            let opposite=pane === left ? right : left
            pane.onTreeOpen={ [weak self,weak opposite] location in guard let self,let opposite else{return};self.navigate(location,pane:opposite,focus:false)}
            pane.restoreViewMode()
        }
        installFileContextMenus()
        activate(0)
        separateTrees.restore()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, event.window === self.window, self.window.attachedSheet == nil else { return event }
            if self.handleFieldEscape(event) {return nil}
            if self.handleCustomShortcut(event) {return nil}
            let functionKeys: Set<UInt16> = [122,120,99,118,96,97,98,100,101,109]
            if functionKeys.contains(event.keyCode), self.handleKey(event) { return nil }
            return event
        }
    }
    deinit { if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) } }
    func show() {
        if !splitInitialized {window.center();restoreWindowPosition()}
        window.makeKeyAndOrderFront(nil);window.contentView?.layoutSubtreeIfNeeded()
        if !splitInitialized {
            let saved=UserDefaults.standard.double(forKey:"savedDividerRatio"),ratio=saved>0.1 && saved<0.9 ? saved : 0.5
            splitView.setPosition((splitView.isVertical ? splitView.bounds.width : splitView.bounds.height)*ratio,ofDividerAt:0);splitInitialized=true
        }
        window.makeFirstResponder(activePane.fileResponder)
    }
    func activate(_ index: Int, focus: Bool = true) {
        if (index == 0 ? left : right).quickViewOverlay != nil {toggleQuickView();return}
        if activeIndex != index {quickSearchText=""}
        activeIndex = index; left.active = index == 0; right.active = index == 1
        separateTrees.refreshRoots()
        if focus { window.makeFirstResponder(activePane.fileResponder) }
    }
    @discardableResult func navigate(_ url:URL,pane:Pane?=nil) -> Bool { navigate(.local(url),pane:pane) }
    func go(_ path:String) {
        do {
            let next=try activePane.location.resolvePath(path)
            navigate(next)
        } catch { showError(error) }
    }
    func handleKey(_ event: NSEvent) -> Bool {
        if handleCustomShortcut(event) { return true }
        guard window.attachedSheet == nil else { return false }
        if activePane.isLoading { if event.keyCode == 53 {activePane.loadTask?.cancel()}; return true }
        let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let keys: [UInt16:Int] = [122:1,120:2,99:3,118:4,96:5,97:6,98:7,100:8,101:9,109:10]
        if let key = keys[event.keyCode], mods.isEmpty { performFunction(key); return true }
        if handleExtendedKey(event, modifiers: mods) { return true }
        if mods == [.option] {
            if event.keyCode == 98 { searchFiles(); return true }
            if event.keyCode == 96 { packFiles(); return true }
            if event.keyCode == 101 { unpackFiles(); return true }
            if event.keyCode == 118 { NSApp.terminate(nil); return true }
            if event.keyCode == 123 { backFolder(); return true }
            if event.keyCode == 124 { forwardFolder(); return true }
            if event.keyCode == 120 { activate(1); places(); return true }
            if event.keyCode == 122 { activate(0); places(); return true }
        }
        if mods == [.control] {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "m": multiRename(); return true
            case "r": refreshSource(); return true
            case "u": swap(); return true
            case "t": newTab(); return true
            case "w": closeTab(); return true
            case "a": selectAllFiles(); return true
            case "d": places(); return true
            default: break
            }
        }
        if mods == [.shift], event.keyCode == 97 { renameCurrent(); return true }
        if mods.isEmpty,event.keyCode==53,!quickSearchText.isEmpty {quickSearchText="";status.stringValue=activePane.location.displayPath;return true}
        if handleQuickSearch(event) {return true}
        if !mods.isEmpty { return false }
        switch event.keyCode {
        case 48: activate(activeIndex == 0 ? 1 : 0); return true
        case 36, 76: if commandField.stringValue.isEmpty { openCurrent() } else { runCommand(commandField) }; return true
        case 51: parent(); return true
        case 49, 114: activePane.toggleMark(); return true
        case 117: trash(); return true
        case 53: if !activePane.filter.isEmpty { activePane.filter = ""; refreshSource() }; commandField.stringValue = ""; activePane.clearMarks(); return true
        case 115: activePane.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false); activePane.table.scrollRowToVisible(0); return true
        case 119: let n = activePane.entries.count; activePane.table.selectRowIndexes(IndexSet(integer: n), byExtendingSelection: false); activePane.table.scrollRowToVisible(n); return true
        default:
            if let text = event.characters, !text.isEmpty, text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && $0.value < 0xF700 }) { commandField.stringValue += text; focusCommand(); return true }; return false
        }
    }
    @objc func functionButton(_ sender: NSButton) { performFunction(sender.tag) }
    func performFunction(_ key: Int) {
        if busy && key != 1 { NSSound.beep(); return }
        switch key {
        case 1: help()
        case 2: refreshSource()
        case 3: viewFile(editable: false)
        case 4: viewFile(editable: true)
        case 5: transfer(move: false)
        case 6: transfer(move: true)
        case 7: makeFolder()
        case 8: trash()
        case 9: sourceMenu()
        case 10: sourceMenu()
        default: break
        }
    }
    @objc func menuAction(_ item: NSMenuItem) { performFunction(item.tag) }
    @objc func openCurrent() {
        if activePane.isTreeMode {if let location=activePane.directoryTree.selectedLocation {navigate(location,pane:otherPane,focus:false)};return}
        guard !busy, !activePane.isLoading else { return }
        if activePane.table.selectedRow == 0 { parent(); return }
        guard let entry=activePane.currentEntry else {return}
        if entry.isDirectory { do { navigate(try activePane.location.child(entry)) } catch {showError(error)} }
        else if NativeOperations.recognizesArchive(name:entry.name),runtimeConfig.browseArchivesAsDirectories || activePane.location.localDirectory == nil { openArchiveInPane(entry) }
        else if activePane.location.localDirectory != nil {
            if !NSWorkspace.shared.open(entry.url) {
                if NativeOperations.recognizesArchive(name:entry.name) {openArchiveInPane(entry)} else {viewFile(editable:false)}
            }
        } else { viewFile(editable:false) }
    }
    func viewFile(editable:Bool) {
        guard permitFileAction() else{return}
        guard !activePane.isLoading, let entry=activePane.currentEntry,!entry.isDirectory else {NSSound.beep();return}
        let location=activePane.location
        if let _=location.localDirectory {
            do {
                if let external = configuredExternalApplication(editable:editable) {
                    NSWorkspace.shared.open([entry.url],withApplicationAt:external,configuration:NSWorkspace.OpenConfiguration()) { [weak self] _,error in if let error {DispatchQueue.main.async {self?.showError(error)}} }
                } else if editable {try EditorController.open(url:entry.url,editable:true)} else {try ListerController.open(url:entry.url)}
            } catch {showError(error)}
        } else {
            if editable { if case .archive = location {openArchiveEditor(entry:entry)} else {openRemoteEditor(entry:entry)};return }
            runOperation("Opening file",success:"Opened read-only viewer") { [weak self] in
                let lease=try location.readableMaterialization(entry)
                DispatchQueue.main.async {do {try ListerController.open(url:lease.url);self?.materializations.append(lease)} catch {self?.showError(error)}}
            }
        }
    }
    func transfer(move: Bool) {
        guard permitFileAction(),!otherPane.isTreeMode else{return}
        guard !activePane.isLoading,!otherPane.isLoading else {return}
        if activePane.location.localDirectory == nil || otherPane.location.localDirectory == nil { transferBetweenProviders(move:move);return }
        let sources = activePane.selectedURLs
        guard !sources.isEmpty else { NSSound.beep(); return }
        let target = otherPane.directory,settings=runtimeConfig
        let enqueue: (String)->Void = { [weak self] value in
            guard let self else{return}
            let expanded=(value as NSString).expandingTildeInPath
            guard expanded.hasPrefix("/") else {self.showMessage("Use an absolute path","The destination must begin with / or ~.");return}
            let options=NativeTransferOptions(preserveDirectoryDates:settings.copyPreserveDirectoryDates,preserveFileDates:settings.copyPreserveFileDates,preservePermissions:settings.copyPreservePermissions,verifyAfterCopy:settings.copyVerifyAfterCopy,bufferSizeKB:settings.copyBufferSizeKB)
            let policy:TransferCollisionPolicy
            switch settings.copyDefaultCollision {case "skip":policy = .skip;case "replace":policy = .replace;case "rename":policy = .rename;default:policy = .ask}
            TransferQueueController.enqueue(sources:sources,destination:URL(fileURLWithPath:expanded),move:move,options:options,defaultPolicy:policy,confirmPolicy:settings.confirmCopyMove,confirmOverwrite:settings.confirmOverwrite) { [weak self] result in
                self?.refresh();self?.status.stringValue=result.summary
                if !result.errors.isEmpty {self?.showMessage("Transfer finished with errors",result.summary)}
            }
        }
        if settings.confirmCopyMove {
            prompt(title:"\(move ? "Move" : "Copy") \(sources.count) item\(sources.count == 1 ? "" : "s")",detail:"Destination folder. Choose conflict handling before the transfer starts.\n\(sources.prefix(3).map(\.lastPathComponent).joined(separator:", "))",value:target.path,action:move ? "Move" : "Copy",completion:enqueue)
        } else {enqueue(target.path)}
    }
    @objc func renameCurrent() {
        guard permitFileAction() else{return}
        if activePane.location.localDirectory == nil { renameProviderEntry();return }
        guard !busy, let entry = activePane.currentEntry else { return }
        prompt(title: "Rename", detail: entry.url.path, value: entry.name, action: "Rename") { [weak self] name in
            self?.runOperation("Renaming", success: "Renamed to \(name)") { try FileService.rename(entry.url, toName: name) }
        }
    }
    func makeFolder() {
        if activePane.location.localDirectory == nil { makeProviderFolder();return }
        let directory = activePane.directory
        prompt(title: "New folder", detail: directory.path, value: "New Folder", action: "Create") { [weak self] name in
            self?.runOperation("Creating folder", success: "Created \(name)") { try FileService.makeDirectory(in: directory, name: name) }
        }
    }
    func trash() {
        guard permitFileAction() else{return}
        if activePane.location.localDirectory == nil {deleteProviderEntries();return}
        let sources=activePane.selectedURLs
        guard !sources.isEmpty else{NSSound.beep();return}
        let useTrash=runtimeConfig.deleteToTrash
        let perform:()->Void = { [weak self] in
            self?.runOperation(useTrash ? "Moving to Trash" : "Deleting permanently",success:useTrash ? "Moved \(sources.count) item(s) to Trash" : "Deleted \(sources.count) item(s)") {
                if useTrash {try FileService.trash(sources)} else {try FileService.deletePermanently(sources)}
            }
        }
        // Disabling routine confirmation affects recoverable Trash only. Permanent
        // deletion always requires a fresh confirmation for the actual selection.
        if useTrash && !runtimeConfig.confirmDelete {perform();return}
        let alert=NSAlert();alert.messageText=useTrash ? "Move \(sources.count) item(s) to Trash?" : "Permanently delete \(sources.count) item(s)?"
        alert.informativeText=sources.prefix(5).map(\.lastPathComponent).joined(separator:"\n") + (useTrash ? "\n\nYou can restore these items from the macOS Trash." : "\n\nThis cannot be undone. These items will not go to Trash.")
        alert.alertStyle = .warning;alert.addButton(withTitle:useTrash ? "Move to Trash" : "Delete permanently");alert.addButton(withTitle:"Cancel")
        alert.beginSheetModal(for:window){response in if response == .alertFirstButtonReturn {perform()}}
    }
    func prompt(title: String, detail: String, value: String, action: String, completion: @escaping (String) -> Void) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail
        alert.addButton(withTitle: action); alert.addButton(withTitle: "Cancel")
        let input = NSTextField(string: value); input.frame = NSRect(x: 0, y: 0, width: 480, height: 25); input.font = mono
        alert.accessoryView = input; alert.window.initialFirstResponder = input
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { completion(input.stringValue) }
        }
    }
    func runOperation(_ name: String, success: String, operation: @escaping () throws -> Void) {
        guard !busy else { return }
        busy = true; buttons.forEach { $0.isEnabled = false }; status.stringValue = "\(name)… Please wait."
        workQueue.async { [weak self] in
            let error: Error?
            do { try operation(); error = nil } catch let failure { error = failure }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.busy = false; self.drainArchiveUpdates(); self.buttons.forEach { $0.isEnabled = true }
                self.refresh()
                if let error = error { self.showError(error) } else { self.status.stringValue = success }
            }
        }
    }
    @objc func refresh() { guard !busy else {return}; reloadPane(left);reloadPane(right) }
    @objc func hidden(_ item: NSMenuItem) { showHidden.toggle(); runtimeConfig.showHidden=showHidden; if remember { try? runtimeConfig.save() }; item.state = showHidden ? .on : .off; refresh() }
    @objc func focusPath() { window.makeFirstResponder(activePane.path); activePane.path.selectText(nil) }
    @objc func parent() { if case .archive(let session,let path)=activePane.location,path.isEmpty,let up=archiveParents[ObjectIdentifier(session)] {navigate(up)} else if let up=activePane.location.parent {navigate(up)} }
    @objc func swap() {
        guard !busy else { return }
        let l = left.location, r = right.location, original = activeIndex
        navigate(r, pane: left); navigate(l, pane: right); activate(original)
    }
    @objc func selectAllFiles() {
        activePane.marked = Set(activePane.entries.filter{runtimeConfig.selectionIncludesDirectories || !$0.isDirectory}.map(\.url)); activePane.table.reloadData(); activePane.updateFooter()
    }
    @objc func placeSelected(_ item: NSMenuItem) { if let path = item.representedObject as? URL { navigate(path) } }
    func places() {
        let menu = NSMenu(title: "Places")
        let home = FileManager.default.homeDirectoryForCurrentUser
        var locations = [("Home", home), ("Desktop", home.appendingPathComponent("Desktop")), ("Documents", home.appendingPathComponent("Documents")), ("Downloads", home.appendingPathComponent("Downloads")), ("Root /", URL(fileURLWithPath: "/"))]
        for url in FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? [] {
            if url.path != "/" { locations.append((url.lastPathComponent, url)) }
        }
        let saved = UserDefaults.standard.stringArray(forKey:"directoryHotlist") ?? []
        for path in saved where !locations.contains(where: { $0.1.path == path }) { locations.append((path,URL(fileURLWithPath:path))) }
        for (title, url) in locations {
            let item = NSMenuItem(title: title, action: #selector(placeSelected(_:)), keyEquivalent: ""); item.target = self; item.representedObject = url; menu.addItem(item)
        }
        menu.addItem(.separator())
        let add=NSMenuItem(title:"Add current directory",action:#selector(addHotlist),keyEquivalent:""); add.target=self; menu.addItem(add)
        let remove=NSMenuItem(title:"Remove current directory",action:#selector(removeHotlist),keyEquivalent:""); remove.target=self; remove.isEnabled=saved.contains(activePane.directory.path); menu.addItem(remove)
        menu.popUp(positioning: nil, at: NSPoint(x:0,y:activePane.path.bounds.height), in:activePane.path)
    }
    func sourceMenu() {
        let menu = makeMenu("Files")
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: buttons[8].bounds.height), in: buttons[8])
    }
    func commands() {
        let menu = NSMenu(title: "Commands")
        for (title, selector) in [("Refresh both panels", #selector(refresh)), ("Rename selected item…", #selector(renameCurrent)), ("Swap panels", #selector(swap)), ("Select all", #selector(selectAllFiles)), ("Go to path", #selector(focusPath))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: buttons[8].bounds.height), in: buttons[8])
    }
    @objc func help() {
        showMessage("Total Commander Native — Keyboard guide", "Tab: switch panels\n↑ / ↓: navigate · Return: open · Backspace: parent\nSpace: mark and advance · Esc: clear marks\n⌘A: mark all · ⌘L: enter a folder path · ⌘R: refresh\n\nF3 View · F4 Edit · F5 Copy · F6 Move\nF7 New folder · F8 Delete · F9 Menu · F10 Left menu\nUse Files → Rename (⌘⇧R) to rename in place.\n\nMac keyboards may need Fn with function keys. Every action is also available from menus or buttons.\n\nCopy and move use a queue with explicit conflict choices. Ctrl+F opens FTP, Ctrl+M opens rename masks, Ctrl+S filters names. Text editing supports UTF-8 files up to 4 MiB.")
    }
    func showError(_ error: Error) { status.stringValue = error.localizedDescription; showMessage("Operation could not finish", error.localizedDescription) }
    func showMessage(_ title: String, _ body: String) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = body; alert.addButton(withTitle: "OK")
        if window.isVisible { alert.beginSheetModal(for: window) } else { status.stringValue = "\(title): \(body)" }
    }
    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        return (!busy && !activePane.isLoading) || item.action == #selector(help)
    }
    func canQuit() -> Bool {
        saveSession()
        if TransferQueueController.hasPendingJobs || SynchronizationController.hasActiveTransfers || ArchiveBrowserController.hasActiveTransfers || FTPBrowserWindow.hasActiveTransfers { showMessage("Transfers in progress","Finish or cancel the active transfers before quitting."); return false }
        if left.isLoading || right.isLoading {left.loadTask?.cancel();right.loadTask?.cancel();showMessage("Loading folders","Cancelling pending folder loads. Try quitting again after they finish.");return false}
        if busy { showMessage("File operation in progress", "Please wait for the current operation to finish before quitting."); return false }
        let canClose=EditorController.requestCloseAll(); if canClose { FTPBrowserWindow.shutdown() }; return canClose
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { NSApp.terminate(nil); return false }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var commander: CommanderController!
    func applicationDidFinishLaunching(_ notification: Notification) {
        commander = CommanderController(); installMenus(); commander.show(); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { commander.canQuit() ? .terminateNow : .terminateCancel }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { commander.show(); return true }
    @objc func about() {
        commander.showMessage("Total Commander Native — Development", "Independent native macOS reimplementation under development. No Wine or Windows runtime. Based on an audit of Total Commander 11.58.1. This build is not feature-complete; the accompanying parity report lists recovered evidence and unimplemented functionality.")
    }
    func installMenus() {
        let main = NSMenu()
        let appMenu = NSMenu(); let appItem = NSMenuItem(); appItem.submenu = appMenu; main.addItem(appItem)
        let aboutItem = NSMenuItem(title: "About Total Commander Native", action: #selector(about), keyEquivalent: ""); aboutItem.target = self; appMenu.addItem(aboutItem)
        appMenu.addItem(.separator()); appMenu.addItem(withTitle: "Hide Total Commander Native", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Total Commander Native", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let files = NSMenu(title: "Files"); let fileItem = NSMenuItem(title: "Files", action: nil, keyEquivalent: ""); fileItem.submenu = files; main.addItem(fileItem)
        for (title, key, tag) in [("View…", "", 3), ("Edit…", "", 4), ("Copy to other panel…", "", 5), ("Move to other panel…", "", 6), ("New folder…", "n", 7), ("Move to Trash…", "", 8)] {
            let item = NSMenuItem(title: title, action: #selector(CommanderController.menuAction(_:)), keyEquivalent: key); item.tag = tag; item.target = commander; files.addItem(item)
        }
        let rename = NSMenuItem(title: "Rename…", action: #selector(CommanderController.renameCurrent), keyEquivalent: "r"); rename.keyEquivalentModifierMask = [.command, .shift]; rename.target = commander; files.addItem(rename)
        let edit = NSMenu(title: "Edit"); let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); editItem.submenu = edit; main.addItem(editItem)
        for (title, action, key) in [("Undo", Selector(("undo:")), "z"), ("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSResponder.selectAll(_:)), "a"), ("Save", #selector(EditorController.saveDocument(_:)), "s")] {
            edit.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        let panels = NSMenu(title: "Panels"); let panelItem = NSMenuItem(title: "Panels", action: nil, keyEquivalent: ""); panelItem.submenu = panels; main.addItem(panelItem)
        for (title, action, key) in [("Go to Path…", #selector(CommanderController.focusPath), "l"), ("Parent Folder", #selector(CommanderController.parent), "↑"), ("Refresh", #selector(CommanderController.refresh), "r"), ("Swap Panels", #selector(CommanderController.swap), "u"), ("Mark All", #selector(CommanderController.selectAllFiles), "a"), ("Show Hidden Files", #selector(CommanderController.hidden(_:)), ".")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = commander; panels.addItem(item)
        }
        let help = NSMenu(title: "Help"); let helpItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: ""); helpItem.submenu = help; main.addItem(helpItem)
        let guide = NSMenuItem(title: "Keyboard Guide", action: #selector(CommanderController.help), keyEquivalent: "?"); guide.target = commander; help.addItem(guide)
        for title in ["Mark", "Commands", "Net", "Show", "Configuration", "Start"] {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: ""); item.submenu = commander.makeMenu(title); main.addItem(item)
        }
        fileItem.submenu = commander.makeMenu("Files")
        // Keep Cocoa editing equivalents available without adding foreign top-level menus.
        for existing in main.items where existing.submenu === edit || existing.submenu === panels { main.removeItem(existing) }
        for source in [edit, panels] {
            for item in source.items {
                source.removeItem(item); item.isHidden = true; item.allowsKeyEquivalentWhenHidden = true; appMenu.addItem(item)
            }
        }
        let close = NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        close.isHidden = true; close.allowsKeyEquivalentWhenHidden = true; appMenu.addItem(close)
        for item in main.items where item !== appItem { main.removeItem(item) }
        for title in ["Files", "Mark", "Commands", "Net", "Show", "Configuration", "Start", "Help"] {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = commander.makeMenu(title); main.addItem(item)
        }
        NSApp.mainMenu = main
    }
}

@main struct NativeCommander {
    static func main() {
        let app = NSApplication.shared
        if CommandLine.arguments.contains("--provider-smoke-test") {
            app.setActivationPolicy(.prohibited)
            do {try providerSmokeTest()} catch {fputs("\(error)\n",stderr);exit(1)}
            return
        }
        if CommandLine.arguments.contains("--smoke-test") {
            app.setActivationPolicy(.prohibited)
            do { try smokeTest(); try configurationSmokeTest(); print("UI smoke tests passed") } catch { fputs("\(error)\n", stderr); exit(1) }
            return
        }
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
    static func smokeTest() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("classic-ui-\(UUID().uuidString)")
        try fm.createDirectory(at: base, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: base) }
        try fm.createDirectory(at: base.appendingPathComponent("Documents"), withIntermediateDirectories: false)
        try fm.createDirectory(at: base.appendingPathComponent("Projects"), withIntermediateDirectories: false)
        try Data("Welcome to Total Commander Native\n".utf8).write(to: base.appendingPathComponent("Welcome.txt"))
        try Data("test".utf8).write(to: base.appendingPathComponent(".hidden"))
        let c = CommanderController(initial: base, remember: false)
        precondition(c.left.entries.count == 3 && c.right.entries.count == 3)
        precondition(c.left.entries.first?.isDirectory == true)
        func press(_ key: UInt16) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: c.window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: key)!
            c.activePane.table.keyDown(with: event)
        }
        press(48); precondition(c.activeIndex == 1 && c.right.active && !c.left.active)
        c.right.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        press(36); precondition(c.right.directory.lastPathComponent == "Documents")
        press(51); precondition(c.right.directory.path == base.path)
        press(119); precondition(c.right.table.selectedRow == 3)
        press(49); precondition(c.right.marked.count == 1)
        press(53); precondition(c.right.marked.isEmpty)
        press(115); precondition(c.right.table.selectedRow == 0)
        c.left.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        c.left.toggleMark(); precondition(c.left.marked.count == 1 && c.left.selectedURLs.count == 1)
        c.left.clearMarks(); precondition(c.left.marked.isEmpty)
        c.navigate(base.appendingPathComponent("Documents")); precondition(c.right.directory.lastPathComponent == "Documents")
        c.parent(); precondition(c.right.directory.path == base.path)
        c.hidden(NSMenuItem()); precondition(c.right.entries.count == 4)
        c.hidden(NSMenuItem()); precondition(c.right.entries.count == 3)
        c.activate(0); c.selectAllFiles(); precondition(c.left.selectedURLs.count == 3)
        c.left.clearMarks()
        c.left.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        c.left.toggleMark(); c.left.table.selectAll(nil)
        precondition(c.left.selectedURLs.count == 3)
        c.left.clearMarks()
        c.navigate(base.appendingPathComponent("Documents"), pane: c.right)
        c.activate(0); c.swap()
        precondition(c.activeIndex == 0 && c.left.directory.lastPathComponent == "Documents" && c.right.directory.path == base.path)
        c.navigate(base, pane: c.left); c.activate(0)
        c.newTab(); precondition(c.left.tabs.count == 2 && c.left.selectedTab == 1)
        c.navigate(base.appendingPathComponent("Projects")); precondition(c.left.tabs[1].shortName == "Projects")
        c.backFolder(); precondition(c.left.directory.path == base.path)
        c.forwardFolder(); precondition(c.left.directory.lastPathComponent == "Projects")
        c.closeTab(); precondition(c.left.tabs.count == 1 && c.left.directory.path == base.path)
        c.left.sortColumn = "size"; c.left.sortEntries(); precondition(c.left.entries.first?.isDirectory == true)
        c.left.sortColumn = "name"; c.left.sortEntries()
        c.left.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        let selectedBeforeSort = c.left.currentEntry?.url
        c.left.tableView(c.left.table, didClick: c.left.table.tableColumns[0])
        precondition(c.left.currentEntry?.url == selectedBeforeSort)
        let historyBeforeFailure = c.left.backHistory
        precondition(!c.navigate(base.appendingPathComponent("missing-folder")))
        precondition(c.left.backHistory == historyBeforeFailure && c.left.directory.path == base.path)
        c.left.backHistory.append(.local(base.appendingPathComponent("missing-history")))
        let failingHistory = c.left.backHistory; c.backFolder()
        precondition(c.left.backHistory == failingHistory && c.left.directory.path == base.path)
        precondition(c.makeMenu("Files").items.contains { $0.tag == 2400 || $0.action == #selector(CommanderController.multiRename) })
        c.performFunction(2); precondition(c.left.entries.count == 3)
        func shortcut(_ key: UInt16, _ mods: NSEvent.ModifierFlags, _ text: String = "") {
            let event = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:mods,timestamp:0,windowNumber:c.window.windowNumber,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:key)!
            precondition(c.handleKey(event))
        }
        shortcut(122,[.control]); precondition(c.left.brief && c.left.fileResponder !== c.left.table)
        shortcut(120,[.control]); precondition(!c.left.brief && c.left.fileResponder === c.left.table)
        shortcut(118,[.control]); precondition(c.left.sortColumn == "ext")
        shortcut(96,[.control]); precondition(c.left.sortColumn == "date")
        c.left.filter = "Welcome"; c.refreshSource(); precondition(c.left.entries.count == 1)
        shortcut(109,[.control]); precondition(c.left.entries.count == 3)
        let beforeTabs = c.left.tabs.count
        shortcut(17,[.control,.shift],"t"); precondition(c.left.tabs.count == beforeTabs + 1 && c.left.selectedTab == 0)
        shortcut(48,[.control]); precondition(c.left.selectedTab == 1)
        shortcut(48,[.control,.shift]); precondition(c.left.selectedTab == 0)
        c.runtimeConfig.confirmCloseAllTabs=false; shortcut(13,[.control,.shift],"w"); precondition(c.left.tabs.count == 1)
        shortcut(0,[],"a"); precondition(c.commandField.stringValue == "a")
        shortcut(53,[]); precondition(c.commandField.stringValue.isEmpty)
        c.window.contentView?.layoutSubtreeIfNeeded()
        if let pos = CommandLine.arguments.firstIndex(of: "--preview"), CommandLine.arguments.count > pos + 1,
           let view = c.window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if let png = bitmap.representation(using: .png, properties: [:]) { try png.write(to: URL(fileURLWithPath: CommandLine.arguments[pos + 1])) }
        }
        if Bundle.main.url(forResource:"WCMD_ENG",withExtension:"MNU") != nil {
            let delegate = AppDelegate(); delegate.commander = c; delegate.installMenus()
            precondition(NSApp.mainMenu!.items.dropFirst().map(\.title) == ["Files","Mark","Commands","Net","Show","Configuration","Start","Help"])
            let menu=c.makeMenu("Files")
            guard let rename=menu.items.first(where:{$0.tag==2400}) else {preconditionFailure("Original rename command missing")}
            c.busy=true;c.menuWillOpen(menu);precondition(!rename.isEnabled)
            c.busy=false;c.left.table.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false)
            c.menuWillOpen(menu);precondition(rename.isEnabled)
            precondition(menu.items.filter{$0.tag >= 0 && $0.representedObject is String && !ReferenceCommandRouting.isSupported($0.tag)}.allSatisfy{!$0.isEnabled})
        }
        precondition(!c.window.isVisible)
    }
}
