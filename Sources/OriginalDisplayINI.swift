import Foundation

/// Data-only import of documented original display sections. A linked profile group
/// commits only after every member and reference validates; failures leave it intact.
enum OriginalDisplayINI {
    struct Entry {
        let section:String,key:String,value:String
        var id:String{section+"\0"+key}
        var label:String{"[\(section)] \(key)"}
    }
    static func handles(_ section:String)->Bool {["customfields","viewmodes","viewmodeswitch"].contains(section)}
    private static func fail(_ text:String)->NSError {NSError(domain:"OriginalDisplayINI",code:1,userInfo:[NSLocalizedDescriptionKey:text])}
    static func importEntries(_ entries:[Entry],duplicates:Set<String>,merging current:CommanderConfiguration,sections:Set<String>=[])->ConfigurationImportReport {
        let present=sections.union(entries.map(\.section))
        guard !present.isDisjoint(with:["customfields","viewmodes","viewmodeswitch"]) else{return .init(configuration:current,imported:[],unsupported:[],invalid:[])}
        var candidate=current,imported:[String]=[],unsupported:[String]=[],invalid:[String]=[]
        let grouped=Dictionary(grouping:entries,by:{$0.section})
        func section(_ name:String)->[String:Entry] {Dictionary(uniqueKeysWithValues:(grouped[name] ?? []).map{($0.key,$0)})}
        func required(_ dict:[String:Entry],_ key:String)throws->String {guard let value=dict[key]?.value else{throw fail("Missing required key \(key).")};return value}
        func integer(_ text:String)throws->Int {guard let n=Int(text.trimmingCharacters(in:.whitespaces)) else{throw fail("Invalid integer in display profile.")};return n}
        func color(_ text:String)throws->ConfigurationColor? {let value=try integer(text);if value == -1{return nil};guard (0...0xffffff).contains(value) else{throw fail("Unsupported original color value.")};return .init(red:Double(value&255)/255,green:Double((value>>8)&255)/255,blue:Double((value>>16)&255)/255)}
        func merge<T>(_ old:[T],_ new:[T],namespace:String,id:(T)->String)->[T] {let ids=Set(new.map(id));return old.filter{!id($0).hasPrefix(namespace) && !ids.contains(id($0))}+new}
        func customID(_ n:Int)->String{"ini.custom.\(n)"}
        func modeID(_ n:Int)->String{n==0 ? "default":"ini.mode.\(n)"}
        func keys(_ dict:[String:Entry],allowed:Set<String>) {for entry in dict.values where !allowed.contains(entry.key){unsupported.append(entry.label+": unsupported display-profile key")}}
        do {
            for e in entries where e.key == "redirectsection" {unsupported.append(e.label+": section redirection is not followed");throw fail("Redirected display profiles cannot be imported.")}
            for e in entries where duplicates.contains(e.id) {invalid.append(e.label+": duplicate key")}
            guard invalid.isEmpty else{throw fail("Ambiguous display-profile keys.")}
            let custom=section("customfields")
            if present.contains("customfields") {
                let rawTitles=custom.isEmpty ? "":try required(custom,"titles")
                let hasFirst=custom.keys.contains{["headers1","contents1","widths1","options1"].contains($0)}
                let titles=rawTitles.isEmpty && !hasFirst ? []:rawTitles.components(separatedBy:"|")
                for key in custom.keys {for prefix in ["headers","contents","widths","options"] where key.hasPrefix(prefix) {guard let number=Int(key.dropFirst(prefix.count)),number>0,number<=titles.count else{throw fail("Orphaned custom-column profile key.")}}}
                guard titles.count<=29 else{throw fail("More than 29 custom column sets.")}
                var importedSets:[CustomColumnSet]=[],allowed:Set<String>=["titles","autoload"]
                for (offset,name) in titles.enumerated() {
                    let number=offset+1,headersKey="headers\(number)",contentsKey="contents\(number)",widthsKey="widths\(number)",optionsKey="options\(number)"
                    allowed.formUnion([headersKey,contentsKey,widthsKey,optionsKey])
                    let headers=try required(custom,headersKey).components(separatedBy:"\\n"),contents=try required(custom,contentsKey).components(separatedBy:"\\n")
                    let widths=try required(custom,widthsKey).split(separator:",",omittingEmptySubsequences:false).map{try integer(String($0))}
                    guard headers.count==contents.count,widths.count==headers.count+2,!contents.isEmpty else{throw fail("Custom column captions, expressions and widths have different counts.")}
                    let options=try required(custom,optionsKey).components(separatedBy:"|")
                    guard (2...3).contains(options.count) else{throw fail("Invalid custom-column options.")}
                    let referenceWidth=try integer(options[0]),scroll=try integer(options[1])
                    guard referenceWidth>=(-1),[0,1].contains(scroll) else{throw fail("Invalid custom-column options.")}
                    if options.count==3 {guard (48...768).contains(try integer(options[2])) else{throw fail("Invalid source DPI.")}}
                    var columns:[CustomColumnDefinition]=[]
                    for i in contents.indices {
                        let width=widths[i+2];guard width != Int.min,width != 0,abs(width)<=1200 else{throw fail("Invalid custom-column width.")}
                        do{try CustomColumnExpression.validate(contents[i])}catch{unsupported.append("[customfields] \(contentsKey): "+error.localizedDescription);throw fail("Unsupported custom column expression; profile group was not imported.")}
                        columns.append(.init(id:"ini.column.\(number).\(i+1)",title:headers[i],expression:contents[i],width:Double(max(32,abs(width))),alignment:width<0 ? .right:.left))
                    }
                    importedSets.append(.init(id:customID(number),name:name,columns:columns,adjustNameWidth:referenceWidth>0,horizontalScroll:scroll==1))
                }
                keys(custom,allowed:allowed)
                if let auto=custom["autoload"],auto.value != "0" {unsupported.append(auto.label+": original plugin/default auto-load is not a native pane selection")}
                unsupported.append("[customfields] widths/options: widths use native points (minimum 32); Windows Name/Ext widths, font metrics and source DPI are not reproduced")
                candidate.customColumnSets=merge(candidate.customColumnSets,importedSets,namespace:"ini.custom.",id:{$0.id})
                imported += custom.values.filter{allowed.contains($0.key) && $0.key != "autoload"}.map(\.label)
            }
            let modes=section("viewmodes")
            if present.contains("viewmodes") {
                let indices=try profileIndices(modes.keys,suffixes:["name","options","icon","commands"])
                guard modes.isEmpty || !indices.isEmpty else{throw fail("ViewModes contains no recognized profiles.")}
                var next:[CommanderViewMode]=[],allowed=Set<String>()
                for index in indices {
                    let prefix="\(index)_";allowed.formUnion([prefix+"name",prefix+"options",prefix+"icon",prefix+"commands"])
                    let name=try required(modes,prefix+"name"),options=try required(modes,prefix+"options").components(separatedBy:"|")
                    guard options.count==7 || options.count==9 else{throw fail("View mode options require 7 or 9 fields.")}
                    var mode=CommanderViewMode();mode.id=modeID(index);mode.name=name
                    let view=try integer(options[0])
                    switch view {
                    case -1:mode.columnsView = .unchanged
                    case 1:mode.columnsView = .full;mode.customColumnSetID=""
                    case 6...34:mode.columnsView = .full;mode.customColumnSetID=customID(view-5)
                    default:unsupported.append("[viewmodes] \(prefix)options: original view code \(view) has not been mapped");throw fail("Unsupported original columns-view encoding.")
                    }
                    let columnSet=mode.customColumnSetID.flatMap{id in candidate.customColumnSets.first{$0.id==id}}
                    func sort(_ n:Int)throws->String {
                        if n == -1{return "unchanged"}
                        if (0...4).contains(n){return ["name","ext","size","date","unsorted"][n]}
                        if n>=100,let set=columnSet,set.columns.indices.contains(n-100){return "custom."+set.columns[n-100].id}
                        throw fail("Invalid or missing custom sort-column reference.")
                    }
                    mode.sortColumn=try sort(integer(options[1]))
                    let reversed=try integer(options[2]);guard [0,1].contains(reversed) else{throw fail("Invalid reversed-sort flag.")};mode.ascending=mode.sortColumn=="unchanged" ? nil:reversed==0
                    if !options[3].isEmpty {
                        let visible=["name","ext"]+(columnSet?.columns.map{"custom."+$0.id} ?? ["size","date","attr"])
                        mode.secondarySortColumns=try options[3].split(separator:",",omittingEmptySubsequences:false).map {raw in
                            let index=try integer(String(raw));guard index != Int.min,index != 0,visible.indices.contains(abs(index)-1) else{throw fail("Invalid additional sort index.")};let key=visible[abs(index)-1]
                            guard key != "attr" else{throw fail("Native attribute secondary sorting is unavailable.")};return (index<0 ? "-":"")+key
                        }
                    }
                    mode.tabColor=try color(options[4]);mode.background=try color(options[5]);mode.alternatingBackground=try color(options[6])
                    if options.count==9 {mode.darkBackground=try color(options[7]);mode.darkAlternatingBackground=try color(options[8])}
                    if let icon=modes[prefix+"icon"],!icon.value.isEmpty {unsupported.append(icon.label+": Windows icon paths/DLL indices are not loaded")}
                    if let commands=modes[prefix+"commands"] {do{_=try ViewModeSettings.commands(commands.value)}catch{unsupported.append(commands.label+": "+error.localizedDescription);throw fail("Unsupported automatic command; profile group was not imported.")};mode.autoRunCommands=commands.value}
                    next.append(mode)
                }
                keys(modes,allowed:allowed);candidate.viewModes=merge(candidate.viewModes,next,namespace:"ini.mode.",id:{$0.id})
                imported += modes.values.filter{allowed.contains($0.key) && !$0.key.hasSuffix("_icon")}.map(\.label)
            }
            let switching=section("viewmodeswitch")
            if present.contains("viewmodeswitch") {
                let indices=try profileIndices(switching.keys.filter{$0 != "enabled"},suffixes:["rules","mode"])
                guard switching.isEmpty || switching["enabled"] != nil || !indices.isEmpty else{throw fail("ViewModeSwitch contains no recognized profiles.")}
                var next:[CommanderAutoSwitchRule]=[],allowed:Set<String>=["enabled"]
                for index in indices {
                    let prefix="\(index)_";allowed.formUnion([prefix+"rules",prefix+"mode"])
                    let number=try integer(required(switching,prefix+"mode"));guard number>=0 else{throw fail("Invalid view mode reference.")}
                    let encoded=try required(switching,prefix+"rules")
                    var rule=CommanderAutoSwitchRule();rule.id="ini.rule.\(index)";rule.name="Imported rule \(index+1)";rule.viewModeID=modeID(number)
                    do{rule.conditions=try conditions(encoded);if rule.conditions.contains(where:{$0.kind == .local}) {unsupported.append("[viewmodeswitch] \(prefix)rules: original L/D drive-letter and UNC semantics map to native local directories; Windows drive classification is not reproduced")}}catch{unsupported.append("[viewmodeswitch] \(prefix)rules: "+error.localizedDescription);throw fail("Unsupported automatic rule; profile group was not imported.")}
                    next.append(rule)
                }
                if let enabled=switching["enabled"] {guard ["0","1"].contains(enabled.value) else{throw fail("Invalid automatic-switch Enabled flag.")};candidate.autoSwitchEnabled=enabled.value=="1"}
                keys(switching,allowed:allowed);candidate.autoSwitchRules=merge(candidate.autoSwitchRules,next,namespace:"ini.rule.",id:{$0.id});candidate.autoSwitchRestoreDefault=true
                imported += switching.values.filter{allowed.contains($0.key)}.map(\.label)
            }
            try CustomColumnSettings.validate(sets:candidate.customColumnSets,activeID:candidate.activeCustomColumnSetID)
            try ViewModeSettings.validate(modes:candidate.viewModes,rules:candidate.autoSwitchRules,customColumnSets:candidate.customColumnSets)
            return .init(configuration:candidate,imported:imported.sorted(),unsupported:unsupported.sorted(),invalid:[])
        }catch {
            invalid.append("Display profiles unchanged: "+error.localizedDescription)
            return .init(configuration:current,imported:[],unsupported:unsupported.sorted(),invalid:invalid.sorted())
        }
    }
    private static func profileIndices<S:Sequence>(_ keys:S,suffixes:Set<String>)throws->[Int] where S.Element==String {
        var values=Set<Int>()
        for key in keys {
            let parts=key.split(separator:"_",maxSplits:1)
            guard parts.count==2,suffixes.contains(String(parts[1])) else{continue}
            guard let index=Int(parts[0]),index>=0,index<200,String(index)==parts[0] else{throw fail("Invalid profile index.")};values.insert(index)
        }
        return values.sorted()
    }
    private static func conditions(_ text:String)throws->[CommanderViewCondition] {
        var remaining=text[...],pieces:[(String,CommanderConditionMatch?)]=[],join:CommanderConditionMatch?=nil
        while true {
            let and=remaining.range(of:"|&"),or=remaining.range(of:"||"),next=[and,or].compactMap{$0}.min{$0.lowerBound<$1.lowerBound}
            guard let next else{pieces.append((String(remaining),join));break}
            pieces.append((String(remaining[..<next.lowerBound]),join));join=String(remaining[next])=="|&" ? .all:.any;remaining=remaining[next.upperBound...]
        }
        return try pieces.map {raw,join in
            var condition=CommanderViewCondition();condition.conjunction=join
            switch raw {
            case "A":condition.kind = .archive
            case "F":condition.kind = .ftp
            case "L","D":condition.kind = .local
            default:
                guard raw.hasPrefix("+"),raw.count>1 else{throw fail("Only A, F, L, D and + native absolute-path rules are supported.")}
                var path=String(raw.dropFirst())
                guard path.hasPrefix("/") || path.hasPrefix("~/"),!path.contains("\\"),!path.contains("%"),!path.contains("|") else{throw fail("Windows drive/UNC paths, environment expansion and encoded file-type conditions require manual translation.")}
                if path.hasSuffix("/*"){condition.includeSubdirectories=true;path=String(path.dropLast(2));if path.isEmpty{path="/"}}
                condition.kind = .path;condition.value=path
            };return condition
        }
    }
}
