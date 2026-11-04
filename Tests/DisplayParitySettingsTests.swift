import AppKit
@main struct DisplayParitySettingsTests {
    static func main()throws {
        let app=NSApplication.shared;app.setActivationPolicy(.prohibited)
        var checks=0
        func check(_ value:Bool,_ message:String){checks+=1;precondition(value,message)}
        var config=CommanderConfiguration()
        check(config.directoryDisplayName("Photos")=="[Photos]","Preserved default brackets")
        config.directoryBrackets=false;check(config.directoryDisplayName("Photos")=="Photos","Unadorned directory")
        config.directoryTrailingSlash=true;check(config.directoryDisplayName("Photos")=="Photos/","Native slash suffix")
        config.directoryBrackets=true;check(config.directoryDisplayName("Photos")=="[Photos]/","Independent combined decoration")
        check(config.directoryCountSuffix(total:3,selected:1).isEmpty,"Default footer unaffected")
        config.showDirectoryCount=true;check(config.directoryCountSuffix(total:3,selected:1).contains("1 / 3 dirs"),"Directory totals")
        check(CommanderSortMethod.characterCode.compare("z","é") == .orderedAscending,"Uppercase character code")
        check(CommanderSortMethod.characterCode.compare("file10","file2") == .orderedAscending,"Lexical digit ordering")
        check(CommanderSortMethod.naturalCharacterCode.compare("file2","file10") == .orderedAscending,"Natural numeric ordering")
        check(CommanderSortMethod.naturalCharacterCode.compare("file0002","FILE2") == .orderedSame,"Case folding and leading zeros")
        check(CommanderSortMethod.naturalCharacterCode.compare("x99999999999999999999999999","x100000000000000000000000000") == .orderedAscending,"No integer overflow")
        check(CommanderSortMethod.naturalCharacterCode.compare("a0b2","a000b10") == .orderedAscending,"Multiple numeric runs")
        check(CommanderSortMethod.naturalAlphabetical.compare("file2","file10") == .orderedAscending,"Natural locale order")
        check(CommanderSortMethod.alphabetical.compare("b","A") == .orderedDescending,"Alphabetical case-insensitive")
        check(CommanderSortMethod.naturalAlphabetical.compare("a","A",caseSensitive:true)=="a".compare("A"),"Explicit case-sensitive override")
        let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("display-parity-"+UUID().uuidString)
        try fm.createDirectory(at:root,withIntermediateDirectories:false);defer{try? fm.removeItem(at:root)}
        for name in ["Folder2","Folder10"]{try fm.createDirectory(at:root.appendingPathComponent(name),withIntermediateDirectories:false)}
        for name in ["file2.txt","file10.txt",String(repeating:"long",count:25)+".txt"]{try Data("data".utf8).write(to:root.appendingPathComponent(name))}
        let controller=CommanderController(initial:root,remember:false),pane=controller.left
        config=controller.runtimeConfig;config.sortMethod = .characterCode;config.directoriesAlwaysByName=true;config.showDirectoryCount=true;config.directoryBrackets=false;config.directoryTrailingSlash=true
        controller.applyConfiguration(config);pane.sortColumn="name";pane.ascending=false;pane.sortEntries()
        check(Array(pane.entries.prefix(2).map(\.name))==["Folder10","Folder2"],"Directory ascending independent of descending files")
        config.sortMethod = .naturalCharacterCode;controller.applyConfiguration(config)
        check(Array(pane.entries.prefix(2).map(\.name))==["Folder2","Folder10"],"Changing sort method re-sorts immediately")
        var tabView=pane.captureManualTabView();tabView.secondarySortColumns=["size"];pane.restoreManualTabView(tabView,configuration:config);pane.sortEntries()
        check(Array(pane.entries.prefix(2).map(\.name))==["Folder2","Folder10"],"Secondary sort honors directory policy")
        tabView.secondarySortColumns=[];pane.restoreManualTabView(tabView,configuration:config);config.directoriesAlwaysByName=false;controller.applyConfiguration(config)
        check(Array(pane.entries.prefix(2).map(\.name))==["Folder10","Folder2"],"Directory follows reversed file sort when disabled")
        let index=pane.entries.firstIndex{$0.isDirectory}!,column=pane.table.tableColumns.first{$0.identifier.rawValue=="name"}!
        let cell=pane.tableView(pane.table,viewFor:column,row:index+1)
        let label=(cell as? NSTableCellView)?.textField ?? (cell as? NSTextField)
        check(label?.stringValue==pane.entries[index].name+"/","Full view uses directory display settings")
        pane.table.selectRowIndexes(IndexSet(integer:index+1),byExtendingSelection:false);pane.updateFooter()
        check(pane.footer.stringValue.contains("1 / 2 dirs"),"Actual footer counts visible and selected dirs")
        config.briefColumnWidthLimit=120;controller.applyConfiguration(config);pane.setBriefMode(true);pane.view.layoutSubtreeIfNeeded();pane.briefGrid.updateGeometry()
        check(pane.briefGrid.columnWidth<=120,"Brief explicit cap applied")
        config.briefColumnWidthLimit=0;controller.applyConfiguration(config);pane.briefGrid.updateGeometry()
        check(pane.briefGrid.columnWidth>=120,"Unlimited Brief measures long filenames")
        check(config.normalized().briefColumnWidthLimit==0,"Unlimited value retained")
        config.directoriesFirst=false;config.directoriesAlwaysByName=true;controller.applyConfiguration(config);pane.sortColumn="name";pane.ascending=false;pane.sortEntries()
        let mixed=pane.entries.map(\.name),expected=mixed.sorted{config.compareDisplayNames($0,$1) == .orderedDescending}
        check(mixed==expected,"Mixed directory/file listing uses one consistent comparator")
        let encoded=try JSONEncoder().encode(config),decoded=try JSONDecoder().decode(CommanderConfiguration.self,from:encoded)
        check(decoded.sortMethod==config.sortMethod && decoded.directoryTrailingSlash && decoded.showDirectoryCount,"Configuration roundtrip preserves new settings")
        print("PASS: \(checks) display parity assertions")
    }
}
