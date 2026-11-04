import Foundation
import CoreFoundation
import Darwin

struct ConfigurationImportReport {
    let configuration:CommanderConfiguration
    let imported:[String]
    let unsupported:[String]
    let invalid:[String]
    var summary:String {
        "Imported \(imported.count) settings; \(unsupported.count) unsupported; \(invalid.count) invalid."
    }
}

enum ConfigurationFileError:LocalizedError {
    case invalid(String)
    var errorDescription:String? {if case .invalid(let text)=self{return text};return nil}
}

/// Data-only configuration exchange. Importing never opens paths, follows INI redirects,
/// loads plugins, executes commands, or changes saved preferences.
enum ConfigurationFiles {
    static let maximumBytes=1_048_576
    static let version2Keys:Set<String> = ["tabsCloseOnDoubleClick","confirmCloseAllTabs","tabsShowLockAsterisk","customShortcuts","commandAliases","alternatingRowBackground","alternatingBackground","copyPreserveDirectoryDates","copyPreserveFileDates","copyPreservePermissions","copyVerifyAfterCopy","copyBufferSizeKB","copyDefaultCollision","confirmCopyMove","confirmOverwrite","deleteToTrash","confirmDelete","refreshOnActivate","autoRefreshEnabled","autoRefreshMetadata","autoRefreshOnlyForeground","autoRefreshExcludedPaths","autoRefreshUpdateHeader","dateSeparator","timeSeparator","use12HourTime","zipCompressionLevel","zipVerifyAfterPacking","archiveSetDateToNewest","browseArchivesAsDirectories","ftpPassiveMode","ftpConnectTimeout","ftpTransferTimeout","ftpOpenPanel"]
    static let format="total-commander-native-configuration"
    private struct Envelope:Codable {let format:String;let version:Int;let configuration:CommanderConfiguration}
    static func exportNative(_ configuration:CommanderConfiguration)throws->Data {
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        let result=try encoder.encode(Envelope(format:format,version:2,configuration:configuration.normalized()))
        guard result.count<=maximumBytes else {throw ConfigurationFileError.invalid("Configuration exceeds the 1 MiB limit.")}
        return result
    }
    static func importNative(_ data:Data)throws->CommanderConfiguration {
        guard !data.isEmpty,data.count<=maximumBytes else {throw ConfigurationFileError.invalid("Configuration must be between 1 byte and 1 MiB.")}
        guard let object=try JSONSerialization.jsonObject(with:data) as? [String:Any],
              Set(object.keys)==Set(["format","version","configuration"]),
              object["format"] as? String == format,
              let version=object["version"] as? NSNumber,CFGetTypeID(version) != CFBooleanGetTypeID(),[1.0,2.0].contains(version.doubleValue),
              object["configuration"] is [String:Any] else {
            throw ConfigurationFileError.invalid("Not a supported native configuration file (version 1 or 2).")
        }
        try rejectDuplicateKeys(data)
        let envelope=try JSONDecoder().decode(Envelope.self,from:data)
        let normalized=envelope.configuration.normalized()
        // CommanderConfiguration's persistence decoder deliberately tolerates old/malformed
        // stored keys. File import must not silently replace bad input with those defaults.
        var canonical=try JSONSerialization.jsonObject(with:exportNative(normalized)) as! [String:Any]
        if envelope.version==1 {
            var fields=canonical["configuration"] as! [String:Any]
            for key in version2Keys {fields.removeValue(forKey:key)}
            canonical["configuration"]=fields;canonical["version"]=1
        }
        guard equalJSON(object,canonical) else {
            throw ConfigurationFileError.invalid("Configuration contains missing, unknown, invalid, or out-of-range settings. No settings were changed.")
        }
        try ShortcutSettings.validate(shortcuts:normalized.customShortcuts,aliases:normalized.commandAliases)
        return normalized
    }
    private static func rejectDuplicateKeys(_ data:Data)throws {
        // JSONSerialization validates syntax but accepts duplicate keys; reject ambiguous
        // configuration objects rather than silently choosing a parser-dependent value.
        struct Context {var object:Bool;var expectsKey:Bool;var keys=Set<String>()}
        let bytes=Array(data);var stack:[Context]=[],index=0
        while index<bytes.count {
            switch bytes[index] {
            case 123:stack.append(Context(object:true,expectsKey:true))
            case 91:stack.append(Context(object:false,expectsKey:false))
            case 125,93:if !stack.isEmpty{stack.removeLast()}
            case 44:if !stack.isEmpty,stack[stack.count-1].object{stack[stack.count-1].expectsKey=true}
            case 34:
                let start=index;index+=1
                while index<bytes.count {
                    if bytes[index]==92 {index+=2;continue}
                    if bytes[index]==34{break};index+=1
                }
                if let last=stack.last,last.object,last.expectsKey {
                    let keyData=Data(bytes[start...index])
                    let key=try JSONSerialization.jsonObject(with:keyData,options:.fragmentsAllowed) as! String
                    guard !last.keys.contains(key) else{throw ConfigurationFileError.invalid("Configuration contains a duplicate JSON key. No settings were changed.")}
                    stack[stack.count-1].keys.insert(key);stack[stack.count-1].expectsKey=false
                }
            default:break
            }
            index+=1
        }
    }
    private static func equalJSON(_ a:Any,_ b:Any)->Bool {
        if let x=a as? [String:Any],let y=b as? [String:Any] {return Set(x.keys)==Set(y.keys) && x.allSatisfy{key,value in equalJSON(value,y[key]!)}}
        if let x=a as? [Any],let y=b as? [Any] {return x.count==y.count && zip(x,y).allSatisfy{equalJSON($0,$1)}}
        if let x=a as? NSNumber,let y=b as? NSNumber {return (CFGetTypeID(x)==CFBooleanGetTypeID()) == (CFGetTypeID(y)==CFBooleanGetTypeID()) && x==y}
        if let x=a as? String,let y=b as? String{return x==y}
        return a is NSNull && b is NSNull
    }
    static func writeNative(_ configuration:CommanderConfiguration,to url:URL)throws {
        // Data.atomic writes a sibling temporary file and renames it into place; an old
        // complete configuration survives failure before replacement.
        try exportNative(configuration).write(to:url,options:.atomic)
    }
    static func readData(from url:URL)throws->Data {
        let descriptor=open(url.path,O_RDONLY|O_NOFOLLOW|O_NONBLOCK)
        guard descriptor>=0 else{throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
        let handle=FileHandle(fileDescriptor:descriptor,closeOnDealloc:true);defer{try? handle.close()}
        var metadata=stat()
        guard fstat(descriptor,&metadata)==0,metadata.st_mode&S_IFMT==S_IFREG,metadata.st_size<=maximumBytes else {
            throw ConfigurationFileError.invalid("Choose a regular configuration file no larger than 1 MiB.")
        }
        let data=try handle.read(upToCount:maximumBytes+1) ?? Data()
        guard data.count<=maximumBytes else{throw ConfigurationFileError.invalid("Configuration exceeds the 1 MiB limit.")}
        return data
    }
    static func readNative(from url:URL)throws->CommanderConfiguration {try importNative(readData(from:url))}
    static func importINI(_ data:Data,merging current:CommanderConfiguration)throws->ConfigurationImportReport {
        guard !data.isEmpty,data.count<=maximumBytes else{throw ConfigurationFileError.invalid("INI file must be between 1 byte and 1 MiB.")}
        let text:String?
        if data.starts(with:[0xff,0xfe]) || data.starts(with:[0xfe,0xff]) {text=String(data:data,encoding:.utf16)}
        else {text=String(data:data,encoding:.utf8) ?? String(data:data,encoding:.windowsCP1252)}
        guard let text,!text.contains("\0") else {throw ConfigurationFileError.invalid("INI text encoding is invalid.")}
        struct Entry {let section:String;let key:String;let value:String;var label:String{"[\(section)] \(key)"}}
        var entries:[String:Entry]=[:],duplicates=Set<String>(),invalid:[String]=[],unsupported:[String]=[],imported:[String]=[]
        var section=""
        for (offset,raw) in text.replacingOccurrences(of:"\u{feff}",with:"").components(separatedBy:.newlines).enumerated() {
            let line=raw.trimmingCharacters(in:.whitespaces)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#"){continue}
            if line.hasPrefix("[") {
                guard line.hasSuffix("]"),line.count>2 else{invalid.append("Line \(offset+1): invalid section");section="";continue}
                section=String(line.dropFirst().dropLast()).trimmingCharacters(in:.whitespaces).lowercased();continue
            }
            guard !section.isEmpty,let separator=line.firstIndex(of:"=") else{invalid.append("Line \(offset+1): expected a section and key=value");continue}
            let key=String(line[..<separator]).trimmingCharacters(in:.whitespaces).lowercased()
            guard !key.isEmpty else{invalid.append("Line \(offset+1): empty key");continue}
            let e=Entry(section:section,key:key,value:String(line[line.index(after:separator)...]).trimmingCharacters(in:.whitespaces)),id=section+"\0"+key
            if entries[id] != nil {duplicates.insert(id)} else {entries[id]=e}
        }
        var result=current
        let styles:[CommanderConfiguration.SizeFormat]=[.bytes,.kilobytes,.dynamicGigabytes,.dynamicOneDecimalGigabytes,.dynamicMegabytes,.dynamicOneDecimalMegabytes,.dynamic,.dynamicOneDecimal,.dynamicTwoDecimalsGigabytes,.dynamicTwoDecimals]
        let layout:[String:WritableKeyPath<CommanderConfiguration,Bool>]=["buttonbar":\.showButtonBar,"cmdline":\.showCommandLine,"curdir":\.showCurrentDirectory,"directorytabs":\.showFolderTabs,"drivecombo":\.showDriveList,"keybuttons":\.showFunctionButtons,"statusbar":\.showStatusBar,"tabheader":\.showColumnHeaders]
        for id in entries.keys.sorted() {
            let e=entries[id]!,value=Int(e.value)
            if duplicates.contains(id){invalid.append(e.label+": duplicate key");continue}
            func bad(){invalid.append(e.label+": invalid or unsupported value")}
            func importedKey(){imported.append(e.label)}
            func boolean(_ field:WritableKeyPath<CommanderConfiguration,Bool>){guard let value,(0...1).contains(value) else{bad();return};result[keyPath:field]=value==1;importedKey()}
            if e.section=="layout",let field=layout[e.key] {boolean(field);continue}
            if e.section=="configuration" {
                switch e.key {
                case "sizestyle","sizefooter":
                    guard let value,styles.indices.contains(value) else{bad();continue}
                    if e.key=="sizestyle"{result.sizeFormat=styles[value]}else{result.footerSizeFormat=styles[value]};importedKey()
                case "sizestyle1000":boolean(\.useDecimalUnits)
                case "usetrash":boolean(\.deleteToTrash)
                case "verifycopy":boolean(\.copyVerifyAfterCopy)
                case "copydirtimestamp":boolean(\.copyPreserveDirectoryDates)
                case "copyblocksize":
                    guard let value,(64...16384).contains(value) else{bad();continue};result.copyBufferSizeKB=value;importedKey()
                case "watchdirs":
                    guard let value,value>=0 else{bad();continue}
                    result.autoRefreshEnabled=value&1 != 0;result.autoRefreshMetadata=value&2 != 0;result.autoRefreshOnlyForeground=value&8 != 0;result.autoRefreshUpdateHeader=value&32 != 0;importedKey()
                    if value & ~59 != 0{unsupported.append(e.label+": end-of-list insertion and diagnostic beep flags are unsupported")}
                    if value&16==0{unsupported.append(e.label+": native footer always follows the refreshed list")}
                case "customseparators":
                    let characters=Array(e.value);guard characters.count==4 else{bad();continue}
                    result.dateSeparator=characters[0]=="0" ? "" : String(characters[0]);result.timeSeparator=characters[1]=="0" ? "" : String(characters[1]);importedKey()
                    if characters[2] != "0" || characters[3] != "0" {unsupported.append(e.label+": numeric separators continue to follow the macOS locale")}

                case "showhiddensystem":
                    // macOS has hidden names but no Windows system-file attribute.
                    guard let value,[0,1,2].contains(value) else{bad();continue}
                    result.showHidden=value != 0;importedKey()
                    if value==1{unsupported.append(e.label+": Windows system attribute has no native equivalent")}
                case "showicons":
                    guard let value,(0...2).contains(value) else{bad();continue}
                    result.iconMode=[.none,.standard,.system][value];importedKey()
                case "dirtablimit":
                    guard let value,(8...100).contains(value) else{bad();continue};result.tabTitleMaximum=value;importedKey()
                case "dirtaboptions":
                    guard let value,value>=0 else{bad();continue}
                    result.tabsAlwaysVisible=value&1 != 0;result.newTabBesideCurrent=value&128 != 0;importedKey()
                    if value & ~129 != 0{unsupported.append(e.label+": only always-visible and new-tab-position flags are supported")}
                case "quicksearchmatchbeginning":boolean(\.quickSearchMatchBeginning)
                case "quicksearchexactmatch":boolean(\.quickSearchMatchEnding)
                default:unsupported.append(e.label)
                }
            } else if e.section=="packer" {
                switch e.key {
                case "internalziprate":guard let value,(0...9).contains(value) else{bad();continue};result.zipCompressionLevel=value;importedKey()
                case "verifyzip":boolean(\.zipVerifyAfterPacking)
                case "zipsetdatetonewest":boolean(\.archiveSetDateToNewest)
                default:unsupported.append(e.label)
                }
            } else if e.section=="allresolutions" {
                switch e.key {
                case "fontname":guard !e.value.isEmpty,e.value.count<=256 else{bad();continue};result.fileFontName=e.value;importedKey()
                case "fontsize":guard let value,(9...36).contains(value) else{bad();continue};result.fileFontSize=Double(value);importedKey()
                case "fontweight":guard let value,[400,700].contains(value) else{bad();continue};result.fileFontBold=value==700;importedKey()
                default:unsupported.append(e.label)
                }
            } else {unsupported.append(e.label)}
        }
        return ConfigurationImportReport(configuration:result,imported:imported,unsupported:unsupported,invalid:invalid)
    }
}
