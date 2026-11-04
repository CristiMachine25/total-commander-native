import AppKit

struct ReferenceMenuLabel: Equatable {
    let raw: String
    let title: String
    let mnemonic: Character?
    let shortcut: String?
    init(_ raw: String) {
        self.raw=raw
        let decoded=raw.replacingOccurrences(of:"\\t",with:"\t"),parts=decoded.split(separator:"\t",maxSplits:1,omittingEmptySubsequences:false)
        let characters=Array(String(parts[0]));var title="",mnemonic:Character?,index=0
        while index<characters.count {
            if characters[index]=="&" {
                if index+1<characters.count {
                    if characters[index+1]=="&" {title.append("&");index += 2;continue}
                    if mnemonic==nil {mnemonic=characters[index+1]}
                    index += 1;continue
                }
            }
            title.append(characters[index]);index += 1
        }
        self.title=title;self.mnemonic=mnemonic;self.shortcut=parts.count==2 ? String(parts[1]) : nil
    }
    var displayedTitle: String {title + (shortcut.map{"\t"+$0} ?? "")}
}

indirect enum ReferenceMenuNode: Equatable {
    case popup(ReferenceMenuLabel,[ReferenceMenuNode])
    case command(ReferenceMenuLabel,token:String,id:Int?)
    case separator
    case startMenu
    case helpBreak
}

