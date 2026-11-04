import AppKit
@main struct KeybindingsEditorTests {
    static func main()throws {
        let app=NSApplication.shared;app.setActivationPolicy(.prohibited)
        var count=0
        func check(_ value:Bool,_ message:String){count += 1;precondition(value,message)}
        let editor=KeybindingsEditor(shortcuts:"Ctrl+Shift+B=cm_SrcShort")
        check(editor.bindings.count==1,"Existing overrides visible")
        check(try ShortcutSettings.parse(shortcuts:editor.serializedBindings(),aliases:"").bindings.count==1,"Existing overrides roundtrip")
        editor.keyField.stringValue="Alt+F2";editor.commandField.stringValue="cm_SrcLong";try editor.stageBinding()
        check(editor.bindings.count==2,"Assign stages another override")
        editor.table.deselectAll(nil)
        editor.keyField.stringValue="Ctrl+Shift+B";editor.commandField.stringValue="cm_Copy"
        do{try editor.stageBinding();check(false,"Conflict must reject")}catch{check(editor.bindings.count==2,"Conflict keeps prior assignments")}
        let row=editor.bindings.firstIndex{$0.chord==(try! ShortcutChord.parse("Ctrl+Shift+B"))}!
        editor.table.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)
        editor.commandField.stringValue="cm_Copy";try editor.stageBinding()
        check(editor.bindings.first{$0.chord==(try! ShortcutChord.parse("Ctrl+Shift+B"))}?.command=="cm_copy","Selected existing binding can be reassigned")
        editor.keyField.stringValue="NoSuchModifier+Q";do{try editor.stageBinding();check(false,"Invalid key")}catch{check(true,"Invalid key rejected")}
        editor.keyField.stringValue="Ctrl+Q";editor.commandField.stringValue="/bin/sh"
        do{try editor.stageBinding();check(false,"Unsupported command")}catch{check(true,"External command rejected")}
        let event=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[.control,.option],timestamp:0,windowNumber:0,context:nil,characters:"b",charactersIgnoringModifiers:"b",isARepeat:false,keyCode:11)!
        editor.capture.keyDown(with:event)
        check(editor.keyField.stringValue=="Ctrl+Alt+B","Recorded chord uses actual key and modifiers")
        let previous=editor.keyField.stringValue
        let escape=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:53)!
        editor.capture.keyDown(with:escape);check(editor.keyField.stringValue==previous,"Capture Escape cancels without changing shortcut")
        editor.search.stringValue="dark";editor.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification,object:editor.search))
        check(editor.commandField.numberOfItems==3,"Search filters available native commands")
        editor.table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false);editor.remove();check(editor.bindings.count==1,"Remove only selected override")
        editor.resetOverrides();check(try editor.serializedBindings().isEmpty,"Reset returns built-in behavior without saves")
        let invalid=KeybindingsEditor(shortcuts:"broken")
        do{_=try invalid.serializedBindings();check(false,"Malformed persisted bindings not silently discarded")}catch{check(true,"Invalid initial definition must be corrected")}
        invalid.resetOverrides();check(try invalid.serializedBindings().isEmpty,"Explicit reset can recover invalid data")
        editor.newBinding();editor.keyField.stringValue="Ctrl+K";editor.commandField.stringValue="cm_Copy"
        check(try ShortcutSettings.parse(shortcuts:editor.serializedBindings(),aliases:"").bindings.count==1,"Apply stages valid pending fields")
        editor.newBinding();editor.keyField.stringValue="Ctrl+J";editor.commandField.stringValue="cm_Edit";try editor.stageBinding()
        check(editor.bindings.count==2,"New binding never replaces the previously selected row")
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:600,height:500),styleMask:[.titled],backing:.buffered,defer:false);window.contentView=editor
        editor.startRecording()
        let equivalent=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[.command],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"w",charactersIgnoringModifiers:"w",isARepeat:false,keyCode:13)!
        check(editor.capture.performKeyEquivalent(with:equivalent) && editor.keyField.stringValue=="Cmd+W","Active recorder captures command equivalents without window action")
        check(!editor.capture.performKeyEquivalent(with:equivalent),"Inactive recorder does not steal shortcuts")
        print("PASS: \(count) keybindings editor assertions")
    }
}
