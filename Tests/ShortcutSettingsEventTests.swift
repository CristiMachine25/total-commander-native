import AppKit
@main struct ShortcutSettingsEventTests {
    static var checks=0
    static func check(_ condition:Bool,_ message:String){checks += 1;precondition(condition,message)}
    static func event(_ code:UInt16,_ text:String,_ flags:NSEvent.ModifierFlags)->NSEvent {
        NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:0,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:code)!
    }
    static func main()throws {
        _=NSApplication.shared
        let settings=try ShortcutSettings.parse(shortcuts:"Ctrl+Shift+C=cm_CopyFullNamesToClip;Option+F3=cm_List;Cmd+Return=cm_SrcLong;Space=cm_ExchangeSelection",aliases:"")
        check(settings.bindings[ShortcutChord(event:event(8,"C",[.control,.shift,.capsLock]))!]=="cm_copyfullnamestoclip","Real key event maps Ctrl Shift C and ignores Caps Lock")
        check(settings.bindings[ShortcutChord(event:event(99,"",[.option,.function]))!]=="cm_list","Function-key event ignores Fn flag")
        check(settings.bindings[ShortcutChord(event:event(36,"\r",[.command]))!]=="cm_srclong","Return event dispatch key")
        check(settings.bindings[ShortcutChord(event:event(49," ",[]))!]=="cm_exchangeselection","Space event dispatch key")
        check(settings.bindings[ShortcutChord(event:event(8,"c",[.control]))!]==nil,"Extra modifiers required exactly")
        check(ShortcutChord(event:event(0,"é",[]))==nil,"Unsupported character does not hijack text")
        check(ShortcutChord(event:event(123,"",[.command]))==ShortcutChord(key:"LEFT",modifiers:.command),"Arrow key recognized by keycode")
        check(ShortcutChord(event:event(115,"",[]))?.key=="HOME","Home key recognized")
        check(ShortcutChord(event:event(44,"/",[.control]))?.key=="SLASH","Punctuation named key")
        print("PASS: \(checks) shortcut key-event assertions")
    }
}
