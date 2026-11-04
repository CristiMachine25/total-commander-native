import AppKit
@main struct TabSettingsTests {
    static func main()throws {
        let app=NSApplication.shared;app.setActivationPolicy(.prohibited)
        let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("tab-settings-"+UUID().uuidString)
        try fm.createDirectory(at:root,withIntermediateDirectories:false);defer{try? fm.removeItem(at:root)}
        let a=root.appendingPathComponent("A"),b=root.appendingPathComponent("B")
        try fm.createDirectory(at:a,withIntermediateDirectories:false);try fm.createDirectory(at:b,withIntermediateDirectories:false)
        let c=CommanderController(initial:root,remember:false),p=c.left
        c.runtimeConfig.confirmCloseAllTabs=false
        var count=0
        func check(_ value:Bool,_ message:String){count += 1;precondition(value,message)}
        check(p.lockTab(0),"Local tab can lock")
        check(p.tabControl.label(forSegment:0)?.hasPrefix("*")==true,"Locked marker visible")
        c.navigate(a);check(p.tabs.count==2 && p.tabs[0] == .local(root) && p.location == .local(a),"Navigation creates a new tab and retains locked root")
        check(p.selectedTab==1 && p.lockedTabRoots[0]==root,"New tab selected, lock retained")
        c.openLocationInNewTab(.local(b),pane:p);_=p.lockTab(2)
        c.closeFolderTab(1,pane:p);check(p.tabs.count==2 && p.lockedTabRoots[1]==b && p.selectedTab==1,"Removing preceding tab shifts locks and selection")
        c.closeFolderTab(0,pane:p);check(p.tabs.count==2,"Locked tab cannot close")
        c.selectTab(0,pane:p);c.runtimeConfig.newTabBesideCurrent=true;c.navigate(b)
        check(p.selectedTab==1 && p.lockedTabRoots[2]==b && p.lockedTabRoots[0]==root,"Insertion beside current shifts later locks")
        c.openLocationInNewTab(.local(a),pane:p)
        c.closeOtherTabs(p);check(p.tabs.count==3 && p.location == .local(a) && p.lockedTabRoots.count==2,"Close others retains active plus all locked tabs")
        let saved=p.savedLocalTabLocks
        let mirror=Pane(directory:root,title:"TabLockRestore");mirror.tabs=p.tabs;mirror.restoreLocalTabLocks(saved)
        check(mirror.lockedTabRoots==p.lockedTabRoots,"Local lock state round trips across session representation")
        mirror.restoreLocalTabLocks(["0":a.path,"99":root.path]);check(mirror.lockedTabRoots.isEmpty,"Mismatched and out-of-range persisted locks rejected")
        let prior=p.tabs.count
        c.closeFolderTab(p.selectedTab,pane:p);check(p.tabs.count==prior-1 && p.lockedTabRoots[p.selectedTab] != nil,"Closing current tab selects adjacent locked root without opening another tab")
        var config=c.runtimeConfig;config.tabsShowLockAsterisk=false;c.applyConfiguration(config)
        check(p.tabControl.label(forSegment:0)?.hasPrefix("*")==false,"Marker setting changes actual labels")
        c.openLocationInNewTab(.local(a),pane:p)
        let beforeDouble=p.tabs.count
        p.tabControl.handleCompletedClick(count:2,segment:p.selectedTab)
        check(p.tabs.count==beforeDouble,"Double click disabled by default")
        config=c.runtimeConfig;config.tabsCloseOnDoubleClick=true;c.applyConfiguration(config)
        p.tabControl.handleCompletedClick(count:2,segment:p.selectedTab)
        check(p.tabs.count==beforeDouble-1,"Enabled double click closes actual tab")
        c.openLocationInNewTab(.local(a),pane:c.right);let leftCount=p.tabs.count
        c.right.tabControl.handleCompletedClick(count:2,segment:c.right.selectedTab)
        check(c.right.tabs.count==1 && p.tabs.count==leftCount && c.activePane === c.right,"Closing right tab targets and activates right pane")
        c.activate(0);let leftLocks=c.left.lockedTabRoots,rightLocks=c.right.lockedTabRoots
        c.swapPaneTabs()
        let limit=Date().addingTimeInterval(5)
        while c.busy,Date()<limit {RunLoop.current.run(until:Date().addingTimeInterval(0.01))}
        check(!c.busy && c.left.lockedTabRoots==rightLocks && c.right.lockedTabRoots==leftLocks,"Swapping pane tabs swaps lock metadata")
        let control=CommanderTabControl();control.frame=NSRect(x:0,y:0,width:100,height:24);control.segmentCount=2;control.setWidth(40,forSegment:0);control.setWidth(60,forSegment:1)
        check(control.segment(at:NSPoint(x:10,y:10))==0 && control.segment(at:NSPoint(x:80,y:10))==1,"Context-menu hit testing selects correct segment")
        check(control.segment(at:NSPoint(x:120,y:10))==nil,"Blank tab strip has no target")
        let menuController=CommanderController(initial:root,remember:false),menuPane=menuController.left
        menuController.runtimeConfig.confirmCloseAllTabs=false
        menuController.openLocationInNewTab(.local(a),pane:menuPane,background:true)
        menuController.openLocationInNewTab(.local(b),pane:menuPane,background:true)
        check(menuPane.selectedTab==0,"Context regression starts with a different active tab")
        let menu=menuController.tabContextMenu(2,pane:menuPane)!,closeOthers=menu.items.last!
        NSApp.sendAction(closeOthers.action!,to:closeOthers.target,from:closeOthers)
        check(menuPane.tabs==[.local(b)] && menuPane.location == .local(b),"Close-others context action preserves the right-clicked inactive tab")
        var remoteProfile=FTPProfile();remoteProfile.host="127.0.0.1";remoteProfile.port=9
        let remoteClient=try FTPClient(profile:remoteProfile,password:"",options:.init(connectTimeout:1,transferTimeout:1))
        let remote=PaneLocation.ftp(remoteClient,path:"/")
        menuPane.tabs=[.local(root),remote];menuPane.selectedTab=1;menuPane.location=remote;menuPane.updateTabs()
        let generation=menuPane.loadGeneration
        menuPane.onTab?(1)
        check(menuPane.loadGeneration==generation && !menuPane.isLoading,"Clicking the current FTP tab does not start a network reload")
        var remoteConfig=menuController.runtimeConfig;remoteConfig.tabsCloseOnDoubleClick=true;menuController.applyConfiguration(remoteConfig)
        menuPane.tabControl.handleCompletedClick(count:2,segment:1)
        check(menuPane.tabs==[.local(root)] && menuPane.location == .local(root),"Double-click closes current FTP tab and opens local neighbor without a remote reload")
        print("PASS: \(count) tab settings assertions")
    }
}
