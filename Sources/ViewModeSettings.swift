import Foundation

enum CommanderColumnsView:String,Codable,CaseIterable {case unchanged,full,brief,thumbnails}
enum CommanderConditionMatch:String,Codable,CaseIterable {case all,any}
enum CommanderViewConditionKind:String,Codable,CaseIterable {case path,local,archive,ftp,fileMask}
enum CommanderFileMatch:String,Codable,CaseIterable {case all,none,half,any,percent}
struct CommanderViewMode:Codable,Equatable {
    var id=UUID().uuidString
    var name="New view mode"
    var columnsView:CommanderColumnsView = .unchanged
    var customColumnSetID:String?=nil
    var sortColumn="unchanged"
    var ascending:Bool?=nil
    var secondarySortColumns:[String]=[]
    var directoriesFirst:Bool?=nil
    var fileMask:String?=nil
    var background:ConfigurationColor?=nil
    var foreground:ConfigurationColor?=nil
    var alternatingBackground:ConfigurationColor?=nil
    var tabColor:ConfigurationColor?=nil
    var darkBackground:ConfigurationColor?=nil
    var darkForeground:ConfigurationColor?=nil
    var darkAlternatingBackground:ConfigurationColor?=nil
    var darkTabColor:ConfigurationColor?=nil
    var tabIcon=""
    var autoRunCommands=""
}
struct CommanderViewCondition:Codable,Equatable {
    var kind:CommanderViewConditionKind = .path
    var value=""
    var path=""
    var includeSubdirectories=false
    var minimumMatchPercent=0
    var fileMatch:CommanderFileMatch = .any
    var negated=false
    /// Join to the preceding sub-rule. Nil uses the rule's common conjunction.
    var conjunction:CommanderConditionMatch?=nil
}
struct CommanderAutoSwitchRule:Codable,Equatable {
    var id=UUID().uuidString
    var name="New rule"
    var enabled=true
    var viewModeID=""
    var match:CommanderConditionMatch = .all
    var conditions:[CommanderViewCondition]=[]
}
struct CommanderViewContext {
    enum Kind {case local,archive,ftp}
    let kind:Kind
    let path:String
    let fileNames:[String]
}
enum ViewModeSettings {
    static func failure(_ text:String)->NSError {NSError(domain:"ViewModeSettings",code:1,userInfo:[NSLocalizedDescriptionKey:text])}
    static let autoCommands:Set<String>=["cm_srclong","cm_srcshort","cm_srcthumbs","cm_srcbyname","cm_srcbyext","cm_srcbysize","cm_srcbydatetime","cm_srcunsorted","cm_srcnegorder","cm_srcallfiles","cm_srcexecs","cm_50percent","cm_100percent"]
    struct Commands {var skipTab=false;var everyDirectory=false;var enter:[String]=[];var leave:[String]=[]}
    static func commands(_ text:String)throws->Commands {
        var value=text.trimmingCharacters(in:.whitespacesAndNewlines),result=Commands()
        while let first=value.first,first=="*" || first=="-" {if first=="*" {result.everyDirectory=true}else{result.skipTab=true};value.removeFirst()}
        let parts=value.split(separator:"|",omittingEmptySubsequences:false)
        guard parts.count<=2 else{throw failure("Use enter commands | leave commands in Auto-run commands.")}
        func parse(_ part:Substring)throws->[String] {
            if part.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty{return []}
            return try part.split(separator:",",omittingEmptySubsequences:false).map {
                let command=$0.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
                guard autoCommands.contains(command) else{throw failure("Unsupported automatic command ‘\(command)’. Only native view and sort commands are allowed.")};return command
            }
        }
        if let first=parts.first {result.enter=try parse(first)}
        if parts.count==2 {result.leave=try parse(parts[1])};return result
    }
    static func validate(modes:[CommanderViewMode],rules:[CommanderAutoSwitchRule],customColumnSets:[CustomColumnSet])throws {
        guard modes.count<=100,rules.count<=200 else{throw failure("Use at most 100 view modes and 200 automatic rules.")}
        func unique(_ values:[String],_ label:String)throws {
            guard values.allSatisfy({!$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && $0.utf8.count<=256}),Set(values).count==values.count else{throw failure("\(label) must be nonempty and unique.")}
        }
        try unique(modes.map(\.id),"Mode identifiers");try unique(modes.map(\.name),"Mode names")
        try unique(rules.map(\.id),"Rule identifiers")
        let sets=Set(customColumnSets.map(\.id)),ids=Set(modes.map(\.id))
        let allCustomSorts=Set(customColumnSets.flatMap{$0.columns.map{"custom."+$0.id}})
        let sorts:Set<String>=["unchanged","name","ext","size","date","unsorted"]
        for mode in modes {
            let customSorts:Set<String>
            if let id=mode.customColumnSetID {customSorts=Set(customColumnSets.first(where:{$0.id==id})?.columns.map{"custom."+$0.id} ?? [])} else {customSorts=allCustomSorts}
            if let id=mode.customColumnSetID,!id.isEmpty,!sets.contains(id){throw failure("View mode ‘\(mode.name)’ refers to a missing custom-column set.")}
            guard sorts.contains(mode.sortColumn) || customSorts.contains(mode.sortColumn),mode.secondarySortColumns.count<=8,mode.secondarySortColumns.allSatisfy({let key=$0.hasPrefix("-") ? String($0.dropFirst()):$0;return ["name","ext","size","date"].contains(key) || customSorts.contains(key)}) else{throw failure("Invalid sort columns in ‘\(mode.name)’.")}
            guard (mode.fileMask?.utf8.count ?? 0)<=4096,mode.autoRunCommands.utf8.count<=4096,mode.tabIcon.utf8.count<=128 else{throw failure("View mode text is too long.")}
            for color in [mode.background,mode.foreground,mode.alternatingBackground,mode.tabColor,mode.darkBackground,mode.darkForeground,mode.darkAlternatingBackground,mode.darkTabColor].compactMap({$0}) {guard color==color.normalized else{throw failure("Mode colors must be finite values between zero and one.")}}
            _=try commands(mode.autoRunCommands)
        }
        for rule in rules {
            guard !rule.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,rule.name.utf8.count<=256,ids.contains(rule.viewModeID) else{throw failure("Each automatic rule needs a name and an existing view mode.")}
            guard !rule.conditions.isEmpty,rule.conditions.count<=32 else{throw failure("Each rule needs between one and 32 sub-rules.")}
            for condition in rule.conditions {
                guard condition.value.utf8.count<=4096,condition.path.utf8.count<=4096,(0...100).contains(condition.minimumMatchPercent) else{throw failure("Invalid rule text length or percentage.")}
                if condition.kind == .path || condition.kind == .fileMask {guard !condition.value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{throw failure("Path and file-type rules need a pattern.")}}
            }
        }
    }
    static func wildcard(_ text:String,pattern:String)->Bool {
        // Dynamic programming: bounded memory and no regex backtracking on user patterns.
        let input=Array(text.lowercased()),glob=Array(pattern.lowercased())
        var previous=Array(repeating:false,count:input.count+1);previous[0]=true
        for token in glob {
            var row=Array(repeating:false,count:input.count+1);row[0]=token=="*" && previous[0]
            if !input.isEmpty {for i in 1...input.count {row[i]=token=="*" ? (previous[i] || row[i-1]):((token=="?" || token==input[i-1]) && previous[i-1])}}
            previous=row
        };return previous[input.count]
    }
    static func pathMatches(_ path:String,pattern:String,subdirectories:Bool)->Bool {
        func trim(_ s:String)->String {s.count>1 ? s.trimmingCharacters(in:CharacterSet(charactersIn:"/")) : s}
        let p=trim((pattern as NSString).expandingTildeInPath),value=trim(path)
        if wildcard(value,pattern:p){return true}
        if p.hasSuffix("/*"),wildcard(value,pattern:String(p.dropLast(2))){return true}
        guard subdirectories else{return false}
        var parent=value
        while let index=parent.lastIndex(of:"/") {parent=String(parent[..<index]);if wildcard(parent,pattern:p){return true}}
        return p=="/"
    }
    static func fileMatches(_ name:String,mask:String)->Bool {
        let halves=mask.split(separator:"|",maxSplits:1,omittingEmptySubsequences:false)
        func patterns(_ text:Substring)->[String] {text.split(whereSeparator:{$0==";" || $0.isWhitespace}).map(String.init)}
        let include=patterns(halves.first ?? ""),exclude=halves.count>1 ? patterns(halves[1]):[]
        func match(_ p:String)->Bool {wildcard(name,pattern:p=="*.*" ? "*":p)}
        return (include.isEmpty || include.contains(where:match)) && !exclude.contains(where:match)
    }
    static func matches(_ condition:CommanderViewCondition,context:CommanderViewContext)->Bool {
        let result:Bool
        switch condition.kind {
        case .local:result=context.kind == .local
        case .archive:result=context.kind == .archive
        case .ftp:result=context.kind == .ftp
        case .path:result=pathMatches(context.path,pattern:condition.value,subdirectories:condition.includeSubdirectories)
        case .fileMask:
            let inPath=condition.path.isEmpty || pathMatches(context.path,pattern:condition.path,subdirectories:condition.includeSubdirectories)
            let total=context.fileNames.count,count=context.fileNames.filter{fileMatches($0,mask:condition.value)}.count
            let names:Bool
            switch condition.fileMatch {
            case .all:names=total>0 && count==total
            case .none:names=count==0
            case .half:names=total>0 && count*2>=total
            case .any:names=count>0
            case .percent:names=total>0 && count>0 && count*100>=total*condition.minimumMatchPercent
            }
            result=inPath && names
        }
        return condition.negated ? !result:result
    }
    static func matches(_ rule:CommanderAutoSwitchRule,context:CommanderViewContext)->Bool {
        guard rule.enabled,!rule.conditions.isEmpty else{return false}
        var group=matches(rule.conditions[0],context:context),result=false
        for condition in rule.conditions.dropFirst() {
            let value=matches(condition,context:context)
            if (condition.conjunction ?? rule.match) == .all {group=group && value}
            else {result=result || group;group=value}
        };return result || group
    }
    static func matchingModeID(rules:[CommanderAutoSwitchRule],context:CommanderViewContext)->String? {rules.first{matches($0,context:context)}?.viewModeID}
}
