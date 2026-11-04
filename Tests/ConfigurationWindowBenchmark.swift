import AppKit

/// A non-persistent controller fixture exercises the real configuration window
/// without launching or editing the user's file-manager session.
final class CommanderController:NSObject {
    var runtimeConfig=CommanderConfiguration()
    var showHidden=false
    let remember=false
    var applied=0
    func applyConfiguration(_ value:CommanderConfiguration){runtimeConfig=value;showHidden=value.showHidden;applied += 1}
    func refresh(){}
}
@main struct Bench {
 static func descendants(_ root:NSView)->[NSView]{[root]+root.subviews.flatMap(descendants)}
 static func main(){
 _=NSApplication.shared
 let commander=CommanderController(),start=Date(),controller=PreferencesController(commander),window=controller.window!
 window.contentView!.layoutSubtreeIfNeeded()
 print("open/layout: \(Date().timeIntervalSince(start)*1000) ms")
 let nav=descendants(window.contentView!).compactMap{$0 as? NSTableView}.first!
 let t=Date()
 for _ in 0..<20{for row in [5,12,4,0]{nav.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false);window.contentView!.layoutSubtreeIfNeeded()}}
 print("80 category switches/layout: \(Date().timeIntervalSince(t)*1000) ms")
 }
}
