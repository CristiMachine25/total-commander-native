import AppKit

@main struct ContextMenuTests {
    static func main() throws {
        _=NSApplication.shared
        var count=0
        func check(_ value:Bool,_ message:String){count += 1;precondition(value,message)}
        let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("context-menu-"+UUID().uuidString)
        try fm.createDirectory(at:root.appendingPathComponent("folder"),withIntermediateDirectories:true)
        for name in ["a.txt","b.txt","c.txt"]{try Data(name.utf8).write(to:root.appendingPathComponent(name))}
        defer{try? fm.removeItem(at:root)}
        let c=CommanderController(initial:root,remember:false);c.installFileContextMenus()
        let p=c.right
        func row(_ name:String)->Int {p.entries.firstIndex{$0.name==name}!+1}
        let a=row("a.txt"),b=row("b.txt"),d=row("c.txt"),folder=row("folder")
        p.table.selectRowIndexes(IndexSet(integer:a),byExtendingSelection:false)
        let menu=p.contextMenu(forRow:b)!
        check(c.activePane === p,"Context activates clicked pane")
        check(p.currentEntry?.name=="b.txt","Unselected context target replaces cursor")
        check(menu.item(withTitle:"View")?.isEnabled==true,"File offers viewer")
        check(menu.item(withTitle:"Move to Trash…")?.isEnabled==true,"Local file offers Trash")
        p.table.selectRowIndexes(IndexSet([a,b]),byExtendingSelection:false)
        let multi=p.contextMenu(forRow:b)!
        check(p.table.selectedRowIndexes==IndexSet([a,b]),"Context member preserves multiselection")
        check(multi.item(withTitle:"Open")?.isEnabled==false && multi.item(withTitle:"Copy to other pane…")?.isEnabled==true,"Multiple files allow group copy, not ambiguous Open")
        p.marked=[p.entries[a-1].url,p.entries[b-1].url]
        _=p.contextMenu(forRow:b)
        check(p.marked.count==2 && p.selectedEntries.count==2,"Marked context member preserves marked group")
        _=p.contextMenu(forRow:d)
        check(p.marked.isEmpty && p.selectedEntries.map(\.name)==["c.txt"],"Context outside marked group targets only clicked file")
        p.marked=[p.entries[a-1].url]
        let blank=p.contextMenu(forRow:-1)!
        check(p.marked.count==1 && p.currentEntry?.name=="c.txt","Blank-space menu preserves the existing selection and marks")
        check(blank.items.map(\.title)==["New folder…","Refresh"],"Blank menu only contains directory actions")
        let parent=p.contextMenu(forRow:0)!
        check(parent.item(withTitle:"Move to Trash…")==nil,"Parent row has no destructive file actions")
        let folderMenu=p.contextMenu(forRow:folder)!
        check(folderMenu.item(withTitle:"Open")?.isEnabled==true && folderMenu.item(withTitle:"View")?.isEnabled==false,"Folder opens without a text-file viewer action")
        c.busy=true;let beforeBusy=p.table.selectedRowIndexes;check(p.contextMenu(forRow:a)==nil && p.table.selectedRowIndexes==beforeBusy,"Busy controller refuses context menu without changing selection");c.busy=false
        p.isLoading=true;check(p.contextMenu(forRow:b)==nil,"Loading pane refuses context menu");p.isLoading=false
        let stale=p.contextMenu(forRow:a)!.item(withTitle:"Refresh")!
        p.table.selectRowIndexes(IndexSet(integer:b),byExtendingSelection:false)
        c.fileContextAction(stale)
        check(c.status.stringValue=="The context changed. Open the file menu again.","Stale menu action refuses a changed target")
        let point=p.table.convert(NSPoint(x:20,y:p.table.rect(ofRow:d).midY),to:nil)
        let event=NSEvent.mouseEvent(with:.rightMouseDown,location:point,modifierFlags:[],timestamp:0,windowNumber:c.window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
        check(p.table.menu(for:event) != nil && p.currentEntry?.name=="c.txt","Table mouse route builds menu for hit-tested file")
        p.setBriefMode(true)
        let briefPoint=p.briefGrid.convert(p.briefGrid.cellRect(b).origin.applying(CGAffineTransform(translationX:10,y:5)),to:nil)
        let briefEvent=NSEvent.mouseEvent(with:.rightMouseDown,location:briefPoint,modifierFlags:[],timestamp:0,windowNumber:c.window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
        check(p.briefGrid.menu(for:briefEvent) != nil && p.currentEntry?.name=="b.txt","Brief mouse route hit-tests correct column and row")
        _=p.setThumbnailMode()
        let thumbPoint=p.thumbnailGrid.convert(p.thumbnailGrid.cellRect(a).origin.applying(CGAffineTransform(translationX:10,y:5)),to:nil)
        let thumbEvent=NSEvent.mouseEvent(with:.rightMouseDown,location:thumbPoint,modifierFlags:[],timestamp:0,windowNumber:c.window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
        check(p.thumbnailGrid.menu(for:thumbEvent) != nil && p.currentEntry?.name=="a.txt","Thumbnail mouse route hit-tests correct file")
        p.setBriefMode(false)
        var profile=FTPProfile();profile.host="127.0.0.1";profile.security = .plainFTP
        let client=try FTPClient(profile:profile,password:"")
        p.applyListing(p.entries,location:.ftp(client,path:"/"))
        let remote=p.contextMenu(forRow:a)!
        check(remote.item(withTitle:"Delete from server…")?.isEnabled==true && remote.item(withTitle:"Move to Trash…")==nil,"Remote deletion is never labeled Trash")
        check(remote.item(withTitle:"Properties")?.isEnabled==false,"Local properties disabled on FTP")
        let archive=root.appendingPathComponent("read-only.7z"),tool=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/7zz")
        let pack=Process();pack.executableURL=tool;pack.arguments=["a",archive.path,root.appendingPathComponent("a.txt").path];pack.standardOutput=FileHandle.nullDevice;pack.standardError=FileHandle.nullDevice
        try pack.run();pack.waitUntilExit();check(pack.terminationStatus==0,"Read-only archive fixture created")
        let session=try ArchiveBrowserSession(archive:archive,tool:tool)
        let archiveLocation=PaneLocation.archive(session,path:"")
        p.applyListing(try archiveLocation.list(showHidden:false),location:archiveLocation)
        let readOnly=p.contextMenu(forRow:1)!
        check(readOnly.item(withTitle:"View")?.isEnabled==true,"Read-only archive still supports viewing")
        check(readOnly.item(withTitle:"Edit")?.isEnabled==false && readOnly.item(withTitle:"Delete from archive…")?.isEnabled==false && readOnly.item(withTitle:"New folder…")?.isEnabled==false,"Read-only archive disables mutations without presenting an error")
        check(readOnly.item(withTitle:"Copy to other pane…")?.isEnabled==true,"Read-only archive can still be extracted to writable local pane")
        print("Context menu: \(count) checks passed")
    }
}
