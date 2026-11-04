import AppKit
@main struct KeybindingsEditorTests {
    static func main()throws {
        let app=NSApplication.shared;app.setActivationPolicy(.prohibited)
        var count=0
        func check(_ value:Bool,_ message:String){count += 1;precondition(value,message)}
        func select(_ editor:KeybindingsEditor,_ command:String){let index=editor.visibleCommands.firstIndex(of:command)!;editor.table.selectRowIndexes(IndexSet(integer:index),byExtendingSelection:false)}
        func parsed(_ editor:KeybindingsEditor)throws->[ShortcutChord:String]{try ShortcutSettings.parse(shortcuts:editor.serializedBindings(),aliases:editor.aliasField.stringValue).bindings}
        let editor=KeybindingsEditor(shortcuts:"Ctrl+Shift+B=cm_SrcShort;Ctrl+J=cm_SrcShort",aliases:"brief=cm_SrcShort")
        check(editor.bindings.count==2,"Existing multiple overrides retained")
        check(try parsed(editor).count==2,"Existing overrides roundtrip")
        check(editor.aliasField.stringValue=="brief=cm_SrcShort" && editor.advanced.isHidden,"Aliases preserved in collapsed advanced area")
        check(editor.visibleCommands.count>80 && KeybindingActions.title("cm_copy")=="Copy files","Readable action list exists before any overrides")
        check(!KeybindingActions.commands.contains(where:{KeybindingActions.title($0).hasPrefix("cm_")}),"Every supported action has readable label")
        check(editor.shortcutSummary(for:"cm_copy")=="F5","Actual copy default visible")
        check(editor.shortcutSummary(for:"cm_srcshort").contains("Ctrl+F1") && editor.shortcutSummary(for:"cm_srcshort").contains("Ctrl+J *"),"Defaults and custom shortcuts distinguished")
        check(!editor.recordButton.isEnabled,"Recording requires an action")
        select(editor,"cm_copy");check(editor.recordButton.isEnabled && editor.commandField.stringValue=="cm_copy","Selecting readable action chooses command")
        editor.keyField.stringValue="Alt+F13";try editor.stageBinding()
        check(editor.bindings.count==3,"Recording adds without discarding other bindings")
        editor.keyField.stringValue="Ctrl+Shift+B";editor.commandField.stringValue="cm_Copy"
        do{try editor.stageBinding();check(false,"Conflict must reject")}catch{check(editor.bindings.count==3 && !editor.replaceButton.isHidden && editor.feedback.stringValue.isEmpty==false,"Conflict keeps prior assignments until explicit replace")}
        do{_=try editor.serializedBindings();check(false,"Unresolved conflict must block Apply")}catch{check(true,"Unresolved conflict blocks Apply")}
        editor.replaceConflict()
        check(try parsed(editor)[ShortcutChord.parse("Ctrl+Shift+B")]=="cm_copy","Explicit replacement changes only chosen chord")
        check(try parsed(editor)[ShortcutChord.parse("Ctrl+J")]=="cm_srcshort","Other binding for previous action preserved")
        select(editor,"cm_edit");editor.keyField.stringValue="F5"
        do{try editor.stageBinding();check(false,"Built-in conflict must reject")}catch{check(!editor.replaceButton.isHidden,"Built-in conflict requires confirmation")}
        editor.replaceConflict();check(editor.shortcutSummary(for:"cm_copy").contains("F5")==false,"Overridden built-in no longer displayed for old action")
        check(editor.shortcutSummary(for:"cm_edit").contains("F5 *"),"Overridden built-in displayed on new action")
        select(editor,"cm_copy");editor.restoreDefault()
        check(editor.shortcutSummary(for:"cm_copy")=="F5" && !editor.bindings.contains{$0.chord==(try! ShortcutChord.parse("F5"))},"Restore default removes conflicting override and action custom bindings")
        check(editor.bindings.count==1 && editor.bindings[0].command=="cm_srcshort","Restore preserves unrelated bindings")
        select(editor,"cm_edit");editor.keyField.stringValue="Space"
        do{try editor.stageBinding();check(false,"Context default conflict must reject")}catch{check(!editor.replaceButton.isHidden,"Context-only builtin collision detected")}
        select(editor,"cm_srcshort")
        check(try parsed(editor).count==1,"Selecting another action cancels unresolved capture without modifying bindings")
        editor.keyField.stringValue="NoSuchModifier+Q";do{try editor.stageBinding();check(false,"Invalid key")}catch{check(true,"Invalid modifier rejected")}
        editor.keyField.stringValue="Ctrl+K";editor.commandField.stringValue="/bin/sh"
        do{try editor.stageBinding();check(false,"Unsupported command")}catch{check(true,"External command rejected")}
        select(editor,"cm_edit")
        let event=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[.control,.option],timestamp:0,windowNumber:0,context:nil,characters:"b",charactersIgnoringModifiers:"b",isARepeat:false,keyCode:11)!
        editor.capture.keyDown(with:event)
        check(editor.keyField.stringValue=="Ctrl+Alt+B" && editor.bindings.contains{$0.command=="cm_edit" && $0.chord==(try! ShortcutChord.parse("Ctrl+Alt+B"))},"Recorded event stages shortcut for selected action")
        let previous=try editor.serializedBindings()
        let escape=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:53)!
        editor.capture.keyDown(with:escape);check(try editor.serializedBindings()==previous,"Capture Escape preserves binding")
        editor.search.stringValue="dark";editor.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification,object:editor.search))
        check(Set(editor.visibleCommands)==Set(["cm_switchdarkmode","cm_enabledarkmode","cm_disabledarkmode"]),"Search filters readable actions")
        editor.search.stringValue="F5";editor.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification,object:editor.search))
        check(editor.visibleCommands.contains("cm_copy"),"Search finds current shortcut")
        editor.search.stringValue="";editor.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification,object:editor.search))
        select(editor,"cm_edit");editor.keyField.stringValue="Ctrl+Alt+B";editor.remove()
        check(editor.bindings.count==1,"Advanced remove affects only chosen custom chord")
        editor.resetOverrides();check(try editor.serializedBindings().isEmpty,"Reset returns builtin behavior without preferences writes")
        let invalid=KeybindingsEditor(shortcuts:"broken")
        do{_=try invalid.serializedBindings();check(false,"Malformed persisted bindings not silently discarded")}catch{check(true,"Invalid initial definition blocks Apply")}
        invalid.resetOverrides();check(try invalid.serializedBindings().isEmpty,"Explicit reset recovers invalid data")
        select(editor,"cm_copy");editor.keyField.stringValue="Ctrl+K"
        check(try parsed(editor).count==1,"Apply collects pending advanced field edits")
        editor.keyField.stringValue="Ctrl+J";try editor.stageBinding()
        check(editor.bindings.count==2,"Additional assignment preserves other shortcut for same action")
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:600,height:600),styleMask:[.titled],backing:.buffered,defer:false);window.contentView=editor
        editor.startRecording()
        let equivalent=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[.command],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"w",charactersIgnoringModifiers:"w",isARepeat:false,keyCode:13)!
        check(editor.capture.performKeyEquivalent(with:equivalent) && editor.keyField.stringValue=="Cmd+W","Active recorder captures command equivalents without window action")
        check(!editor.capture.performKeyEquivalent(with:equivalent),"Inactive recorder leaves shortcuts alone")
        editor.aliasField.stringValue="bad=/bin/sh"
        do{_=try editor.serializedBindings();check(false,"Invalid alias blocks Apply")}catch{check(true,"Advanced aliases remain validated")}
        let aliases=KeybindingsEditor(shortcuts:"Ctrl+K=cm_CopyOtherPanel;Ctrl+J=cm_Copy")
        check(aliases.shortcutSummary(for:"cm_copy").contains("Ctrl+K *") && aliases.shortcutSummary(for:"cm_copy").contains("Ctrl+J *"),"Equivalent commands share one action while preserving all bindings")
        check(try parsed(aliases)[ShortcutChord.parse("Ctrl+K")]=="cm_copyotherpanel","Original alias command identifier preserved on roundtrip")
        let profiles=KeybindingsEditor(shortcuts:"Ctrl+K=cm_SrcViewMode23")
        check(profiles.visibleCommands.contains("cm_srcviewmode23") && !profiles.visibleCommands.contains("cm_srcviewmode24"),"Only bound numbered profiles appear in initial list")
        profiles.search.stringValue="View mode 24";profiles.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification,object:profiles.search))
        check(profiles.visibleCommands.contains("cm_srcviewmode24"),"Unused numbered profiles remain searchable")
        select(profiles,"cm_srcviewmode24");profiles.keyField.stringValue="Ctrl+J";try profiles.stageBinding()
        profiles.search.stringValue="Copy files";profiles.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification,object:profiles.search))
        check(profiles.selectedCommand==nil && !profiles.recordButton.isEnabled,"Filtered-out selection cannot record into an invisible action")
        check(try parsed(profiles).count==2,"Filtering preserves both staged profile bindings")
        profiles.search.stringValue="";profiles.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification,object:profiles.search))
        select(profiles,"cm_srcviewmode24");profiles.keyField.stringValue="Ctrl+J";profiles.remove()
        check(try parsed(profiles).count==1 && !profiles.visibleCommands.contains("cm_srcviewmode24"),"Removing one numbered profile binding preserves others and hides unused slot")
        check(KeybindingActions.defaults.keys.allSatisfy{ShortcutSettings.supportedCommands.contains($0)},"Every displayed default belongs to a supported command")
        print("PASS: \(count) keybindings editor assertions")
    }
}
