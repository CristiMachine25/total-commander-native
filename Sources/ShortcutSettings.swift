import Foundation

struct ShortcutChord: Hashable {
    struct Modifiers: OptionSet, Hashable {
        let rawValue: Int
        static let control=Modifiers(rawValue:1),option=Modifiers(rawValue:2),shift=Modifiers(rawValue:4),command=Modifiers(rawValue:8)
    }
    let key:String
    let modifiers:Modifiers
    static let namedKeys:Set<String>=["SPACE","RETURN","TAB","ESCAPE","BACKSPACE","DELETE","INSERT","HOME","END","PAGEUP","PAGEDOWN","LEFT","RIGHT","UP","DOWN","PLUS","MINUS","EQUAL","COMMA","PERIOD","SLASH","BACKSLASH","LEFTBRACKET","RIGHTBRACKET","APOSTROPHE","SEMICOLON","GRAVE"]
    static func canonicalKey(_ text:String)->String? {
        let value=text.uppercased()
        let synonyms=["ENTER":"RETURN","ESC":"ESCAPE","DEL":"DELETE","INS":"INSERT","PGUP":"PAGEUP","PGDN":"PAGEDOWN","PGDOWN":"PAGEDOWN","ARROWLEFT":"LEFT","ARROWRIGHT":"RIGHT","ARROWUP":"UP","ARROWDOWN":"DOWN"]
        if let synonym=synonyms[value]{return synonym}
        if namedKeys.contains(value){return value}
        if value.count==1,let scalar=value.unicodeScalars.first,CharacterSet(charactersIn:"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789").contains(scalar){return value}
        if value.hasPrefix("F"),let n=Int(value.dropFirst()),(1...20).contains(n){return "F"+String(n)}
        return nil
    }
    static func parse(_ text:String)throws->ShortcutChord {
        let pieces=text.split(separator:"+",omittingEmptySubsequences:false).map{$0.trimmingCharacters(in:.whitespacesAndNewlines)}
        guard let last=pieces.last,let key=canonicalKey(last) else{throw ShortcutSettings.failure("Unknown key in ‘\(text)’. Use a letter, number, F1–F20, or a named key such as Space, Return or Left.")}
        var modifiers:Modifiers=[]
        for piece in pieces.dropLast() {
            let flag:Modifiers
            switch piece.lowercased(){case "ctrl","control":flag = .control;case "alt","option","opt":flag = .option;case "shift":flag = .shift;case "cmd","command","super":flag = .command;default:throw ShortcutSettings.failure("Unknown modifier ‘\(piece)’ in ‘\(text)’.")}
            guard !modifiers.contains(flag) else{throw ShortcutSettings.failure("Repeated modifier in ‘\(text)’.")};modifiers.insert(flag)
        }
        return ShortcutChord(key:key,modifiers:modifiers)
    }
}

