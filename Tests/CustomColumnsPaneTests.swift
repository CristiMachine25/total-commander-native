import AppKit
@main struct CustomColumnsPaneTests {
    static func main()throws {
        let app=NSApplication.shared;app.setActivationPolicy(.prohibited)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("custom-pane-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        try Data(repeating:1,count:20).write(to:root.appendingPathComponent("small.txt"))
        try Data(repeating:1,count:100).write(to:root.appendingPathComponent("large.txt"))
        let c=CommanderController(initial:root,remember:false),p=c.left
        var config=c.runtimeConfig
        let set=CustomColumnSet(id:"sizes",name:"Sizes",columns:[.init(id:"bytes",title:"Bytes",expression:"[=tc.size.bytes]",width:120,alignment:.right),.init(id:"label",title:"Label",expression:"File [=tc.fullname]",width:200)],adjustNameWidth:false,horizontalScroll:true)
        config.customColumnSets=[set];config.activeCustomColumnSetID="sizes";config.extensionStyle = .afterName;c.applyConfiguration(config)
        var count=0
        func check(_ b:Bool,_ message:String){precondition(b,message);count += 1}
        check(p.table.tableColumns.filter{!$0.isHidden}.map{$0.identifier.rawValue} == ["name","ext","custom.bytes","custom.label"],"Permanent name/ext plus ordered custom columns")
        check(p.table.columnAutoresizingStyle == .noColumnAutoresizing && p.table.enclosingScrollView?.hasHorizontalScroller == true,"Sizing and horizontal scrolling")
        let small=p.entries.first{$0.name=="small.txt"}!
        check(p.customColumnText("custom.bytes",entry:small)=="20","Rendered expression")
        p.sortColumn="custom.bytes";p.ascending=true;p.sortEntries()
        check(p.entries.map(\.name)==["small.txt","large.txt"],"Numerical sort")
        p.table.reloadData();p.table.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false);p.marked=[small.url]
        let column=p.table.tableColumns.first{$0.identifier.rawValue=="custom.bytes"}!
        let cell=p.tableView(p.table,viewFor:column,row:1) as! NSTextField
        check(cell.stringValue=="20" && cell.alignment == .right,"Cell content and alignment")
        let nameColumn=p.table.tableColumns.first{$0.identifier.rawValue=="name"}!
        let nameView=p.tableView(p.table,viewFor:nameColumn,row:1)
        let nameText=(nameView as? NSTableCellView)?.textField?.stringValue ?? (nameView as? NSTextField)?.stringValue
        check(nameText=="✓ small","Custom name column does not duplicate extension")
        var edited=config;edited.customColumnSets[0].columns[0].expression="[=tc.size.kbytes]";c.applyConfiguration(edited)
        check(p.customColumnText("custom.bytes",entry:small)=="0.02","Cache invalidated after editing expression")
        check(p.marked.contains(small.url) && p.currentEntry?.url==small.url,"Marks and selection survive config")
        edited.activeCustomColumnSetID="";c.applyConfiguration(edited)
        check(p.table.tableColumns.map{$0.identifier.rawValue} == ["name","ext","size","date","attr"],"Removing custom view restores standard columns")
        check(p.sortColumn=="name","Deleted custom sort resets")
        check(p.table.tableColumns.filter{!$0.isHidden}.map{$0.identifier.rawValue} == ["name","size","date","attr"],"Standard after-name extension visibility restored")
        check(c.customColumnsMenu().items.count==2,"Manual menu exposes configured set")
        c.selectCustomColumns("sizes");check(p.currentCustomColumnSet?.id=="sizes" && c.right.currentCustomColumnSet==nil,"Manual custom view applies only active pane")
        print("PASS: \(count) custom column pane assertions")
    }
}
