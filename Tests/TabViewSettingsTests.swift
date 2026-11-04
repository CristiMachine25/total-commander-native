import AppKit
@main struct TabViewSettingsTests {
    static func main()throws {
        let app=NSApplication.shared;app.setActivationPolicy(.prohibited)
        let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("tab-view-settings-"+UUID().uuidString)
        try fm.createDirectory(at:root,withIntermediateDirectories:false);defer{try? fm.removeItem(at:root)}
        let a=root.appendingPathComponent("A"),b=root.appendingPathComponent("B"),auto=root.appendingPathComponent("Auto")
        for folder in [a,b,auto] {try fm.createDirectory(at:folder,withIntermediateDirectories:false);try Data("x".utf8).write(to:folder.appendingPathComponent("one.txt"));try Data("longer".utf8).write(to:folder.appendingPathComponent("two.jpg"))}
        var checks=0
        func check(_ condition:Bool,_ reason:String){checks += 1;precondition(condition,reason)}
        let c=CommanderController(initial:a,remember:false),p=c.left
        var config=c.runtimeConfig;config.tabsRememberViewSettings=true;config.tabsRememberFileFilters=true;config.confirmCloseAllTabs=false
        let set=CustomColumnSet(id:"sizes",name:"Sizes",columns:[CustomColumnDefinition(id:"bytes",title:"Bytes",expression:"[=tc.size]",alignment:.right)])
        let manual=CommanderViewMode(id:"manual",name:"Manual",columnsView:.full,customColumnSetID:"sizes",sortColumn:"ext",ascending:true,secondarySortColumns:["-size"])
        let automatic=CommanderViewMode(id:"auto",name:"Automatic",columnsView:.brief,sortColumn:"size",ascending:false)
        config.customColumnSets=[set];config.viewModes=[manual,automatic];config.autoSwitchEnabled=true
        config.autoSwitchRules=[CommanderAutoSwitchRule(viewModeID:"auto",conditions:[CommanderViewCondition(kind:.path,value:auto.path)])]
        c.applyConfiguration(config)
        _=c.applyNamedViewMode(id:"manual");p.fileMask="*.txt";p.applyListing(p.refreshListedEntries,location:p.location)
        p.marked=Set(p.entries.map(\.url));p.table.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false)
        check(c.openLocationInNewTab(.local(b),background:true),"Background tab opens")
        check(p.tabs.count==2 && p.selectedTab==0 && p.tabViewSettings[1]?.manualModeID=="manual","Background inherits manual view without activating")
        c.selectTab(1);check(p.location == .local(b) && p.currentNamedViewModeID=="manual" && p.configuration.activeCustomColumnSetID=="sizes","Tab activation restores inherited mode/custom columns")
        c.fullView();p.sortColumn="name";p.ascending=false;p.fileMask="*.jpg";p.applyListing(p.refreshListedEntries,location:p.location);c.recordManualViewChange(in:p)
        c.selectTab(0)
        check(p.location == .local(a) && p.currentNamedViewModeID=="manual" && p.configuration.activeCustomColumnSetID=="sizes","First tab restores independent manual mode")
        check(p.fileMask=="*.txt" && p.sortColumn=="ext" && p.ascending,"First tab restores filter and primary sort")
        check(p.captureManualTabView().secondarySortColumns==["-size"],"Secondary sorts retained")
        check(p.marked.contains(where:{$0.lastPathComponent=="one.txt"}) && p.currentEntry?.name=="one.txt","Marked and cursor selections restore for same directory")
        c.selectTab(1);check(p.configuration.activeCustomColumnSetID.isEmpty && p.fileMask=="*.jpg" && !p.ascending,"Second tab retains its distinct settings")
        c.selectTab(0);_=c.openLocationInNewTab(.local(auto))
        check(p.currentNamedViewModeID=="auto" && p.namedViewIsAutomatic,"New tab reevaluates automatic mode")
        check(p.captureManualTabView().manualModeID=="manual" && p.captureManualTabView().columns=="full","Automatic mode does not overwrite inherited manual settings")
        let autoIndex=p.selectedTab;c.selectTab(1);c.selectTab(autoIndex)
        check(p.currentNamedViewModeID=="auto" && p.captureManualTabView().manualModeID=="manual","Automatic mode reevaluates after tab activation")
        c.navigate(b);check(!p.namedViewIsAutomatic && p.currentNamedViewModeID=="manual","Leaving automatic path restores tab manual mode")
        c.selectTab(0);_=p.lockTab(0);let count=p.tabs.count;c.navigate(b)
        check(p.tabs.count==count+1 && p.tabs[0] == .local(a) && p.tabViewSettings[0]?.manualModeID=="manual","Locked-tab navigation creates a tab preserving original view")
        let missing=root.appendingPathComponent("Missing");_=c.openLocationInNewTab(.local(missing),background:true)
        let beforeIndex=p.selectedTab,beforeLocation=p.location,beforeView=p.captureManualTabView()
        var succeeded=true;c.selectTab(p.tabs.count-1){succeeded=$0}
        check(!succeeded && p.selectedTab==beforeIndex && p.location==beforeLocation && p.captureManualTabView()==beforeView,"Failed navigation preserves active tab and view")
        p.removeTab(at:p.tabs.count-1)
        let savedCount=p.tabViewSettings.count;p.insertTab(.local(a),at:0)
        check(p.tabViewSettings.count==savedCount && p.tabViewSettings[1]?.manualModeID=="manual","Insertion shifts stored tab view indices")
        p.removeTab(at:0);check(p.tabViewSettings[0]?.manualModeID=="manual","Deletion shifts views back")
        p.rememberCurrentTabView();let activeValue=p.tabViewSettings[p.selectedTab]!
        p.retainTabs([0,p.selectedTab]);check(p.tabViewSettings[1]==activeValue && p.selectedTab==1,"Retaining tabs remaps state")
        c.navigate(auto,pane:c.right);c.fullView();c.activate(1);c.briefView();c.activate(0)
        p.rememberCurrentTabView();c.right.rememberCurrentTabView()
        let leftViews=p.tabViewSettings,rightViews=c.right.tabViewSettings
        c.swapPaneTabs();let deadline=Date().addingTimeInterval(5)
        while c.busy,Date()<deadline {RunLoop.current.run(until:Date().addingTimeInterval(0.01))}
        check(!c.busy && c.left.tabViewSettings==rightViews && c.right.tabViewSettings==leftViews,"Whole-pane tab swap moves stored settings")
        c.activate(1);let persistencePane=c.right
        let data=persistencePane.savedLocalTabViews()!
        let mirror=Pane(directory:a,title:"RestoreFixture");mirror.tabs=persistencePane.tabs;mirror.selectedTab=persistencePane.selectedTab
        mirror.restoreLocalTabViews(data,configuration:config)
        check(mirror.tabViewSettings==persistencePane.tabViewSettings,"Local tab settings serialize and restore by paired paths/indices")
        mirror.tabs[0] = .local(root);mirror.restoreLocalTabViews(data,configuration:config)
        check(mirror.tabViewSettings[0]==nil,"Stored state cannot attach to a different folder at same index")
        mirror.restoreLocalTabViews(Data("not json".utf8),configuration:config);check(mirror.tabViewSettings.isEmpty,"Malformed saved state ignored")
        var stale=CommanderTabViewSettings(manualModeID:"removed",customColumnSetID:"removed",sortColumn:"custom.removed",secondarySortColumns:["custom.removed"])
        let sanitized=stale.sanitized(configuration:config)!
        check(sanitized.manualModeID==nil && sanitized.customColumnSetID.isEmpty && sanitized.sortColumn=="name" && sanitized.secondarySortColumns.isEmpty,"Stale mode/set/sort references fall back safely")
        stale.selectedNames=["../escape"];check(stale.sanitized(configuration:config)==nil,"Invalid persisted selection names rejected")
        let target=c.right;c.selectTab(0,pane:target)
        target.fileMask="*.jpg";target.applyListing(target.refreshListedEntries,location:target.location)
        config.tabsRememberFileFilters=false;c.applyConfiguration(config)
        let maskBefore=target.fileMask;c.selectTab(1,pane:target)
        check(target.fileMask==maskBefore,"Disabled per-tab file filter retains pane-wide mask")
        config.tabsRememberViewSettings=false;c.applyConfiguration(config)
        target.setBriefMode(true);target.sortColumn="size";target.ascending=false;c.recordManualViewChange(in:target)
        c.selectTab(0,pane:target)
        check(target.viewMode == .brief && target.sortColumn=="size" && !target.ascending,"Disabled per-tab views retain pane-wide manual layout/sort")
        check(target.savedLocalTabViews()==nil,"Disabled tab views do not persist session records")
        config.tabsRememberViewSettings=true;config.tabsRememberFileFilters=true;c.applyConfiguration(config)
        c.activate(0);c.navigate(auto,pane:c.left)
        check(c.left.namedViewIsAutomatic,"Manual edit regression enters auto mode")
        c.showPrograms()
        check(!c.left.namedViewIsAutomatic && c.left.showProgramsOnly,"Manual filter survives same-directory refresh under automatic mode")
        c.navigate(a,pane:c.left);c.navigate(auto,pane:c.left)
        let sizeHeader=c.left.table.tableColumns.first{$0.identifier.rawValue=="size"}!
        c.left.tableView(c.left.table,didClick:sizeHeader)
        check(!c.left.namedViewIsAutomatic,"Header sort records manual override of automatic mode")
        c.left.tabViewSettings[0]=CommanderTabViewSettings(locationIdentity:"ftp://remote-fixture/private")
        let scrubbed=try JSONDecoder().decode(Pane.SavedTabViews.self,from:c.left.savedLocalTabViews()!)
        check(scrubbed.records.allSatisfy{$0.view.locationIdentity.hasPrefix("local:")},"Persisted local records exclude inherited remote identities")
        var profile=FTPProfile();profile.host="127.0.0.1";profile.port=9
        let client=try FTPClient(profile:profile,password:"fixture",options:.init(connectTimeout:1,transferTimeout:1))
        let pane=c.left;_=c.openLocationInNewTab(.ftp(client,path:"/"),pane:pane,background:true)
        let remoteIndex=pane.tabs.count-1;c.selectTab(remoteIndex,pane:pane);c.selectTab(0,pane:pane)
        let chosen=pane.location,chosenView=pane.captureManualTabView()
        RunLoop.current.run(until:Date().addingTimeInterval(0.15))
        check(pane.selectedTab==0 && pane.location==chosen && pane.captureManualTabView()==chosenView,"Stale asynchronous tab completion cannot replace newer selection")
        let localRecords=try JSONDecoder().decode(Pane.SavedTabViews.self,from:pane.savedLocalTabViews()!)
        check(localRecords.records.count==pane.tabs.filter{$0.localDirectory != nil}.count,"Only local tab views are serialized")
        let transitions=CommanderController(initial:b,remember:false),tp=transitions.left
        let latent=CommanderViewMode(id:"latent",name:"Latent",columnsView:.full,autoRunCommands:"|cm_100percent")
        var sourceMode=CommanderViewMode(id:"source",name:"Source",columnsView:.brief,autoRunCommands:"cm_100percent|cm_50percent")
        let targetMode=CommanderViewMode(id:"target",name:"Target",columnsView:.full)
        var transitionConfig=transitions.runtimeConfig;transitionConfig.viewModes=[latent,sourceMode,targetMode];transitionConfig.autoSwitchEnabled=true
        transitionConfig.autoSwitchRules=[CommanderAutoSwitchRule(viewModeID:"source",conditions:[CommanderViewCondition(kind:.path,value:a.path)]),CommanderAutoSwitchRule(viewModeID:"target",conditions:[CommanderViewCondition(kind:.path,value:b.path)])]
        transitions.applyConfiguration(transitionConfig);_=transitions.applyNamedViewMode(id:"latent");_=transitions.openLocationInNewTab(.local(a))
        transitions.window.contentView?.layoutSubtreeIfNeeded()
        transitions.selectTab(0)
        let half=transitions.splitView.bounds.width/2
        check(abs(transitions.splitView.subviews[0].frame.width-half)<5,"Tab transition runs effective source leave and not inactive saved manual leave")
        tp.table.selectRowIndexes(IndexSet([1,2]),byExtendingSelection:false)
        transitions.selectTab(1);transitions.selectTab(0)
        check(tp.table.selectedRowIndexes==IndexSet([1,2]),"Automatic mode reapplication preserves multiple highlighted rows")
        tp.rememberCurrentTabView();transitions.finishRestoringNamedViewModes()
        check(tp.table.selectedRowIndexes==IndexSet([1,2]) && tp.currentNamedViewModeID=="target","Startup tab restoration preserves multi-selection through automatic mode")
        sourceMode.autoRunCommands="-cm_100percent|cm_50percent";transitionConfig.viewModes=[latent,sourceMode,targetMode];transitions.applyConfiguration(transitionConfig)
        transitions.splitView.setPosition(half,ofDividerAt:0);transitions.selectTab(1)
        check(abs(transitions.splitView.subviews[0].frame.width-half)<5,"Dash skips enter commands on tab activation")
        transitions.splitView.setPosition(transitions.splitView.bounds.width,ofDividerAt:0);let wide=transitions.splitView.subviews[0].frame.width
        transitions.selectTab(0)
        check(abs(transitions.splitView.subviews[0].frame.width-wide)<5,"Dash skips effective source leave commands on tab activation")
        let defaultsController=CommanderController(initial:a,remember:false)
        var defaultsConfig=defaultsController.runtimeConfig;defaultsConfig.viewModes=[CommanderViewMode(id:"red",name:"Red",columnsView:.brief,background:.init(red:1,green:0.8,blue:0.8))]
        defaultsController.applyConfiguration(defaultsConfig);_=defaultsController.applyNamedViewMode(id:"red");_=defaultsController.openLocationInNewTab(.local(b));defaultsController.selectTab(0)
        _=defaultsController.applyNamedViewMode(id:"default")
        check(defaultsController.left.configuration.background==defaultsConfig.background && defaultsController.left.viewMode == .full,"Default after tab restoration returns pre-mode appearance and layout")
        print("PASS: \(checks) per-tab view settings assertions")
    }
}
