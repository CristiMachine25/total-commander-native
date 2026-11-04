import AppKit
extension NativeCommander {
    static func providerSmokeTest() throws {
        guard CommandLine.arguments.count >= 5 else {fatalError("Missing provider fixture arguments")}
        let root=URL(fileURLWithPath:CommandLine.arguments[2]),tool=URL(fileURLWithPath:CommandLine.arguments[3]),port=Int(CommandLine.arguments[4])!
        let c=CommanderController(initial:root.appendingPathComponent("local"),remember:false)
        func settle(_ pane:Pane) {
            let deadline=Date().addingTimeInterval(20)
            while pane.isLoading && Date()<deadline {_=RunLoop.current.run(mode:.default,before:Date().addingTimeInterval(0.02))}
            precondition(!pane.isLoading,"Provider listing did not settle")
        }
        func shortcut(_ key:UInt16,_ modifiers:NSEvent.ModifierFlags,_ text:String="") {
            let event=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:modifiers,timestamp:0,windowNumber:c.window.windowNumber,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:key)!
            precondition(c.handleKey(event))
        }
        let archive=try ArchiveBrowserSession(archive:root.appendingPathComponent("local/example.zip"),tool:tool)
        c.navigate(.archive(archive,path:""));settle(c.left)
        precondition(c.left.location.localDirectory == nil && c.left.entries.first?.name == "inside")
        precondition(c.left.entries.allSatisfy{!$0.url.isFileURL})
        c.left.table.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false);c.openCurrent();settle(c.left)
        precondition(c.left.entries.first?.name == "archive.txt" && c.left.path.stringValue.contains("!/inside"))
        shortcut(42,[.control],"\\");settle(c.left)
        precondition(c.left.location == .archive(archive,path:""),"Archive root shortcut left provider")
        c.navigate(.archive(archive,path:"inside"));settle(c.left)
        c.left.table.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false)
        shortcut(36,[.control,.shift]);precondition(c.commandField.stringValue.contains("!/inside/archive.txt"))
        c.commandField.stringValue=""
        c.newTab();settle(c.left);precondition(c.left.tabs.count==2)
        c.navigate(root.appendingPathComponent("local"));c.selectTab(0);settle(c.left)
        precondition(c.left.entries.first?.name == "archive.txt")
        c.backFolder();settle(c.left);precondition(c.left.entries.first?.name == "inside")
        c.forwardFolder();settle(c.left);precondition(c.left.entries.first?.name == "archive.txt")
        var profile=FTPProfile();profile.host="127.0.0.1";profile.port=port;profile.username="fixture";profile.security = .plainFTP
        let client=try FTPClient(profile:profile,password:"fixture-password")
        c.activate(1);c.navigate(.ftp(client,path:"/"));settle(c.right)
        precondition(c.right.entries.contains{$0.name=="remote.txt"} && c.right.entries.allSatisfy{!$0.url.isFileURL})
        let remote=c.right.entries.first{$0.name=="remote.txt"}!
        let lease=try c.right.location.readableMaterialization(remote);let remoteText=try String(contentsOf:lease.url,encoding:.utf8);precondition(remoteText=="remote bytes")
        _=try c.left.location.export(c.left.entries,to:root.appendingPathComponent("target"))
        let archiveText=try String(contentsOf:root.appendingPathComponent("target/archive.txt"),encoding:.utf8);precondition(archiveText=="archive bytes")
        _=try c.right.location.upload([root.appendingPathComponent("local/local.txt")]);c.reloadPane(c.right);settle(c.right)
        precondition(c.right.entries.contains{$0.name=="local.txt"})
        let nested=c.right.entries.first{$0.name=="sub"}!;c.navigate(try c.right.location.child(nested));settle(c.right)
        precondition(c.right.entries.first?.name=="nested.txt")
        shortcut(42,[.control],"\\");settle(c.right)
        precondition(c.right.location == .ftp(client,path:"/"),"FTP root shortcut left provider")
        c.right.table.selectRowIndexes(IndexSet(integer:(c.right.entries.firstIndex{$0.name=="remote.txt"}!)+1),byExtendingSelection:false)
        shortcut(36,[.control,.shift]);precondition(c.commandField.stringValue.contains("ftp://127.0.0.1:") && c.commandField.stringValue.contains("remote.txt"))
        c.commandField.stringValue=""

        precondition(c.right.path.stringValue.hasPrefix("ftp://127.0.0.1:"))
        c.navigate(.ftp(client,path:"/sub"));c.navigate(root.appendingPathComponent("local"),pane:c.right)
        let deadline=Date().addingTimeInterval(0.5);while Date()<deadline {_=RunLoop.current.run(mode:.default,before:Date().addingTimeInterval(0.02))}
        precondition(c.right.location.localDirectory?.lastPathComponent=="local","Stale FTP completion replaced newer local navigation")
        let stable=c.right.location
        c.right.tabs=[stable,.ftp(client,path:"/sub"),.ftp(client,path:"/missing")];c.right.selectedTab=0
        c.selectTab(1,pane:c.right);c.selectTab(2,pane:c.right);settle(c.right)
        precondition(c.right.selectedTab==0 && c.right.location==stable && c.right.tabs[c.right.selectedTab]==stable,"Failed async tabs changed selected state")
        let previousTabs=c.left.tabs
        c.right.location = .ftp(client,path:"/missing");c.right.tabs=[c.right.location];c.right.selectedTab=0
        c.swapPaneTabs()
        let swapDeadline=Date().addingTimeInterval(20);while c.busy && Date()<swapDeadline {_=RunLoop.current.run(mode:.default,before:Date().addingTimeInterval(0.02))}
        precondition(!c.busy && c.left.tabs==previousTabs,"Failed swap changed tabs")
        print("Provider UI integration passed: ZIP/FTP main panes, tabs/history, materialization, transfers, parent navigation, stale completion")
    }
}
