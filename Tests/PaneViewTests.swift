import AppKit
import Darwin

/// Compile with Main.swift's @main annotation removed in a disposable source copy.
@main struct PaneViewTests {
    static func main() throws {
        _=NSApplication.shared
        func physical(_ url:URL?)->String? {guard let url,let path=realpath(url.path,nil) else{return nil};defer{free(path)};return String(cString:path)}
        var count=0
        func check(_ value:Bool,_ message:String){count += 1;precondition(value,message)}
        let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("pane-view-tests-"+UUID().uuidString)
        try fm.createDirectory(at:root.appendingPathComponent("folder/deeper"),withIntermediateDirectories:true)
        try Data(repeating:65,count:2048).write(to:root.appendingPathComponent("fixture.txt"))
        try fm.createSymbolicLink(at:root.appendingPathComponent("cycle"),withDestinationURL:root)
        defer{try? fm.removeItem(at:root)}
        let pane=Pane(directory:root,title:"IsolatedViewTests")
        try pane.load(root,showHidden:false)
        let selected=pane.entries.firstIndex{$0.name=="fixture.txt"}!+1
        pane.table.selectRowIndexes(IndexSet(integer:selected),byExtendingSelection:false)
        var config=CommanderConfiguration();config.sizeFormat = .dynamic;config.thumbnailSize=192;config.visibleColumns=["name","size"];config.columnWidths["size"]=125;config.rowHeight=29;config.iconMode = .none
        pane.applyConfiguration(config)
        check(pane.currentEntry?.name=="fixture.txt","Configuration preserves selected file across resort")
        check(pane.table.tableColumns.first{$0.identifier.rawValue=="ext"}!.isHidden,"Column visibility applied")
        check(pane.table.tableColumns.first{$0.identifier.rawValue=="size"}!.width==125,"Configured column width")
        let sizeColumn=pane.table.tableColumns.first{$0.identifier.rawValue=="size"}!
        let cell=pane.tableView(pane.table,viewFor:sizeColumn,row:pane.table.selectedRow) as! NSTextField
        check(cell.stringValue==config.sizeString(2048),"Visible size cell uses configured units")
        check(pane.footer.stringValue.contains(config.sizeString(2048)),"Footer selected total uses configured units")
        config.footerSizeFormat = .bytes;pane.applyConfiguration(config)
        check(pane.footer.stringValue.contains(config.footerSizeString(2048)),"Independent footer unit setting applied immediately")
        config.ignoreListEnabled=true;config.ignorePatterns="*.txt";pane.applyConfiguration(config)
        check(!pane.entries.contains{$0.name=="fixture.txt"},"Ignore mask immediately filters displayed files")
        config.ignorePatterns="folder";pane.applyConfiguration(config)
        check(!pane.entries.contains{$0.name=="folder"},"Ignore mask applies to directories too")
        config.ignoreListEnabled=false;config.showStatusBar=false;pane.applyConfiguration(config)
        check(pane.entries.contains{$0.name=="fixture.txt"} && pane.entries.contains{$0.name=="folder"},"Disabling ignore restores retained listing")
        check(pane.footer.isHidden,"Pane status layout setting applied")
        config.showStatusBar=true;config.footerSizeFormat=nil;pane.applyConfiguration(config)
        pane.table.selectRowIndexes(IndexSet(integer:pane.entries.firstIndex{$0.name=="fixture.txt"}!+1),byExtendingSelection:false)
        check(pane.setThumbnailMode() && pane.viewMode == .thumbnails,"Actual thumbnail mode")
        check(pane.thumbnailGrid.pixels==192,"Thumbnail size configured")
        check(pane.currentEntry?.name=="fixture.txt","Thumbnail transition preserves shared selection")
        pane.setBriefMode(true);check(pane.viewMode == .brief,"Brief transition")
        pane.setBriefMode(false);check(pane.viewMode == .full,"Full transition")
        var opened:PaneLocation?
        pane.onTreeOpen={opened=$0};pane.setTreeMode(root:.local(root))
        let deadline=Date().addingTimeInterval(5)
        while pane.directoryTree.rootIsLoading && Date()<deadline {RunLoop.current.run(until:Date().addingTimeInterval(0.01))}
        check(!pane.directoryTree.rootIsLoading,"Tree scan completed asynchronously")
        check(pane.directoryTree.visibleFolderNames.contains("folder"),"Actual root child directory listed")
        check(!pane.directoryTree.visibleFolderNames.contains("fixture.txt"),"Tree excludes files")
        check(!pane.directoryTree.visibleFolderNames.contains("cycle"),"Tree excludes symlink cycle")
        check(pane.path.isHidden,"Tree does not expose preserved hidden-list path")
        let outline=pane.directoryTree.responder as! NSOutlineView
        let folderRow=pane.directoryTree.visibleFolderNames.firstIndex(of:"folder")!
        outline.selectRowIndexes(IndexSet(integer:folderRow),byExtendingSelection:false)
        let enter=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:36)!
        outline.keyDown(with:enter)
        check(opened?.localDirectory?.lastPathComponent=="folder","Return emits the selected tree location, not hidden file selection")
        pane.setBriefMode(false);check(!pane.path.isHidden,"Leaving tree restores configured path field")
        var profile=FTPProfile();profile.host="127.0.0.1"
        pane.location = .ftp(try FTPClient(profile:profile,password:""),path:"/")
        check(!pane.setThumbnailMode() && pane.viewMode == .full,"Virtual provider rejected without reading synthetic URLs")
        let controller=CommanderController(initial:root,remember:false)
        controller.separateTrees.setState(1)
        check(!controller.separateTrees.leftView.isHidden && controller.separateTrees.rightView.isHidden,"One separate tree visible")
        let revealDeadline=Date().addingTimeInterval(8)
        while controller.separateTrees.leftView.selectedLocation?.localDirectory?.path != physical(controller.activePane.location.localDirectory) && Date()<revealDeadline {RunLoop.current.run(until:Date().addingTimeInterval(0.01))}
        if controller.separateTrees.leftView.selectedLocation?.localDirectory?.path != physical(controller.activePane.location.localDirectory) {
            FileHandle.standardError.write(Data("Reveal mismatch actual=\(String(describing:controller.separateTrees.leftView.selectedLocation?.displayPath)) expected=\(controller.activePane.location.displayPath)\n".utf8))
        }
        check(controller.separateTrees.leftView.selectedLocation?.localDirectory?.path == physical(controller.activePane.location.localDirectory),"Single tree lazily reveals active directory through canonical volume path")
        controller.navigate(.local(root.appendingPathComponent("folder")),pane:controller.right,focus:false)
        controller.activate(1,focus:false);controller.separateTrees.refreshRoots()
        let activeDeadline=Date().addingTimeInterval(8)
        while controller.separateTrees.leftView.selectedLocation?.localDirectory?.path != physical(controller.right.location.localDirectory) && Date()<activeDeadline {RunLoop.current.run(until:Date().addingTimeInterval(0.01))}
        check(controller.separateTrees.leftView.selectedLocation?.localDirectory?.path == physical(controller.right.location.localDirectory),"One tree follows the newly active pane")
        controller.separateTrees.setState(2)
        check(!controller.separateTrees.leftView.isHidden && !controller.separateTrees.rightView.isHidden,"Two separate trees visible")
        controller.separateTrees.setState(0)
        check(controller.separateTrees.leftView.isHidden && controller.separateTrees.rightView.isHidden,"Off restores only file panes")
        check(physical(controller.left.location.localDirectory)==physical(root) && physical(controller.right.location.localDirectory)==physical(root.appendingPathComponent("folder")),"Tree state changes preserve file locations")
        pane.directoryTree.setRoot(.local(root.appendingPathComponent("folder")),showHidden:false)
        pane.directoryTree.setRoot(.local(root),showHidden:false)
        let raceDeadline=Date().addingTimeInterval(5)
        while pane.directoryTree.rootIsLoading && Date()<raceDeadline {RunLoop.current.run(until:Date().addingTimeInterval(0.01))}
        check(pane.directoryTree.visibleFolderNames.contains("folder") && !pane.directoryTree.visibleFolderNames.contains("deeper"),"Superseded root load cannot overwrite newer tree")
        print("Pane views: \(count) checks passed")
    }
}
