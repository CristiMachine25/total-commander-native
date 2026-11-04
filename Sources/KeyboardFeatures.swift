import AppKit

/// Physical ANSI key codes; Control is deliberately not substituted with Command.
/// This table is also the machine-readable contract exercised by ShortcutContractTests.
enum ShortcutContract {
    struct Binding {
        let key: UInt16
        let modifiers: NSEvent.ModifierFlags
        let action: String
        let reference: String
    }
    static let bindings: [Binding] = [
        .init(key:96, modifiers:[.shift], action:"copySameFolder", reference:"SHIFT+F5"),
        .init(key:98, modifiers:[.shift], action:"mkdirTarget", reference:"SHIFT+F7"),
        .init(key:109, modifiers:[.shift], action:"contextMenu", reference:"SHIFT+F10"),
        .init(key:32, modifiers:[.control,.shift], action:"swapTabs", reference:"CTRL+SHIFT+U"),
        .init(key:0, modifiers:[.control,.shift], action:"tabList", reference:"CTRL+SHIFT+A"),
        .init(key:48, modifiers:[.control], action:"nextTab", reference:"CTRL+TAB"),
        .init(key:48, modifiers:[.control,.shift], action:"previousTab", reference:"CTRL+SHIFT+TAB"),
        .init(key:123, modifiers:[.control], action:"openLeft", reference:"CTRL+left"),
        .init(key:124, modifiers:[.control], action:"openRight", reference:"CTRL+right"),
        .init(key:126, modifiers:[.control], action:"childTab", reference:"CTRL+UP"),
        .init(key:126, modifiers:[.control,.shift], action:"childTargetTab", reference:"CTRL+SHIFT+UP"),
        .init(key:69, modifiers:[.shift], action:"selectPatternFiles", reference:"SHIFT+NUM +"),
        .init(key:78, modifiers:[.shift], action:"unselectPatternFiles", reference:"SHIFT+NUM -"),
        .init(key:67, modifiers:[.shift], action:"invertFiles", reference:"SHIFT+NUM *"),
        .init(key:69, modifiers:[.control,.shift], action:"selectFiles", reference:"CTRL+SHIFT+NUM +"),
        .init(key:78, modifiers:[.control,.shift], action:"unselectFiles", reference:"CTRL+SHIFT+NUM -"),
        .init(key:69, modifiers:[.option], action:"selectExtension", reference:"ALT+NUM +"),
        .init(key:78, modifiers:[.option], action:"unselectExtension", reference:"ALT+NUM -")
    ]
    static func action(key:UInt16, modifiers:NSEvent.ModifierFlags) -> String? {
        let exact = modifiers.intersection([.control,.shift,.option,.command])
        return bindings.first { $0.key == key && $0.modifiers == exact }?.action
    }
    static func selection(current:Set<String>, files:Set<String>, operation:String) -> Set<String> {
        switch operation {
        case "selectFiles": return current.union(files)
        case "unselectFiles": return current.subtracting(files)
        case "invertFiles": return current.symmetricDifference(files)
        default: return current
        }
    }
    static func validCopyName(_ name:String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0")
    }
}

/// Original CHM options_compare.htm: mark missing/newer files, not all byte differences.
enum FileListComparison {
    struct Item {let id:Int;let name:String;let directory:Bool;let modified:Date?}
    struct Result {var left=Set<Int>();var right=Set<Int>();var unresolved=0}
    static func compare(_ left:[Item],_ right:[Item])->Result {
        func key(_ name:String)->String {name.precomposedStringWithCanonicalMapping.lowercased()}
        let a=Dictionary(grouping:left,by:{key($0.name)}),b=Dictionary(grouping:right,by:{key($0.name)})
        var result=Result()
        for name in Set(a.keys).union(b.keys) {
            let x=a[name] ?? [],y=b[name] ?? []
            guard x.count <= 1,y.count <= 1 else {result.unresolved += 1;continue}
            if let l=x.first,let r=y.first {
                guard !l.directory,!r.directory else {continue}
                guard let ld=l.modified,let rd=r.modified else {result.unresolved += 1;continue}
                if ld > rd {result.left.insert(l.id)} else if rd > ld {result.right.insert(r.id)}
            } else if let l=x.first,!l.directory {result.left.insert(l.id)}
            else if let r=y.first,!r.directory {result.right.insert(r.id)}
        }
        return result
    }
}

