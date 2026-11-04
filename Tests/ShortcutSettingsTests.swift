import Foundation
@main struct ShortcutSettingsTests {
    static var checks=0
    static func check(_ condition:@autoclosure ()throws->Bool,_ message:String)throws{checks += 1;guard try condition() else{throw ShortcutSettings.failure(message)}}
    static func rejects(_ message:String,_ action:()throws->Void)throws{do{try action()}catch{checks += 1;return};throw ShortcutSettings.failure("Expected rejection: "+message)}
    static func main()throws{
        let defaults=try ShortcutSettings.parse(shortcuts:"",aliases:"")
        try check(defaults.bindings.isEmpty && defaults.aliases.isEmpty,"Empty settings retain defaults")
        let settings=try ShortcutSettings.parse(shortcuts:"Ctrl+Shift+C=cm_CopyFullNamesToClip; Alt+F3=cm_List; Command+Return=cm_SrcLong",aliases:"ll=cm_SrcLong; vv=cm_List")
        try check(settings.bindings[try ShortcutChord.parse("Control+Shift+c")]=="cm_copyfullnamestoclip","Case-insensitive canonical modifiers and keys")
        try check(settings.bindings[try ShortcutChord.parse("Option+F3")]=="cm_list","Option is Alt")
        try check(settings.bindings[try ShortcutChord.parse("Cmd+Enter")]=="cm_srclong","Command and Enter aliases")
        try check(settings.command(forAlias:" LL ")=="cm_srclong","Exact case-insensitive command alias")
        try check(settings.command(forAlias:"ll file")==nil && settings.command(forAlias:"lll")==nil,"Alias does not expand a prefix or consume arguments")
        try check(try ShortcutChord.parse("Shift+Esc").key=="ESCAPE","Named Escape key")
        try check(try ShortcutChord.parse("F20").key=="F20","Highest supported function key")
        try check(try ShortcutChord.parse("A").modifiers.isEmpty,"Unmodified letter binding")
        try check(try ShortcutChord.parse("ctrl+alt+shift+cmd+9").modifiers == [.control,.option,.shift,.command],"All modifier combinations")
        try rejects("Duplicate shortcut aliases"){_=try ShortcutSettings.parse(shortcuts:"Ctrl+C=cm_Copy;Control+c=cm_List",aliases:"")}
        try rejects("Duplicate alias case"){_=try ShortcutSettings.parse(shortcuts:"",aliases:"ll=cm_List;LL=cm_Copy")}
        try rejects("Alias chain/cycle"){_=try ShortcutSettings.parse(shortcuts:"",aliases:"a=b;b=a")}
        try rejects("Shell command"){_=try ShortcutSettings.parse(shortcuts:"F2=rm -rf /",aliases:"")}
        try rejects("Unknown original command"){_=try ShortcutSettings.parse(shortcuts:"F2=cm_NotImplemented",aliases:"")}
        try rejects("Alias shadows internal command"){_=try ShortcutSettings.parse(shortcuts:"",aliases:"cm_List=cm_Copy")}
        try rejects("Alias contains spaces"){_=try ShortcutSettings.parse(shortcuts:"",aliases:"two words=cm_List")}
        try rejects("Command arguments not silently dropped"){_=try ShortcutSettings.parse(shortcuts:"F2=cm_List file",aliases:"")}
        try rejects("Missing command"){_=try ShortcutSettings.parse(shortcuts:"F2=",aliases:"")}
        try rejects("Multiple equals"){_=try ShortcutSettings.parse(shortcuts:"F2==cm_List",aliases:"")}
        try rejects("Repeated modifier"){_=try ShortcutChord.parse("Ctrl+Control+A")}
        try rejects("Unknown modifier"){_=try ShortcutChord.parse("Hyper+A")}
        try rejects("Unknown key"){_=try ShortcutChord.parse("Ctrl+F21")}
        try rejects("Blank chord"){_=try ShortcutChord.parse("")}
        try rejects("Bounded config"){_=try ShortcutSettings.parse(shortcuts:String(repeating:"a",count:16385),aliases:"")}
        let multiline=try ShortcutSettings.parse(shortcuts:"F2=cm_RereadSource\nF3=cm_List",aliases:"new-folder=cm_MkDir")
        try check(multiline.bindings.count==2 && multiline.command(forAlias:"new-folder")=="cm_mkdir","Multiline lists and hyphenated aliases")
        print("PASS: \(checks) shortcut settings assertions")
    }
}
