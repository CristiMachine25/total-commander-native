import AppKit
extension NativeCommander {
    static func configurationSmokeTest()throws {
        let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("configuration-ui-"+UUID().uuidString)
        try fm.createDirectory(at:root,withIntermediateDirectories:false);defer{try? fm.removeItem(at:root)}
        try fm.createDirectory(at:root.appendingPathComponent("Folder"),withIntermediateDirectories:false)
        try Data(repeating:65,count:1_572_864).write(to:root.appendingPathComponent("sample.txt"))
        try Data([1,2,3]).write(to:root.appendingPathComponent("other.bin"))
        let persistedConfiguration=UserDefaults.standard.data(forKey:"commander.configuration.v1")
        let c=CommanderController(initial:root,remember:false)
        let persistedFrame=UserDefaults.standard.object(forKey:"savedWindowFrame") as? String
        let persistedDivider=UserDefaults.standard.object(forKey:"savedDividerRatio") as? NSNumber
        c.hidden(NSMenuItem());c.hidden(NSMenuItem())
        c.verticalArrangement();c.verticalArrangement();c.saveConfiguration();c.saveWindowPosition()
        precondition(UserDefaults.standard.object(forKey:"savedWindowFrame") as? String == persistedFrame)
        precondition(UserDefaults.standard.object(forKey:"savedDividerRatio") as? NSNumber == persistedDivider)
        precondition(UserDefaults.standard.data(forKey:"commander.configuration.v1")==persistedConfiguration,"Nonpersistent hidden-file toggles changed saved settings")
        var configuration=CommanderConfiguration();configuration.sizeFormat = .megabytes;configuration.visibleColumns=["name","size"];configuration.columnWidths["size"]=140;configuration.rowHeight=29
        configuration.showButtonBar=false;configuration.showCommandLine=false;configuration.verticalArrangement=true;configuration.thumbnailSize=192;configuration.selectionIncludesDirectories=false
        c.applyConfiguration(configuration)
        precondition(c.buttonBar.isHidden && c.commandField.isHidden && !c.splitView.isVertical)
        precondition(c.left.table.rowHeight==29 && c.left.table.tableColumns.first{$0.identifier.rawValue=="ext"}!.isHidden)
        let row=c.left.entries.firstIndex{$0.name=="sample.txt"}!+1,column=c.left.table.tableColumns.first{$0.identifier.rawValue=="size"}!
        let cell=c.left.tableView(c.left.table,viewFor:column,row:row) as! NSTextField
        precondition(cell.stringValue==configuration.sizeString(1_572_864),"Size setting did not reach visible cell")
        c.selectAllFiles();precondition(c.left.marked.count==2 && !c.left.marked.contains(root.appendingPathComponent("Folder")))
        c.left.table.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)
        let before=c.left.currentEntry?.url
        c.thumbnailView();precondition(c.left.currentEntry?.url==before && c.left.viewMode == .thumbnails)
        c.fullView();precondition(c.left.currentEntry?.url==before)
        c.left.setTreeMode(root:.local(root))
        let deadline=Date().addingTimeInterval(5)
        while c.left.directoryTree.rootIsLoading && Date()<deadline {_=RunLoop.current.run(mode:.default,before:Date().addingTimeInterval(0.01))}
        precondition(c.left.directoryTree.visibleFolderNames.contains("Folder"))
        precondition(!c.left.directoryTree.visibleFolderNames.contains("sample.txt"))
        c.fullView();configuration=CommanderConfiguration();c.applyConfiguration(configuration)
        precondition(!c.buttonBar.isHidden && !c.commandField.isHidden && c.splitView.isVertical)
        c.left.fileMask="*.txt";c.refreshSource();precondition(c.left.entries.map(\.name).sorted()==["Folder","sample.txt"])
        c.showAllFiles();precondition(c.left.entries.count==3)
        configuration.quickSearchMode = .letters;c.applyConfiguration(configuration)
        let key=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:c.window.windowNumber,context:nil,characters:"s",charactersIgnoringModifiers:"s",isARepeat:false,keyCode:1)!
        precondition(c.handleKey(key) && c.left.currentEntry?.name=="sample.txt" && c.commandField.stringValue.isEmpty)
        c.quickSearchText="";configuration.quickSearchMode = .disabled;c.applyConfiguration(configuration)
        c.separateTrees.setState(1);precondition(!c.separateTrees.leftView.isHidden && c.separateTrees.rightView.isHidden)
        c.separateTrees.setState(2);precondition(!c.separateTrees.rightView.isHidden)
        c.separateTrees.setState(0);precondition(c.separateTrees.leftView.isHidden && c.separateTrees.rightView.isHidden)
        let fileEditor=try ConfigurationFilesController(c)
        var edited=c.runtimeConfig;edited.sizeFormat = .gigabytes
        fileEditor.textView.string=String(decoding:try ConfigurationFiles.exportNative(edited),as:UTF8.self)
        fileEditor.apply();precondition(c.runtimeConfig.sizeFormat == .gigabytes)
        precondition(UserDefaults.standard.data(forKey:CommanderConfiguration.defaultsKey)==persistedConfiguration)
        fileEditor.textView.string="{invalid}"
        do {_=try fileEditor.parsedConfiguration();preconditionFailure("Invalid JSON accepted")}catch{}
        fileEditor.close()
        print("Configuration UI integration passed: size cells, columns, row heights, layout, selection, thumbnails, tree, masks")
    }
}
