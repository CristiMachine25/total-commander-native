import AppKit

@main struct RefreshSettingsTests {
    static func main()throws {
        _=NSApplication.shared
        let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("refresh-settings-"+UUID().uuidString)
        try fm.createDirectory(at:root,withIntermediateDirectories:false);defer{try? fm.removeItem(at:root)}
        for name in ["a.txt","b.txt","c.txt"] {try Data(name.utf8).write(to:root.appendingPathComponent(name))}
        let c=CommanderController(initial:root,remember:false)
        var count=0
        func check(_ condition:Bool,_ message:String){count += 1;precondition(condition,message)}
        func scan(_ activation:Bool=false)throws {
            let previous=c.refreshController.completedScans
            if activation {c.refreshController.requestActivationRefresh()}else{c.refreshController.scanNow()}
            let deadline=Date().addingTimeInterval(5)
            while c.refreshController.completedScans==previous && Date()<deadline {RunLoop.current.run(until:Date().addingTimeInterval(0.01))}
            check(c.refreshController.completedScans>previous,"Background scan completed")
        }
        var config=c.runtimeConfig;config.autoRefreshEnabled=true;config.autoRefreshOnlyForeground=false;c.applyConfiguration(config)
        config.alternatingRowBackground=true;config.alternatingBackground = .init(red:0.9,green:0.8,blue:0.7);c.applyConfiguration(config)
        let oddRow=c.left.tableView(c.left.table,rowViewForRow:1)!
        let evenRow=c.left.tableView(c.left.table,rowViewForRow:2)!
        check(oddRow.backgroundColor==config.alternatingBackground.nsColor,"Odd Full rows use configured alternate background")
        check(evenRow.backgroundColor==config.background.nsColor,"Even Full rows retain normal background")
        check(c.left.itemBackground(row:1)==config.alternatingBackground.nsColor,"Brief row background uses shared alternating policy")
        config.alternatingRowBackground=false;c.applyConfiguration(config)
        check(c.left.tableView(c.left.table,rowViewForRow:1)!.backgroundColor==config.background.nsColor,"Disabling alternation restores normal row background")
        c.left.table.selectRowIndexes(IndexSet([1,3]),byExtendingSelection:false)
        let markedURL=c.left.entries.first{$0.name=="b.txt"}!.url
        c.left.marked=[markedURL]
        try Data("added".utf8).write(to:root.appendingPathComponent("aa.txt"));try scan()
        check(c.left.entries.count==4 && c.right.entries.count==4,"Created file refreshes both local panes")
        check(Set(c.left.table.selectedRowIndexes.map{c.left.entries[$0-1].name})==["a.txt","c.txt"],"All nonadjacent cursor selections survive refresh")
        check(c.left.marked==[markedURL],"Marks survive refresh")
        config.autoRefreshMetadata=false;c.applyConfiguration(config)
        let previousSize=c.left.entries.first{$0.name=="a.txt"}!.size
        try Data(repeating:65,count:500).write(to:root.appendingPathComponent("a.txt"));try scan()
        check(c.left.entries.first{$0.name=="a.txt"}!.size==previousSize,"Names-only refresh ignores size/date changes")
        config.autoRefreshMetadata=true;c.applyConfiguration(config);try scan()
        check(c.left.entries.first{$0.name=="a.txt"}!.size==500,"Metadata refresh updates file sizes")
        try fm.removeItem(at:root.appendingPathComponent("b.txt"));try scan()
        check(c.left.marked.isEmpty && !c.left.entries.contains{$0.name=="b.txt"},"Deleted file removes stale marks")
        config.autoRefreshEnabled=false;config.refreshOnActivate=false;c.applyConfiguration(config)
        try Data().write(to:root.appendingPathComponent("disabled.txt"));c.refreshController.scanNow();RunLoop.current.run(until:Date().addingTimeInterval(0.05))
        check(!c.left.entries.contains{$0.name=="disabled.txt"},"Disabled refresh does not scan")
        config.refreshOnActivate=true;c.applyConfiguration(config);try scan(true)
        check(c.left.entries.contains{$0.name=="disabled.txt"},"Activation refresh works with background watcher disabled")
        try Data().write(to:root.appendingPathComponent("busy.txt"));c.busy=true;c.refreshController.requestActivationRefresh()
        check(!c.left.entries.contains{$0.name=="busy.txt"},"Busy operation defers activation refresh")
        c.busy=false;try scan();check(c.left.entries.contains{$0.name=="busy.txt"},"Deferred activation request survives busy state")
        // Each pane must keep its own scan baseline even when both show one folder.
        config.autoRefreshEnabled=true;config.autoRefreshMetadata=false;c.applyConfiguration(config);try scan()
        c.right.isLoading=true
        try Data().write(to:root.appendingPathComponent("deferred-pane.txt"));try scan()
        check(c.left.entries.contains{$0.name=="deferred-pane.txt"} && !c.right.entries.contains{$0.name=="deferred-pane.txt"},"Loading pane defers while other pane refreshes")
        c.right.isLoading=false;try scan()
        check(c.right.entries.contains{$0.name=="deferred-pane.txt"},"Deferred pane refreshes despite other pane already caching the same directory stamp")
        config.autoRefreshEnabled=true;config.autoRefreshExcludedPaths=root.path;c.applyConfiguration(config)
        try Data().write(to:root.appendingPathComponent("excluded.txt"));c.refreshController.scanNow();RunLoop.current.run(until:Date().addingTimeInterval(0.05))
        check(!c.left.entries.contains{$0.name=="excluded.txt"},"Excluded path does not refresh")
        check(CommanderRefreshController.excluded(root.appendingPathComponent("child"),paths:root.path),"Exclusion covers descendants")
        check(!CommanderRefreshController.excluded(URL(fileURLWithPath:root.path+"-other"),paths:root.path),"Exclusion respects path component boundary")
        config.autoRefreshExcludedPaths="";config.autoRefreshUpdateHeader=false;c.applyConfiguration(config);c.left.heading.stringValue="unchanged header";try scan()
        check(c.left.heading.stringValue=="unchanged header","Optional disk-space heading update disabled")
        print("PASS: \(count) refresh settings assertions")
    }
}