struct ReferenceCommandDefinition: Equatable {
    let symbol: String
    let id: Int
    let description: String
}
struct ReferenceMenuCatalog {
    let roots: [ReferenceMenuNode]
    let commandsBySymbol: [String:ReferenceCommandDefinition]
    let aliasesByID: [Int:[String]]
    enum ParseError: LocalizedError {
        case invalid(Int,String)
        var errorDescription:String? {if case .invalid(let line,let message)=self{return "Reference menu line \(line): \(message)"};return nil}
    }
    init(menuText: String, commandsText: String) throws {
        var commands:[String:ReferenceCommandDefinition]=[:],aliases:[Int:[String]]=[:]
        for (number,line) in commandsText.components(separatedBy:.newlines).enumerated() {
            let value=line.trimmingCharacters(in:.whitespacesAndNewlines)
            if value.isEmpty || value.hasPrefix(";") || value.hasPrefix("["){continue}
            guard let equals=value.firstIndex(of:"=") else{continue}
            let symbol=String(value[..<equals]).trimmingCharacters(in:.whitespaces)
            let tail=value[value.index(after:equals)...].split(separator:";",maxSplits:1,omittingEmptySubsequences:false)
            guard let id=Int(tail[0].trimmingCharacters(in:.whitespaces)) else{throw ParseError.invalid(number+1,"Non-numeric command ID.")}
            let definition=ReferenceCommandDefinition(symbol:symbol,id:id,description:tail.count>1 ? String(tail[1]) : "")
            let key=symbol.lowercased()
            if let prior=commands[key],prior.id != id{throw ParseError.invalid(number+1,"Conflicting command alias \(symbol).")}
            commands[key]=definition
            if !(aliases[id] ?? []).contains(symbol){aliases[id,default:[]].append(symbol)}
        }
        self.commandsBySymbol=commands;self.aliasesByID=aliases
        let lines=menuText.components(separatedBy:.newlines);var position=0
        func quoted(_ value:String,line:Int)throws->(String,String) {
            guard value.first=="\"" else{throw ParseError.invalid(line,"Expected quoted label.")}
            var label="",cursor=value.index(after:value.startIndex)
            while cursor<value.endIndex {
                let character=value[cursor]
                if character=="\"" {return(label,String(value[value.index(after:cursor)...]).trimmingCharacters(in:.whitespaces))}
                if character=="\\" {
                    let next=value.index(after:cursor)
                    if next<value.endIndex,value[next]=="\"" {label.append("\"");cursor=value.index(after:next);continue}
                }
                label.append(character);cursor=value.index(after:cursor)
            }
            throw ParseError.invalid(line,"Unterminated quoted label.")
        }
        func parse(nested:Bool)throws->[ReferenceMenuNode] {
            var result:[ReferenceMenuNode]=[]
            while position<lines.count {
                let number=position+1,line=lines[position].trimmingCharacters(in:.whitespacesAndNewlines);position += 1
                if line.isEmpty || line.hasPrefix(";"){continue}
                if line=="END_POPUP" {guard nested else{throw ParseError.invalid(number,"Unexpected END_POPUP.")};return result}
                if line.hasPrefix("POPUP ") {
                    let(label,tail)=try quoted(String(line.dropFirst(6)).trimmingCharacters(in:.whitespaces),line:number)
                    guard tail.isEmpty else{throw ParseError.invalid(number,"Unexpected text after popup label.")}
                    result.append(.popup(ReferenceMenuLabel(label),try parse(nested:true)));continue
                }
                if line=="MENUITEM SEPARATOR"{result.append(.separator);continue}
                if line.hasPrefix("MENUITEM ") {
                    let(label,tail)=try quoted(String(line.dropFirst(9)).trimmingCharacters(in:.whitespaces),line:number)
                    guard tail.first=="," else{throw ParseError.invalid(number,"Missing command separator.")}
                    let token=tail.dropFirst().trimmingCharacters(in:.whitespaces)
                    guard !token.isEmpty else{throw ParseError.invalid(number,"Missing command.")}
                    result.append(.command(ReferenceMenuLabel(label),token:token,id:Int(token) ?? commands[token.lowercased()]?.id));continue
                }
                if line=="STARTMENU"{result.append(.startMenu);continue}
                if line=="HELP_BREAK"{result.append(.helpBreak);continue}
                throw ParseError.invalid(number,"Unsupported directive: \(line)")
            }
            if nested{throw ParseError.invalid(position,"Missing END_POPUP.")};return result
        }
        self.roots=try parse(nested:false)
    }
    func id(for symbol:String)->Int? {Int(symbol) ?? commandsBySymbol[symbol.lowercased()]?.id}
    func popup(_ title:String)->[ReferenceMenuNode]? {
        let wanted=ReferenceMenuLabel(title).title.lowercased()
        for root in roots {if case .popup(let label,let children)=root,label.title.lowercased()==wanted{return children}}
        return nil
    }
    var topLevelTitles:[String] {roots.compactMap{if case .popup(let label,_)=$0{return label.title};if case .startMenu=$0{return "Start"};return nil}}
    private static let cacheLock=NSLock()
    private static var bundleCache:[String:ReferenceMenuCatalog]=[:]
    static func load(bundle:Bundle = .main)throws->ReferenceMenuCatalog? {
        guard let menu=bundle.url(forResource:"WCMD_ENG",withExtension:"MNU"),let commands=bundle.url(forResource:"TOTALCMD",withExtension:"INC") else{return nil}
        // Shipped bundle resources are immutable for the lifetime of this process.
        let key=menu.path+"|"+commands.path
        cacheLock.lock();let existing=bundleCache[key];cacheLock.unlock()
        if let existing{return existing}
        let catalog=try ReferenceMenuCatalog(menuText:String(contentsOf:menu,encoding:.windowsCP1252),commandsText:String(contentsOf:commands,encoding:.windowsCP1252))
        cacheLock.lock();if bundleCache.count>=8{bundleCache.removeAll()};bundleCache[key]=catalog;cacheLock.unlock()
        return catalog
    }
}

/// Capabilities are explicit. A symbolic alias is enabled only when its resolved
/// original ID has a genuine native route; unknown IDs remain visible but disabled.
enum ReferenceCommandRouting {
    static let supportedIDs:Set<Int> = [
        2950,2951,2952,270,333,483,2920,2939,2940,2947,8500,8501,8502,8503,8504,8505,8506,8507,8508,8509,271,272,273,274,275,276,277,278,279,3200,3201,3202,269,301,302,303,304,305,311,312,313,314,321,322,323,324,325,330,493,552,2023,2031,2032,2036,2037,
        498,571,560,561,490,501,503,508,509,510,518,521,522,523,524,525,526,527,529,530,531,532,533,
        540,550,551,553,564,565,570,580,581,620,640,690,2017,2018,2020,2022,2121,2400,3001,24340
    ]
    static let localOnlyIDs:Set<Int> = [560,561,501,503,508,509,510,564,565,2020,2022,2400]
    static let selectedIDs:Set<Int> = [560,561,503,508,509,510,518,527,564,565,2017,2018,2022,2400]
    static func isSupported(_ id:Int?)->Bool {id.map{supportedIDs.contains($0) || (271...299).contains($0) || (8500...8749).contains($0)} ?? false}
    static func unsupportedReason(_ id:Int?)->String {"Not implemented in the native macOS app" + (id.map{" (original command \($0))."} ?? ".")}
}

