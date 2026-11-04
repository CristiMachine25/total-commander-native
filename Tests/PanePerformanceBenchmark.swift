import AppKit
@main struct PanePerformanceBenchmark {
 static func main() throws {
 _=NSApplication.shared
 let root=URL(fileURLWithPath:"/private/tmp/tc-pane-benchmark")
 let p=Pane(directory:root,title:"PerformanceFixture")
 var cfg=CommanderConfiguration();cfg.iconMode = .none;p.applyConfiguration(cfg)
 for n in [1000,10000] {
 let rows=(0..<n).map { i in FileEntry(url:root.appendingPathComponent("file-\(i).txt"),name:"file-\(i).txt",isDirectory:false,isSymbolicLink:false,size:Int64(i),modified:Date(timeIntervalSince1970:1600000000)) }
 p.applyListing(rows,location:.local(root));p.table.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false)
 func time(_ name:String,_ count:Int,_ body:()->Void) {let start=CFAbsoluteTimeGetCurrent();for _ in 0..<count {body()};print("\(n) \(name): \((CFAbsoluteTimeGetCurrent()-start)*1000/Double(count)) ms/op")}
 time("single selection footer",100){p.updateFooter()}
 time("repeated format-only config Apply",10){var c=cfg;c.sizeFormat = .megabytes;p.applyConfiguration(c)}
 let col=p.table.tableColumns[0]
 time("name cell",1000){_=p.tableView(p.table,viewFor:col,row:1)}
 }
 }
}