#if !SHORTCUT_CONTRACT_TEST

extension CommanderController {
    func performShortcutContract(_ action:String) {
        switch action {
        case "copySameFolder": copyWithinFolder()
        case "mkdirTarget": makeTargetFolder()
        case "contextMenu": keyboardContextMenu()
        case "swapTabs": swapPaneTabs()
        case "tabList": showTabList()
        case "nextTab": cycleTab(1)
        case "previousTab": cycleTab(-1)
        case "openLeft", "openRight":
            let target = action == "openLeft" ? left : right
            if target !== activePane, let entry=activePane.currentEntry,!entry.isDirectory,NativeOperations.recognizesArchive(name:entry.name) {
                openArchiveInPane(entry,source:activePane.location,target:target,newTab:false,focus:false)
            } else if target === activePane {navigate(activePane.location,pane:target,focus:false)}
            else {navigate(shortcutChildLocation(),pane:target,focus:false)}
        case "childTab", "childTargetTab":
            let target=action == "childTargetTab" ? otherPane : activePane
            if let entry=activePane.currentEntry,!entry.isDirectory,NativeOperations.recognizesArchive(name:entry.name) {
                openArchiveInPane(entry,source:activePane.location,target:target,newTab:true,focus:true)
            } else {openLocationInNewTab(shortcutChildLocation(),pane:target,background:false)}
        case "selectPatternFiles": selectionPattern(remove:false,filesOnly:runtimeConfig.selectionIncludesDirectories)
        case "unselectPatternFiles": selectionPattern(remove:true,filesOnly:true)
        case "invertFiles", "selectFiles", "unselectFiles":
            let pane=activePane; pane.savedSelection=pane.marked
            let selected=Set(pane.marked.map(\.absoluteString)), includeDirectories=action != "unselectFiles" && !runtimeConfig.selectionIncludesDirectories
            let files=Set(pane.entries.filter{includeDirectories || !$0.isDirectory}.map{ $0.url.absoluteString })
            pane.marked=Set(ShortcutContract.selection(current:selected,files:files,operation:action).compactMap(URL.init(string:)))
            pane.table.reloadData();pane.updateFooter()
        case "selectExtension", "unselectExtension":
            guard let current=activePane.currentEntry, !current.isDirectory else { return }
            let pane=activePane; pane.savedSelection=pane.marked
            let ext=(current.name as NSString).pathExtension.lowercased()
            for entry in pane.entries where !entry.isDirectory && (entry.name as NSString).pathExtension.lowercased() == ext {
                if action == "selectExtension" { pane.marked.insert(entry.url) } else { pane.marked.remove(entry.url) }
            }
            pane.table.reloadData();pane.updateFooter()
        default: break
        }
    }
    func shortcutEntryPath(_ entry:FileEntry)->String {
        if activePane.location.localDirectory != nil {return entry.url.path}
        let base=activePane.location.displayPath
        return base+(base.hasSuffix("/") ? "" : "/")+entry.name
    }
    func shortcutChildLocation() -> PaneLocation {
        guard let entry=activePane.currentEntry else { return activePane.location }
        // ZIP entry is handled by the asynchronous archive-opening path before this helper.
        return (try? activePane.location.child(entry)) ?? activePane.location
    }
    @objc func showTabList() {
        let menu=NSMenu(title:"Open tabs")
        for (index,location) in activePane.tabs.enumerated() {
            let item=NSMenuItem(title:location.displayPath,action:#selector(shortcutTabSelected(_:)),keyEquivalent:"")
            item.target=self;item.tag=index;item.state=index == activePane.selectedTab ? .on : .off;menu.addItem(item)
        }
        menu.popUp(positioning:nil,at:.zero,in:activePane.path)
    }
    @objc func shortcutTabSelected(_ item:NSMenuItem) { selectTab(item.tag) }
    func keyboardContextMenu() {
        let menu=NSMenu(title:"File context")
        for (title,tag) in [("View",3),("Edit",4),("Copy",5),("Move",6),("New folder",7),("Move to Trash",8)] {
            let item=NSMenuItem(title:title,action:#selector(menuAction(_:)),keyEquivalent:"");item.target=self;item.tag=tag;menu.addItem(item)
        }
        let properties=NSMenuItem(title:"Properties",action:#selector(fileProperties),keyEquivalent:"");properties.target=self;menu.addItem(properties)
        let row=activePane.table.selectedRow
        let point=row >= 0 ? NSPoint(x:20,y:activePane.table.rect(ofRow:row).maxY) : .zero
        if activePane.brief {
            let cell=activePane.briefGrid.cellRect(max(0,row))
            menu.popUp(positioning:nil,at:NSPoint(x:cell.minX+20,y:cell.maxY),in:activePane.briefGrid)
        } else {menu.popUp(positioning:nil,at:point,in:activePane.table)}
    }
    func copyWithinFolder() {
        guard permitFileAction() else{return}
        guard let directory=activePane.location.localDirectory else { showMessage("Copy in same folder","This command currently supports local folders only.");return }
        let selected=activePane.selectedURLs
        guard selected.count == 1, let source=selected.first else { showMessage("Copy in same folder","Select one item to copy with a new name. Batch rename-copy is not implemented.");return }
        prompt(title:"Copy in same folder",detail:directory.path,value:source.lastPathComponent,action:"Copy") { [weak self] name in
            guard ShortcutContract.validCopyName(name) else { self?.showMessage("Invalid name","Enter one filename without /, a null character, . or ...");return }
            let target=directory.appendingPathComponent(name)
            guard source.standardizedFileURL != target.standardizedFileURL else { self?.showMessage("Choose another name","The copy must have a different name.");return }
            self?.runOperation("Copying",success:"Copied as \(name)") {
                // copyItem refuses an existing destination; never overwrite the original.
                try FileManager.default.copyItem(at:source,to:target)
            }
        }
    }
    func makeTargetFolder() {
        guard !otherPane.isLoading else {return}
        let target=otherPane.location,name=activePane.currentEntry?.name ?? "New Folder"
        prompt(title:"New folder in target",detail:target.displayPath,value:name,action:"Create") { [weak self] name in
            guard ShortcutContract.validCopyName(name) else {self?.showMessage("Invalid name",name);return}
            if case .archive(let session,let path)=target {
                self?.runArchiveMutation("Creating target archive folder",session:session) {try ArchiveMutationService.makeDirectory(session:session,path:path.isEmpty ? name : path+"/"+name)}
            } else {self?.runOperation("Creating target folder",success:"Created \(name)") {try target.makeDirectory(name:name)}}
        }
    }
    @objc func compareFileLists() {
        guard !busy,!left.isLoading,!right.isLoading else {return}
        func items(_ pane:Pane)->[FileListComparison.Item] {pane.entries.enumerated().map{.init(id:$0.offset,name:$0.element.name,directory:$0.element.isDirectory,modified:$0.element.modified)}}
        let result=FileListComparison.compare(items(left),items(right))
        for (pane,indices) in [(left,result.left),(right,result.right)] {
            pane.savedSelection=pane.marked;pane.marked=Set(indices.map{pane.entries[$0].url});pane.table.reloadData();pane.updateFooter()
        }
        status.stringValue="Compared file lists: \(result.left.count) marked left, \(result.right.count) marked right"+(result.unresolved > 0 ? " · \(result.unresolved) ambiguous names/missing timestamps skipped" : "")
    }
    @objc func refreshSource() { guard !busy else { return };if activePane.isTreeMode {activePane.directoryTree.refresh();return}; reloadPane(activePane) }
    func sortSource(_ key: String) {
        guard let column = activePane.table.tableColumns.first(where: { $0.identifier.rawValue == key }) else { return }
        activePane.tableView(activePane.table, didClick: column)
    }
    @objc func briefView() { setBrief(true) }
    @objc func fullView() { setBrief(false) }
    func setBrief(_ value: Bool) { activePane.setBriefMode(value) }
    @objc func quickFilter() {
        prompt(title: "Quick Filter", detail: "Show names containing:", value: activePane.filter, action: "Filter") { [weak self] text in
            self?.activePane.filter = text; self?.refreshSource()
        }
    }
    @objc func showAllFiles() { activePane.filter = "";activePane.fileMask="";activePane.showProgramsOnly=false;activePane.selectedOnly=nil; refreshSource() }
    func cycleTab(_ delta: Int) {
        let p=activePane
        guard !busy, p.tabs.count > 1 else { return }
        selectTab((p.selectedTab + delta + p.tabs.count) % p.tabs.count)
    }
    @objc func closeAllTabs() { guard !busy else { return }; activePane.tabs=[activePane.location];activePane.selectedTab=0;activePane.updateTabs() }
    func openTab(background:Bool) { guard !busy else { return }; openLocationInNewTab(activePane.location,pane:activePane,background:background) }
    func selectionPattern(remove: Bool, filesOnly: Bool? = nil) {
        let pane = activePane
        prompt(title: remove ? "Unselect files" : "Select files", detail: "Wildcard pattern (* and ?).", value: "*.*", action: remove ? "Unselect" : "Select") { value in
            let pattern = value == "*.*" ? "*" : value
            let regex = "^" + pattern.map { $0 == "*" ? ".*" : ($0 == "?" ? "." : NSRegularExpression.escapedPattern(for: String($0))) }.joined() + "$"
            guard let r = try? NSRegularExpression(pattern: regex, options: .caseInsensitive) else { return }
            let p = pane; p.savedSelection = p.marked
            let includeDirectories=filesOnly.map{!$0} ?? (remove || self.runtimeConfig.selectionIncludesDirectories)
            for entry in p.entries where (includeDirectories || !entry.isDirectory) && r.firstMatch(in: entry.name, range: NSRange(entry.name.startIndex..., in: entry.name)) != nil {
                if remove { p.marked.remove(entry.url) } else { p.marked.insert(entry.url) }
            }
            p.table.reloadData(); p.updateFooter()
        }
    }
    @objc func copyFullNames() {
        let paths=activePane.selectedEntries.map{shortcutEntryPath($0)}; guard !paths.isEmpty else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(paths.joined(separator:"\n"),forType:.string)
    }
    @objc func copyFilesToClipboard() {
        guard permitFileAction() else{return}
        let entries=activePane.selectedEntries;guard !entries.isEmpty else{return}
        NSPasteboard.general.clearContents()
        if activePane.location.localDirectory != nil {
            providerClipboard=nil;NSPasteboard.general.writeObjects(entries.map(\.url) as [NSURL])
        } else {
            providerClipboard=(activePane.location,entries)
            NSPasteboard.general.setString(entries.map{shortcutEntryPath($0)}.joined(separator:"\n"),forType:.string)
            providerClipboardChange=NSPasteboard.general.changeCount
        }
        status.stringValue="Copied \(entries.count) file reference(s)"
    }
    @objc func pasteFilesFromClipboard() {
        guard permitFileAction(),!busy else{return}
        if let (source,entries)=providerClipboard,providerClipboardChange==NSPasteboard.general.changeCount {
            runProviderTransfer(entries:entries,source:source,target:activePane.location,move:false);return
        }
        guard let urls=NSPasteboard.general.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL],!urls.isEmpty else{return}
        if let target=activePane.location.localDirectory {
            TransferQueueController.enqueue(sources:urls,destination:target,move:false){[weak self] result in self?.refresh();self?.status.stringValue=result.summary}
        } else {
            let parent=urls[0].deletingLastPathComponent()
            guard urls.allSatisfy({$0.deletingLastPathComponent()==parent}) else{showMessage("Paste files","Copy items from one folder at a time into an archive or FTP pane.");return}
            do {
                let selected=Set(urls),entries=try FileService.list(parent,showHidden:true).filter{selected.contains($0.url)}
                guard entries.count==selected.count else{throw FileServiceError.invalid("Some clipboard files no longer exist.")}
                runProviderTransfer(entries:entries,source:.local(parent),target:activePane.location,move:false)
            }catch{showError(error)}
        }
    }
    @objc func newTextFile() {
        guard permitFileAction() else{return}
        guard let folder=activePane.location.localDirectory else { showMessage("Edit new file","Select a local folder.");return }
        prompt(title: "Edit new file", detail: folder.path, value: "New.txt", action: "Create") { [weak self] name in
            guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else { self?.showMessage("Invalid name", name); return }
            let url = folder.appendingPathComponent(name)
            do { try Data().write(to: url, options: .withoutOverwriting); self?.refreshSource(); try EditorController.open(url: url, editable: true) }
            catch { self?.showError(error) }
        }
    }
    @objc func fileProperties() {
        guard permitFileAction() else{return}
        guard let directory=activePane.location.localDirectory else { showMessage("Properties","Remote/archive properties are not implemented.");return }
        let url = activePane.currentEntry?.url ?? directory
        do {
            let a = try FileManager.default.attributesOfItem(atPath: url.path)
            showMessage("Properties — " + url.lastPathComponent, "\(url.path)\nSize: \(a[.size] ?? 0) bytes\nModified: \(a[.modificationDate] ?? "")\nPermissions: \(String((a[.posixPermissions] as? NSNumber)?.intValue ?? 0, radix: 8))\nOwner: \(a[.ownerAccountName] ?? "")")
        } catch { showError(error) }
    }
    @objc func addHotlist() {
        guard activePane.location.localDirectory != nil else { showMessage("Hotlist","Only local folders can be saved currently.");return }
        var paths=UserDefaults.standard.stringArray(forKey:"directoryHotlist") ?? []
        if !paths.contains(activePane.directory.path) { paths.append(activePane.directory.path); UserDefaults.standard.set(paths,forKey:"directoryHotlist") }
    }
    @objc func removeHotlist() {
        guard activePane.location.localDirectory != nil else { return }
        var paths=UserDefaults.standard.stringArray(forKey:"directoryHotlist") ?? []; paths.removeAll { $0 == activePane.directory.path }; UserDefaults.standard.set(paths,forKey:"directoryHotlist")
    }
    @objc func directoryHistory() {
        let menu = NSMenu(title: "History")
        for url in activePane.backHistory.reversed() {
            let i = NSMenuItem(title: url.displayPath, action: #selector(shortcutHistorySelected(_:)), keyEquivalent: ""); i.target = self; i.representedObject = url; menu.addItem(i)
        }
        menu.popUp(positioning: nil, at: .zero, in: activePane.path)
    }
    @objc func shortcutHistorySelected(_ item:NSMenuItem) { if let location=item.representedObject as? PaneLocation { navigate(location) } }
    @objc func commandHistory() {
        let menu = NSMenu(title: "Command history")
        for command in UserDefaults.standard.stringArray(forKey: "commandHistory") ?? [] {
            let i = NSMenuItem(title: command, action: #selector(recallCommand(_:)), keyEquivalent: ""); i.target = self; menu.addItem(i)
        }
        menu.popUp(positioning: nil, at: .zero, in: commandField)
    }
    @objc func recallCommand(_ item: NSMenuItem) { commandField.stringValue = item.title; focusCommand() }
    func saveSession() {
        guard remember,runtimeConfig.saveOnExit else { return }
        for (name,p) in [("left",left),("right",right)] {
            let locals=p.tabs.enumerated().compactMap { index,location -> (Int,String)? in location.localDirectory.map { (index,$0.path) } }
            UserDefaults.standard.set(locals.map{$0.1},forKey:name+"Tabs")
            UserDefaults.standard.set(locals.firstIndex(where:{$0.0 == p.selectedTab}) ?? 0,forKey:name+"TabIndex")
        }
        UserDefaults.standard.set(showHidden,forKey:"showHidden")
    }
    func restoreSession() {
        guard remember else { return }
        showHidden=runtimeConfig.showHidden
        for (name,p) in [("left",left),("right",right)] {
            if let paths=UserDefaults.standard.stringArray(forKey:name+"Tabs"), !paths.isEmpty {
                p.tabs=paths.map { .local(URL(fileURLWithPath:$0)) }; p.selectedTab=min(max(0,UserDefaults.standard.integer(forKey:name+"TabIndex")),p.tabs.count-1)
                if (try? p.load(p.tabs[p.selectedTab].localDirectory!,showHidden:showHidden)) == nil { p.tabs[p.selectedTab]=p.location }
                p.updateTabs()
            } else if let local=p.location.localDirectory { try? p.load(local,showHidden:showHidden) }
        }
    }
    func handleExtendedKey(_ event: NSEvent, modifiers m: NSEvent.ModifierFlags) -> Bool {
        let key = event.keyCode, text = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if let action = ShortcutContract.action(key:key,modifiers:m) {
            guard !busy else { NSSound.beep(); return true }
            performShortcutContract(action); return true
        }
        if m == [.control] {
            switch key {
            case 122: briefView(); return true
            case 120: fullView(); return true
            case 99: sortSource("name"); return true
            case 118: sortSource("ext"); return true
            case 96: sortSource("date"); return true
            case 97: sortSource("size"); return true
            case 98: unsortedOrder();return true
            case 100: treeView();return true
            case 103: showPrograms();return true
            case 111: customFileMask();return true
            case 109: showAllFiles(); return true
            case 116: parent(); return true
            case 121: openCurrent(); return true
            case 48: cycleTab(1); return true
            case 125: commandHistory(); return true
            case 36,76: if let e = activePane.currentEntry { commandField.stringValue += " '" + e.name.replacingOccurrences(of: "'", with: "'\\''") + "'"; focusCommand() }; return true
            case 69: selectAllFiles(); return true
            case 78: clearSelection(); return true
            default: break
            }
            switch text {
            case "q": toggleQuickView(); return true
            case "f", "n": connectFTP(); return true
            case "l": calculateSpace(); return true
            case "s": quickFilter(); return true
            case "c": copyFilesToClipboard(); return true
            case "v": pasteFilesFromClipboard(); return true
            case "p": commandField.stringValue += activePane.location.displayPath + "/"; focusCommand(); return true
            case "i": navigate(otherPane.location); return true
            case "\\", "<":
                switch activePane.location {
                case .local:navigate(URL(fileURLWithPath:"/"))
                case .archive(let session,_):navigate(.archive(session,path:""))
                case .ftp(let client,_):navigate(.ftp(client,path:"/"))
                };return true
            default: break
            }
        }
        if m == [.control,.shift] {
            if key == 122 {thumbnailView();return true}
            if key == 100 {cycleSeparateTrees();return true}
            if text == "f" {disconnectFTP();return true}
            if key == 48 { cycleTab(-1); return true }
            if text == "t" { openTab(background: true); return true }
            if text == "w" { closeAllTabs(); return true }
            if key == 36 || key == 76, let e = activePane.currentEntry { commandField.stringValue += " '" + shortcutEntryPath(e).replacingOccurrences(of: "'", with: "'\\''") + "'"; focusCommand(); return true }
        }
        if m == [.shift] {
            if key == 118 { newTextFile(); return true }
            if key == 99 { viewFile(editable: false); return true }
            if key == 120 { compareFileLists(); return true }
            if key == 53 { window.miniaturize(nil); return true }
        }
        if m == [.option] {
            if key == 97 { unpackFiles(); return true }
            if key == 100 { commandHistory(); return true }
            if key == 125 { directoryHistory(); return true }
            if key == 36 || key == 76 { fileProperties(); return true }
        }
        if m.isEmpty {
            switch key {
            case 69: selectionPattern(remove: false); return true
            case 78: selectionPattern(remove: true); return true
            case 67: activePane.savedSelection = activePane.marked; invertSelection(); return true
            case 75: activePane.marked = activePane.savedSelection.intersection(Set(activePane.entries.map(\.url))); activePane.table.reloadData(); activePane.updateFooter(); return true
            default: break
            }
        }
        return false
    }
}

#endif
