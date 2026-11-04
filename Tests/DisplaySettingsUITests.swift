import AppKit

final class CommanderController:NSObject {
    var runtimeConfig=CommanderConfiguration(),showHidden=false
    let remember=false
    var applied=0
    func applyConfiguration(_ value:CommanderConfiguration){runtimeConfig=value;showHidden=value.showHidden;applied += 1}
    func refresh(){}
}
@main struct DisplaySettingsUITests {
    static var checks=0
    static func check(_ value:@autoclosure()throws->Bool,_ message:String)throws {checks += 1;if try !value(){throw NSError(domain:"DisplaySettingsUITests",code:checks,userInfo:[NSLocalizedDescriptionKey:message])}}
    static func descendants(_ view:NSView)->[NSView]{[view]+view.subviews.flatMap(descendants)}
    static func field(_ view:NSView,_ label:String)->NSTextField {descendants(view).compactMap{$0 as? NSTextField}.first{$0.accessibilityLabel()==label}!}
    static func popup(_ view:NSView,_ label:String)->NSPopUpButton {descendants(view).compactMap{$0 as? NSPopUpButton}.first{$0.accessibilityLabel()==label}!}
    static func checkBox(_ view:NSView,_ title:String)->NSButton {descendants(view).compactMap{$0 as? NSButton}.first{$0.title==title}!}
    static func action<T>(_ editor:DisplaySettingsListEditor<T>,_ title:String){let buttons=editor.arrangedSubviews[1] as! NSStackView;(buttons.arrangedSubviews.compactMap{$0 as? NSButton}.first{$0.title==title}!).performClick(nil)}
    static func main()throws {
        _=NSApplication.shared
        let before=UserDefaults.standard.data(forKey:CommanderConfiguration.defaultsKey),commander=CommanderController(),preferences=PreferencesController(commander)
        preferences.selectPage(index:6)
        let root=preferences.window!.contentView!
        let sets=descendants(root).compactMap{$0 as? DisplaySettingsListEditor<CustomColumnSet>}.first!
        action(sets,"New")
        field(sets,"Set name").stringValue="Documents"
        let columns=descendants(sets).compactMap{$0 as? DisplaySettingsListEditor<CustomColumnDefinition>}.first!
        field(columns,"Caption").stringValue="Length"
        field(columns,"Field contents").stringValue="[=tc.size.kbytes]"
        popup(columns,"Align").selectItem(withTitle:"Right")
        action(columns,"New")
        field(columns,"Caption").stringValue="Modified"
        field(columns,"Field contents").stringValue="[=tc.writedate]"
        action(columns,"Up")
        let editedSets=try sets.values()
        try check(editedSets[0].columns.map(\.title)==["Modified","Length"],"Column ordering is collected from actual editor buttons")
        try check(editedSets[0].columns[1].alignment == .right,"Column alignment survives selection changes")
        checkBox(root,"Use the selected set as the default columns").state = .on
        preferences.selectPage(index:7)
        let modes=descendants(root).compactMap{$0 as? DisplaySettingsListEditor<CommanderViewMode>}.first!
        action(modes,"New")
        field(modes,"Mode name").stringValue="Documents mode"
        popup(modes,"Columns view").selectItem(withTitle:"Full")
        popup(modes,"Custom column set").selectItem(withTitle:"Documents")
        popup(modes,"Sort order").selectItem(withTitle:"Size")
        popup(modes,"Direction").selectItem(withTitle:"Descending")
        field(modes,"Additional sort columns").stringValue="ext;-name"
        field(modes,"Tab icon (SF Symbol)").stringValue="doc"
        field(modes,"Auto-run commands").stringValue="cm_100percent|cm_50percent"
        checkBox(modes,"Override alternate background").state = .on
        preferences.selectPage(index:8)
        let rules=descendants(root).compactMap{$0 as? DisplaySettingsListEditor<CommanderAutoSwitchRule>}.first!
        action(rules,"New")
        field(rules,"Rule name").stringValue="Text files"
        popup(rules,"Switch to view mode").selectItem(withTitle:"Documents mode")
        let conditions=descendants(rules).compactMap{$0 as? DisplaySettingsListEditor<CommanderViewCondition>}.first!
        popup(conditions,"Condition").selectItem(withTitle:"Files matching mask")
        field(conditions,"Path or file masks").stringValue="*.txt"
        popup(conditions,"File matching policy").selectItem(withTitle:"At least half")
        action(conditions,"New")
        popup(conditions,"Condition").selectItem(withTitle:"Local filesystem")
        popup(conditions,"Join with previous condition").selectItem(withTitle:"AND")
        checkBox(root,"Automatically switch view mode on directory change").state = .on
        try preferences.applyDraft()
        let saved=commander.runtimeConfig
        try check(saved.customColumnSets.count==1 && saved.customColumnSets[0].name=="Documents","Custom-column form applies through the actual preferences controller")
        try check(saved.activeCustomColumnSetID==saved.customColumnSets[0].id,"Default column-set control applies the selected set")
        try check(saved.viewModes[0].customColumnSetID==saved.customColumnSets[0].id && saved.viewModes[0].columnsView == .full,"Mode references newly created custom set across pages")
        try check(saved.viewModes[0].ascending==false && saved.viewModes[0].secondarySortColumns==["ext","-name"],"Mode sort controls are collected")
        try check(saved.viewModes[0].alternatingBackground != nil && saved.viewModes[0].tabIcon=="doc" && saved.viewModes[0].autoRunCommands=="cm_100percent|cm_50percent","Colors, icons and autorun fields are collected")
        try check(saved.autoSwitchEnabled && saved.autoSwitchRules[0].viewModeID==saved.viewModes[0].id,"Automatic-rule control refers to saved mode")
        try check(saved.autoSwitchRules[0].conditions.count==2 && saved.autoSwitchRules[0].conditions[0].fileMatch == .half && saved.autoSwitchRules[0].conditions[1].conjunction == .all,"Actual condition controls preserve policies and conjunction")
        preferences.selectPage(index:7)
        let currentModes=descendants(root).compactMap{$0 as? DisplaySettingsListEditor<CommanderViewMode>}.first!
        action(currentModes,"Delete")
        try check(try currentModes.values().count==1,"Referenced view-mode deletion is refused")
        try check(currentModes.errorLabel.stringValue.contains("automatic switching rule"),"Reference failure is explained inline")
        preferences.selectPage(index:6)
        let currentSets=descendants(root).compactMap{$0 as? DisplaySettingsListEditor<CustomColumnSet>}.first!
        action(currentSets,"Delete")
        try check(try currentSets.values().count==1,"Referenced column-set deletion is refused")
        action(currentSets,"Copy")
        try check(try currentSets.values().count==2,"Copy creates a separate draft set")
        action(currentSets,"Delete")
        try check(try currentSets.values().count==1,"Unreferenced copy can be deleted")
        let currentColumns=descendants(currentSets).compactMap{$0 as? DisplaySettingsListEditor<CustomColumnDefinition>}.first!
        field(currentColumns,"Field contents").stringValue="[=missingplugin.secret]"
        var invalid=false;do{try preferences.applyDraft()}catch{invalid=true}
        try check(invalid && commander.runtimeConfig==saved,"Unsupported field blocks Apply and preserves runtime state")
        preferences.close()
        try check(commander.applied==1,"Closing the edited dialog discards invalid/unapplied drafts")
        try check(UserDefaults.standard.data(forKey:CommanderConfiguration.defaultsKey)==before,"Nonpersistent UI test leaves personal preferences unchanged")
        print("PASS: \(checks) display-settings UI assertions")
    }
}
