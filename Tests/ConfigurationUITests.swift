import AppKit

/// A non-persistent controller fixture exercises the real configuration window
/// without launching or editing the user's file-manager session.
final class CommanderController:NSObject {
    var runtimeConfig=CommanderConfiguration()
    var showHidden=false
    let remember=false
    var applied=0,refreshed=0
    func applyConfiguration(_ value:CommanderConfiguration){runtimeConfig=value;showHidden=value.showHidden;applied += 1}
    func refresh(){refreshed += 1}
}
@main struct ConfigurationUITests {
    static var checks=0
    static func check(_ value:@autoclosure ()->Bool,_ message:String)throws{checks += 1;if !value(){throw NSError(domain:"ConfigurationUITests",code:checks,userInfo:[NSLocalizedDescriptionKey:message])}}
    static func descendants(_ root:NSView)->[NSView]{[root]+root.subviews.flatMap(descendants)}
    static func main()throws {
        _=NSApplication.shared
        let commander=CommanderController(),controller=PreferencesController(commander),window=controller.window!
        window.contentView!.layoutSubtreeIfNeeded()
        let navigation=descendants(window.contentView!).compactMap{$0 as? NSTableView}.first!
        let count=navigation.numberOfRows
        try check(count>=20,"Original configuration categories are navigable")
        for row in 0..<count {
            navigation.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)
            window.contentView!.layoutSubtreeIfNeeded()
            let views=descendants(window.contentView!)
            try check(views.compactMap{$0 as? NSScrollView}.allSatisfy{$0.frame.width>100 && $0.frame.height>50},"Category \(row) content and navigation have usable geometry")
        }
        navigation.selectRowIndexes(IndexSet(integer:5),byExtendingSelection:false)
        let sizeChoice=descendants(window.contentView!).compactMap{$0 as? NSPopUpButton}.first{$0.itemTitles.contains("Fixed MB (native addition)")}!
        try check(sizeChoice.numberOfItems==12,"Tabstops exposes all ten original formats plus explicit fixed MB/GB choices")
        sizeChoice.selectItem(withTitle:"Fixed MB (native addition)")
        navigation.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
        navigation.selectRowIndexes(IndexSet(integer:5),byExtendingSelection:false)
        let revisitedChoice=descendants(window.contentView!).compactMap{$0 as? NSPopUpButton}.first{$0.itemTitles.contains("Fixed MB (native addition)")}!
        try check(revisitedChoice === sizeChoice && revisitedChoice.titleOfSelectedItem=="Fixed MB (native addition)","Revisiting a category reuses its controls without losing unsaved changes")
        navigation.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false)
        let hidden=descendants(window.contentView!).compactMap{$0 as? NSButton}.first{$0.title=="Show hidden files"}!
        hidden.state = .on
        let apply=descendants(window.contentView!).compactMap{$0 as? NSButton}.first{$0.title=="Apply"}!
        let persistedBefore=UserDefaults.standard.data(forKey:CommanderConfiguration.defaultsKey)
        apply.performClick(nil)
        try check(commander.refreshed==0,"Applying settings does not start an unconditional second directory scan")
        try check(commander.applied==1 && commander.runtimeConfig.showHidden && commander.runtimeConfig.sizeFormat == .megabytes,"Apply invokes actual runtime configuration update")
        try check(UserDefaults.standard.data(forKey:CommanderConfiguration.defaultsKey)==persistedBefore,"Non-persistent UI fixture never writes user settings")
        let afterApplyHidden=descendants(window.contentView!).compactMap{$0 as? NSButton}.first{$0.title=="Show hidden files"}!
        afterApplyHidden.state = .off
        let cancel=descendants(window.contentView!).compactMap{$0 as? NSButton}.first{$0.title=="Cancel"}!
        cancel.performClick(nil)
        try check(commander.runtimeConfig.showHidden && commander.applied==1,"Cancel discards new unapplied changes")
        let resetController=PreferencesController(commander),resetWindow=resetController.window!
        let resetNavigation=descendants(resetWindow.contentView!).compactMap{$0 as? NSTableView}.first!
        resetNavigation.selectRowIndexes(IndexSet(integer:5),byExtendingSelection:false)
        resetNavigation.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false)
        let restore=descendants(resetWindow.contentView!).compactMap{$0 as? NSButton}.first{$0.title=="Restore defaults"}!
        restore.performClick(nil)
        let resetHidden=descendants(resetWindow.contentView!).compactMap{$0 as? NSButton}.first{$0.title=="Show hidden files"}!
        try check(resetHidden.state == .off,"Restore defaults rebuilds the active category")
        resetNavigation.selectRowIndexes(IndexSet(integer:5),byExtendingSelection:false)
        let resetSize=descendants(resetWindow.contentView!).compactMap{$0 as? NSPopUpButton}.first{$0.itemTitles.contains("Fixed MB (native addition)")}!
        try check(resetSize.titleOfSelectedItem=="bytes","Restore defaults discards previously cached category values")
        resetController.close()
        print("PASS: \(checks) configuration UI assertions")
    }
}
