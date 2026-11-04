import AppKit

/// Exercises actual pane selection/configuration paths with a large synthetic listing.
@main struct PanePerformanceTests {
    static func main() throws {
        _=NSApplication.shared
        var checks=0
        func check(_ condition:Bool,_ message:String) {checks += 1;precondition(condition,message)}
        let root=URL(fileURLWithPath:"/private/tmp/pane-performance-fixture")
        let pane=Pane(directory:root,title:"PerformanceRegression")
        let rows=(0..<10000).map {i in FileEntry(url:root.appendingPathComponent("file-\(i).txt"),name:"file-\(i).txt",isDirectory:i==0,isSymbolicLink:false,size:Int64(i),modified:nil)}
        pane.applyListing(rows,location:.local(root))
        pane.table.selectRowIndexes(IndexSet([0,2,7]),byExtendingSelection:false)
        check(pane.selectedEntries.map(\.url)==[pane.entries[1].url,pane.entries[6].url],"Selected-row lookup skips parent and preserves listing order")
        pane.marked=[pane.entries[9].url,pane.entries[3].url]
        check(pane.selectedEntries.map(\.url)==[pane.entries[3].url,pane.entries[9].url],"Marks override cursor selection in listing order")
        pane.updateFooter()
        check(pane.footer.stringValue.contains("2 selected"),"Footer counts marks only once")
        pane.marked=[]
        let selected=pane.selectedEntries.map(\.url)
        var cfg=CommanderConfiguration();cfg.iconMode = .none
        pane.applyConfiguration(cfg)
        cfg.sizeFormat = .megabytes;cfg.fileFontSize=15;pane.applyConfiguration(cfg)
        check(pane.selectedEntries.map(\.url)==selected,"Presentation-only settings preserve selection")
        check(pane.configuredFont.pointSize==15,"Cached font follows settings")
        cfg.ignoreListEnabled=true;cfg.ignorePatterns="file-1*";pane.applyConfiguration(cfg)
        check(!pane.entries.contains{$0.name.hasPrefix("file-1")},"Ignore changes still refilter")
        cfg.ignoreListEnabled=false;pane.applyConfiguration(cfg)
        check(pane.entries.count==10000,"Turning filter off restores full retained listing")
        pane.sortColumn="size";pane.ascending=false;pane.sortEntries()
        let before=pane.entries.map(\.url)
        cfg.sizeFormat = .gigabytes;pane.applyConfiguration(cfg)
        check(pane.entries.map(\.url)==before,"Display-only settings keep current sorting")
        cfg.directoriesFirst=false;pane.applyConfiguration(cfg)
        check(pane.entries.first?.size==9999,"Sort policy changes still resort")
        let column=pane.table.tableColumns.first{$0.identifier.rawValue=="size"}!
        let cell=pane.tableView(pane.table,viewFor:column,row:1) as! NSTextField
        check(cell.stringValue==cfg.sizeString(pane.entries[0].size),"Reusable size cell reflects current units")
        check(cell.identifier != nil,"Text cells register reuse identifiers")
        cfg.iconMode = .standard;pane.applyConfiguration(cfg)
        let name=pane.tableView(pane.table,viewFor:pane.table.tableColumns[0],row:1) as! NSTableCellView
        check(name.identifier != nil && name.imageView != nil,"Icon cells register reuse identifiers")
        check(name.textField?.toolTip==pane.entries[0].url.path,"Icon cell keeps correct file tooltip")
        pane.table.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false)
        let start=CFAbsoluteTimeGetCurrent();for _ in 0..<1000 {pane.updateFooter()}
        print("Single-selection footer, 10k rows: \((CFAbsoluteTimeGetCurrent()-start)*1000/1000) ms/op")
        print("Pane performance regressions: \(checks) checks passed")
    }
}
