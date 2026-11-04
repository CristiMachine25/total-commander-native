import Foundation

struct CommanderBarItem: Codable, Equatable {
    var title: String
    var command: String
    var parameters = ""
    var directory = ""
    var icon = ""
    var separator = false
}
struct CommanderButtonBar: Codable, Equatable {
    static let defaultsKey = "commander.buttonBar.v1"
    var version = 1
    var iconSize = 22
    var showLabels = false
    var items: [CommanderBarItem] = Self.defaultItems
    static let defaultItems: [CommanderBarItem] = [
        .init(title:"Refresh",command:"cm_RereadSource",icon:"Refresh"),
        .init(title:"Brief",command:"cm_SrcShort",icon:"Brief"),
        .init(title:"Full",command:"cm_SrcLong",icon:"Full"),
        .init(title:"Invert",command:"cm_ExchangeSelection",icon:"Invert"),
        .init(title:"Back",command:"cm_GoToPreviousDir",icon:"Back"),
        .init(title:"Forward",command:"cm_GoToNextDir",icon:"Forward"),
        .init(title:"Pack",command:"cm_PackFiles",icon:"Pack"),
        .init(title:"Unpack",command:"cm_UnpackFiles",icon:"Unpack"),
        .init(title:"FTP",command:"cm_FtpConnect",icon:"FTP"),
        .init(title:"FTPNew",command:"cm_FtpNew",icon:"FTPNew"),
        .init(title:"Search",command:"cm_SearchFor",icon:"Search"),
        .init(title:"Rename",command:"cm_MultiRenameFiles",icon:"Rename"),
        .init(title:"Synchronize directories",command:"cm_FileSync",icon:"Compare"),
        .init(title:"CopyNames",command:"cm_CopyFullNamesToClip",icon:"CopyNames")
    ]
    static let extraCommands = ["cm_List","cm_Edit","cm_Copy","cm_RenMov","cm_MkDir","cm_Delete","cm_ButtonConfig"]
    static var nativeCommands: Set<String> {Set((defaultItems.map(\.command)+extraCommands).map{$0.lowercased()})}
    static func failure(_ message:String)->NSError {NSError(domain:"ButtonBar",code:1,userInfo:[NSLocalizedDescriptionKey:message])}
    func validate() throws {
        guard version==1,(16...48).contains(iconSize),items.count<=200 else {throw Self.failure("Use 16–48 pixel icons and at most 200 buttons.")}
        for item in items where !item.separator {
            guard !item.title.trimmingCharacters(in:.whitespaces).isEmpty,!item.command.isEmpty else {throw Self.failure("Every button needs a tooltip and a command.")}
            guard item.command.lowercased().hasPrefix("cm_") || item.command.hasPrefix("/") || item.command.hasPrefix("~/") else {throw Self.failure("Choose an internal cm_ command or an absolute Mac program, application or folder path.")}
            if !item.directory.isEmpty, !item.directory.hasPrefix("/"), !item.directory.hasPrefix("~/") {throw Self.failure("Start path must be an absolute Mac folder path.")}
            _ = try Self.arguments(item.parameters)
        }
    }
    func save(to defaults:UserDefaults = .standard)throws {try validate();defaults.set(try JSONEncoder().encode(self),forKey:Self.defaultsKey)}
    static func load(from defaults:UserDefaults = .standard)->Self {
        guard let data=defaults.data(forKey:defaultsKey),let value=try? JSONDecoder().decode(Self.self,from:data),(try? value.validate()) != nil else{return Self()};return value
    }
    /// Quotes group arguments. No shell expansion or file-name interpolation occurs.
    static func arguments(_ text:String)throws->[String] {
        var result:[String]=[],word="",quote:Character?,escaped=false,started=false
        for char in text {
            if escaped {word.append(char);escaped=false;started=true;continue}
            if char=="\\",quote != "'" {escaped=true;started=true;continue}
            if let current=quote {if char==current{quote=nil}else{word.append(char)};continue}
            if char=="\"" || char=="'" {quote=char;started=true;continue}
            if char.isWhitespace {if started {result.append(word);word="";started=false}} else {word.append(char);started=true}
        }
        guard quote==nil,!escaped else{throw failure("Parameters contain an unfinished quote or backslash.")}
        if started {result.append(word)};return result
    }
}