/// Data-only configuration parser. Aliases point directly to native commands;
/// no shell text, positional arguments, recursive expansion or plugin loading.
struct ShortcutSettings {
    let bindings:[ShortcutChord:String]
    let aliases:[String:String]
    // Explicit dispatch-capability snapshot. Unknown original commands are rejected,
    // not accepted as placeholders or treated as shell commands.
    static let supportedCommands:Set<String>=Set("""
cm_switchdarkmode cm_enabledarkmode cm_disabledarkmode
cm_srccustomviewmenu cm_srcviewmodelist cm_customcolumnconfig cm_customcolumndlg cm_configviewmodes cm_configviewmodeswitch cm_toggleautoviewmodeswitch
cm_about cm_buttonconfig cm_clearall cm_closealltabs cm_closecurrenttab
cm_combine cm_comparedirs cm_comparefilesbycontent cm_config cm_configchangeinifiles
cm_configsavepos cm_configsavesettings cm_copy cm_copyfiledetailstoclip cm_copyfpfiledetailstoclip
cm_copyfullnamestoclip cm_copynamestoclip cm_copyotherpanel cm_copytoarchive cm_copytoclipboard
cm_crccheck cm_crccreate cm_delete cm_directoryhotlist cm_edit
cm_editexistingfile cm_editnewfile cm_exchange cm_exchangeselection cm_exit
cm_filesync cm_ftpconnect cm_ftpdisconnect cm_ftphiddenfiles cm_ftpnew
cm_getfilespace cm_gotonextdir cm_gotopreviousdir cm_keyboard cm_list
cm_listinternalonly cm_listonly cm_loadselectionfromfile cm_matchsrc cm_mkdir
cm_multirenamefiles cm_opendesktop cm_opennewtab cm_packfiles cm_pastefromclipboard
cm_quit cm_renamesinglefile cm_renmov cm_rereadsource cm_restoreselection
cm_saveselection cm_saveselectiontofile cm_searchfor cm_selectall cm_selectcurrentextension
cm_separatetree1 cm_separatetree2 cm_separatetreeoff cm_showonlyselected cm_shrinkselection
cm_split cm_spreadselection cm_srcallfiles cm_srcbydatetime cm_srcbyext
cm_srcbyname cm_srcbysize cm_srcexecs cm_srclong cm_srcnegorder
cm_srcquickview cm_srcshort cm_srcthumbs cm_srctree cm_srcunsorted
cm_srcuserdef cm_srcuserspec cm_testarchive cm_unpackfiles cm_versioninfo
cm_verticalpanels cm_visithomepage
""".split(whereSeparator:{$0.isWhitespace}).map(String.init)).union((1...29).map{"cm_srccustomview"+String($0)}).union((0...249).map{"cm_srcviewmode"+String($0)})
    static func failure(_ text:String)->NSError{NSError(domain:"ShortcutSettings",code:1,userInfo:[NSLocalizedDescriptionKey:text])}
    static func validate(shortcuts:String,aliases:String)throws{_=try parse(shortcuts:shortcuts,aliases:aliases)}
    static func parse(shortcuts:String,aliases:String)throws->ShortcutSettings {
        guard shortcuts.utf8.count<=16384,aliases.utf8.count<=16384 else{throw failure("Shortcut and alias lists are limited to 16 KiB each.")}
        func pairs(_ text:String)throws->[(String,String)] {
            try text.split(whereSeparator:{$0==";" || $0=="\n"}).filter{!$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}.map {piece in
                let parts=piece.split(separator:"=",omittingEmptySubsequences:false).map{$0.trimmingCharacters(in:.whitespacesAndNewlines)}
                guard parts.count==2,!parts[0].isEmpty,!parts[1].isEmpty else{throw failure("Use name=cm_Command for each binding; separate bindings with semicolons.")}
                let command=parts[1].lowercased()
                guard supportedCommands.contains(command) else{throw failure("Unsupported native command ‘\(parts[1])’. Alias chains, external commands and parameters are not supported.")}
                return (parts[0],command)
            }
        }
        var bindings:[ShortcutChord:String]=[:],aliasMap:[String:String]=[:]
        for (name,command) in try pairs(shortcuts) {
            let chord=try ShortcutChord.parse(name)
            guard bindings[chord]==nil else{throw failure("Shortcut ‘\(name)’ is assigned more than once.")};bindings[chord]=command
        }
        for (name,command) in try pairs(aliases) {
            let alias=name.lowercased()
            guard !alias.hasPrefix("cm_"),alias.unicodeScalars.allSatisfy({CharacterSet(charactersIn:"abcdefghijklmnopqrstuvwxyz0123456789_-").contains($0)}),alias.first?.isLetter==true else{throw failure("Alias ‘\(name)’ must begin with a letter and contain only letters, numbers, - or _. Do not use the cm_ prefix.")}
            guard aliasMap[alias]==nil else{throw failure("Alias ‘\(name)’ is assigned more than once.")};aliasMap[alias]=command
        }
        return ShortcutSettings(bindings:bindings,aliases:aliasMap)
    }
    func command(forAlias text:String)->String?{aliases[text.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()]}
}