#if !REFERENCE_MENU_TESTS
extension CommanderController: NSMenuDelegate {
    func menuWillOpen(_ menu:NSMenu) {
        for item in menu.items where item.representedObject is String {
            item.isEnabled = referenceCommandEnabled(item.tag)
            if item.tag == 301 {item.state = activePane.brief ? .on : .off}
            if item.tag == 302 {item.state = activePane.viewMode == .full && activePane.currentCustomColumnSet == nil ? .on : .off}
            if item.tag == 303 {item.state = activePane.isTreeMode ? .on : .off}
            if item.tag == 269 {item.state = activePane.viewMode == .thumbnails ? .on : .off}
            if item.tag == 305 {item.state = runtimeConfig.verticalArrangement ? .on : .off}
            if (3200...3202).contains(item.tag) {item.state = separateTrees.state==item.tag-3200 ? .on : .off}
            if item.tag == 553 {item.state = showHidden ? .on : .off}
        }
    }
    func referenceMenu(title:String)->NSMenu? {
        guard let catalog=try? ReferenceMenuCatalog.load() else{return nil}
        if title.caseInsensitiveCompare("Start") == .orderedSame,catalog.roots.contains(.startMenu) {let menu=NSMenu(title:"Start");menu.autoenablesItems=false;return menu}
        guard let nodes=catalog.popup(title) else{return nil}
        func build(_ nodes:[ReferenceMenuNode],title:String)->NSMenu {
            let menu=NSMenu(title:title);menu.autoenablesItems=false;menu.delegate=self
            for node in nodes {
                switch node {
                case .separator:menu.addItem(.separator())
                case .popup(let label,let children):
                    let item=NSMenuItem(title:label.displayedTitle,action:nil,keyEquivalent:"");item.submenu=build(children,title:label.title);menu.addItem(item)
                case .command(let label,let token,let id):
                    let supported=ReferenceCommandRouting.isSupported(id)
                    let item=NSMenuItem(title:label.displayedTitle,action:supported ? #selector(referenceCommand(_:)) : nil,keyEquivalent:"")
                    item.target=self;item.tag=id ?? -1;item.representedObject=token
                    item.isEnabled=supported && referenceCommandEnabled(id!)
                    item.toolTip=supported ? "Original command: \(token) (\(id!))" : ReferenceCommandRouting.unsupportedReason(id)
                    if let id {
                        if id==301{item.state=activePane.brief ? .on : .off}
                        if id==302{item.state=activePane.viewMode == .full && activePane.currentCustomColumnSet == nil ? .on : .off}
                        if id==303{item.state=activePane.isTreeMode ? .on : .off}
                        if id==269{item.state=activePane.viewMode == .thumbnails ? .on : .off}
                        if id==305{item.state=runtimeConfig.verticalArrangement ? .on : .off}
                        if (3200...3202).contains(id){item.state=separateTrees.state==id-3200 ? .on : .off}
                        if id==553{item.state=showHidden ? .on : .off}
                    }
                    menu.addItem(item)
                case .startMenu,.helpBreak:break
                }
            }
            return menu
        }
        return build(nodes,title:title)
    }
    func referenceCommandEnabled(_ id:Int)->Bool {
        guard ReferenceCommandRouting.isSupported(id),!busy,!activePane.isLoading else{return false}
        if (271...299).contains(id),!runtimeConfig.customColumnSets.indices.contains(id-271) {return false}
        if (8501...8749).contains(id),!runtimeConfig.viewModes.filter({$0.id != "default"}).indices.contains(id-8501) {return false}
        let displayModeCommand=(271...299).contains(id) || (8500...8749).contains(id)
        if (activePane.isTreeMode || separateTrees.hasFocus) && !displayModeCommand && ![2950,2951,2952,270,333,483,2920,2939,2940,2947,8500,3200,3201,3202,269,301,302,303,305,490,493,498,540,580,581,620,640,690,24340].contains(id){return false}
        if ReferenceCommandRouting.localOnlyIDs.contains(id),activePane.location.localDirectory==nil{return false}
        if id==2020,otherPane.location.localDirectory==nil{return false}
        if ReferenceCommandRouting.selectedIDs.contains(id),activePane.selectedEntries.isEmpty{return false}
        if [552,553].contains(id),case .ftp = activePane.location {} else if [552,553].contains(id){return false}
        if id==269,activePane.location.localDirectory==nil{return false}
        return true
    }
    @objc func referenceCommand(_ sender:NSMenuItem) {_ = routeReferenceCommand(sender.tag)}
    @discardableResult func routeReferenceCommand(_ id:Int)->Bool {
        guard referenceCommandEnabled(id) else{return false}
        if routeDisplaySettingsCommand(id) {return true}
        switch id {
        case 2950:toggleCommanderAppearance()
        case 2951:runtimeConfig.appearanceMode = .dark;applyConfiguration(runtimeConfig);if remember {try? runtimeConfig.save()}
        case 2952:runtimeConfig.appearanceMode = .light;applyConfiguration(runtimeConfig);if remember {try? runtimeConfig.save()}
        case 301:briefView()
        case 302:fullView()
        case 3200,3201,3202:separateTrees.setState(id-3200)
        case 303:treeView()
        case 269:thumbnailView()
        case 305:verticalArrangement()
        case 311:showPrograms()
        case 313:lastFileMask()
        case 314:customFileMask()
        case 325:unsortedOrder()
        case 493:saveWindowPosition()
        case 552:disconnectFTP()
        case 2023:showSelectedOnly()
        case 2031:saveSelectionFile()
        case 2032:loadSelectionFile()
        case 2036:copyDetails(withPaths:false)
        case 2037:copyDetails(withPaths:true)
        case 304:toggleQuickView()
        case 312:showAllFiles()
        case 321:referenceSort("name")
        case 322:referenceSort("ext")
        case 323:referenceSort("size")
        case 324:referenceSort("date")
        case 330:
            activePane.ascending.toggle();activePane.sortEntries();activePane.table.reloadData();activePane.updateFooter()
        case 490:configuration()
        case 498:configureButtonBar()
        case 571:forwardFolder()
        case 501:searchFiles()
        case 503:calculateSpace()
        case 508:packFiles()
        case 509:unpackFiles()
        case 510:fileProperties()
        case 518:
            let entries=activePane.selectedEntries,source=activePane.location
            guard let tool=Bundle.main.url(forResource:"7zz",withExtension:nil) else{return false}
            runOperation("Testing archives",success:"Selected ZIP archives passed integrity checks") {
                for entry in entries {
                    guard !entry.isDirectory else{throw ArchiveBrowserError.message("Choose ZIP files to test.")}
                    let lease=try source.readableMaterialization(entry)
                    try ArchiveBrowserSession(archive:lease.url,tool:tool).testIntegrity()
                }
            }
        case 521:selectionPattern(remove:false)
        case 522:selectionPattern(remove:true)
        case 523:selectAllFiles()
        case 524:clearSelection()
        case 525:invertSelection()
        case 526:showPlaces()
        case 527:performShortcutContract("selectExtension")
        case 529:activePane.marked=activePane.savedSelection.intersection(Set(activePane.entries.map(\.url)));activePane.table.reloadData();activePane.updateFooter()
        case 530:activePane.savedSelection=activePane.marked
        case 531:swap()
        case 532:navigate(activePane.location,pane:otherPane)
        case 533:compareFileLists()
        case 540:refreshSource()
        case 550,551:connectFTP()
        case 553:let item=NSMenuItem();hidden(item)
        case 560:splitFile()
        case 561:combineFiles()
        case 564:createChecksums()
        case 565:verifyChecksums()
        case 570:backFolder()
        case 580:saveConfiguration()
        case 581:configurationFile()
        case 620:help()
        case 640:NSWorkspace.shared.open(URL(string:"https://www.ghisler.com/")!)
        case 690:NSApp.orderFrontStandardAboutPanel(nil)
        case 2017:NSPasteboard.general.clearContents();NSPasteboard.general.setString(activePane.selectedEntries.map(\.name).joined(separator:"\n"),forType:.string)
        case 2018:copyFullNames()
        case 2020:synchronizeDirectories()
        case 2022:compareFiles()
        case 2121:navigate(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop"))
        case 2400:multiRename()
        case 3001:newTab()
        case 24340:exitApp()
        default:return false
        }
        return true
    }
    private func referenceSort(_ key:String) {
        if activePane.sortColumn != key {sortSource(key)}
    }
}
#endif
