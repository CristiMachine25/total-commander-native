import Foundation

/// Native subset of Total Commander's content-expression grammar. It never loads plugins or executes commands.
enum CustomColumnAlignment:String,Codable,CaseIterable {case left,right}
struct CustomColumnDefinition:Codable,Equatable {
    var id:String=UUID().uuidString
    var title:String="Size"
    var expression:String="[=tc.size]"
    var width:Double=100
    var alignment:CustomColumnAlignment = .left
}
struct CustomColumnSet:Codable,Equatable {
    var id:String=UUID().uuidString
    var name:String="New columns"
    var columns:[CustomColumnDefinition]=[]
    var adjustNameWidth:Bool=true
    var horizontalScroll:Bool=true
}
enum CustomColumnSettings {
    static func validate(sets:[CustomColumnSet],activeID:String)throws {
        guard sets.count<=29 else{throw invalid("A maximum of 29 custom column sets is supported.")}
        var ids=Set<String>()
        for set in sets {
            guard !set.id.isEmpty,set.id.count<=128,ids.insert(set.id).inserted,set.name.count<=128,set.columns.count<=32 else{throw invalid("Invalid or duplicate custom column set identifier, name or column count.")}
            var columns=Set<String>()
            for column in set.columns {
                guard !column.id.isEmpty,column.id.count<=128,columns.insert(column.id).inserted,!column.title.isEmpty,column.title.count<=128,column.width.isFinite,(32...1200).contains(column.width) else{throw invalid("Column captions must be nonempty; widths must be 32–1200 points; identifiers must be unique.")}
                try CustomColumnExpression.validate(column.expression)
            }
        }
        guard activeID.isEmpty || ids.contains(activeID) else{throw invalid("The selected custom column set no longer exists.")}
    }
    static func invalid(_ message:String)->NSError {NSError(domain:"CustomColumns",code:1,userInfo:[NSLocalizedDescriptionKey:message])}
}
struct CustomColumnExpression {
    struct Field {var name:String;var unit:String;var prefix:String;var suffix:String;var range:ClosedRange<Int>?}
    enum Part {case literal(String),field(Field)}
    let parts:[Part]
    static let availableFields=["name","ext","fullname","path","size","size.bytes","size.kbytes","size.mbytes","size.gbytes","writedate","creationdate","accessdate","writetime","creationtime","accesstime","attributes"].map{"[=tc.\($0)]"}
    static func validate(_ expression:String)throws {_=try Self(expression)}
    init(_ expression:String)throws {
        guard expression.count<=2048,!expression.contains("\0") else{throw CustomColumnSettings.invalid("Column expressions must be at most 2048 characters.")}
        var result:[Part]=[],rest=expression[...]
        while let start=rest.range(of:"[=") {
            if start.lowerBound>rest.startIndex {result.append(.literal(String(rest[..<start.lowerBound])))}
            guard let close=rest[start.upperBound...].firstIndex(of:"]") else{throw CustomColumnSettings.invalid("Unclosed column expression.")}
            var body=String(rest[start.upperBound..<close]),prefix="",suffix="",slice:ClosedRange<Int>?
            if body.hasPrefix("\"") {
                body.removeFirst();guard let quote=body.firstIndex(of:"\"") else{throw CustomColumnSettings.invalid("Unclosed field prefix.")}
                prefix=String(body[..<quote]);body=String(body[body.index(after:quote)...])
            }
            if let quote=body.firstIndex(of:"\"") {
                let tail=body[body.index(after:quote)...];guard tail.last=="\"",!tail.dropLast().contains("\"") else{throw CustomColumnSettings.invalid("Invalid field suffix.")}
                suffix=String(tail.dropLast());body=String(body[..<quote])
            }
            if let colon=body.lastIndex(of:":") {
                let bounds=body[body.index(after:colon)...].split(separator:"-",omittingEmptySubsequences:false)
                guard bounds.count==2,let lower=Int(bounds[0]),let upper=Int(bounds[1]),lower>0,upper>=lower,upper<=100000 else{throw CustomColumnSettings.invalid("Column substrings use positive positions, for example :4-7.")}
                slice=lower...upper;body=String(body[..<colon])
            }
            let pieces=body.split(separator:".",maxSplits:2,omittingEmptySubsequences:false)
            guard pieces.count>=2,pieces[0].lowercased()=="tc" else{throw CustomColumnSettings.invalid("Only built-in tc fields are available; Windows content plugins are not loaded.")}
            let name=pieces[1].lowercased(),unit=pieces.count==3 ? String(pieces[2]):""
            let dates=["writedate","creationdate","accessdate","writetime","creationtime","accesstime"]
            guard ["name","ext","fullname","path","size","attributes"].contains(name) || dates.contains(name) else{throw CustomColumnSettings.invalid("Unsupported built-in field: \(name).")}
            if name=="size" {guard ["","bytes","kbytes","mbytes","gbytes"].contains(unit.lowercased()) else{throw CustomColumnSettings.invalid("Unsupported size unit.")}}
            else if dates.contains(name) {guard unit.count<=64,unit.allSatisfy({"YyMDhmsvaPp -/:.,".contains($0)}) else{throw CustomColumnSettings.invalid("Unsupported date formatter.")}}
            else if !unit.isEmpty {throw CustomColumnSettings.invalid("This field does not accept a unit.")}
            result.append(.field(Field(name:name,unit:unit,prefix:prefix,suffix:suffix,range:slice)))
            rest=rest[rest.index(after:close)...]
        }
        if !rest.isEmpty{result.append(.literal(String(rest)))}
        parts=result
    }
    /// No filesystem calls for name, size, or modified date. Other dates are read only for local rows.
    func text(entry:FileEntry,local:Bool,dateText:(Date)->String,sizeText:(Int64)->String)->String {
        parts.map {part in
            switch part {
            case .literal(let value):return value
            case .field(let field):
                guard var value=Self.value(field,entry:entry,local:local,dateText:dateText,sizeText:sizeText) else{return ""}
                if let range=field.range {value=String(value.dropFirst(range.lowerBound-1).prefix(range.upperBound-range.lowerBound+1))}
                return field.prefix+value+field.suffix
            }
        }.joined()
    }
    func compare(_ a:FileEntry,_ b:FileEntry,local:Bool,caseSensitive:Bool,dateText:(Date)->String,sizeText:(Int64)->String)->ComparisonResult {
        if parts.count==1,case .field(let field)=parts[0],field.range==nil {
            if field.name=="size" {return a.size==b.size ? .orderedSame:(a.size<b.size ? .orderedAscending:.orderedDescending)}
            if field.name.hasSuffix("date") || field.name.hasSuffix("time") {return (Self.date(field.name,entry:a,local:local) ?? .distantPast).compare(Self.date(field.name,entry:b,local:local) ?? .distantPast)}
        }
        let lhs=text(entry:a,local:local,dateText:dateText,sizeText:sizeText),rhs=text(entry:b,local:local,dateText:dateText,sizeText:sizeText)
        return caseSensitive ? lhs.compare(rhs):lhs.localizedStandardCompare(rhs)
    }
    private static func date(_ name:String,entry:FileEntry,local:Bool)->Date? {
        if name.hasPrefix("write"){return entry.modified}
        guard local else{return nil}
        let values=try? entry.url.resourceValues(forKeys:[.creationDateKey,.contentAccessDateKey])
        return name.hasPrefix("creation") ? values?.creationDate:values?.contentAccessDate
    }
    private static func value(_ field:Field,entry:FileEntry,local:Bool,dateText:(Date)->String,sizeText:(Int64)->String)->String? {
        switch field.name {
        case "name":return (entry.name as NSString).deletingPathExtension
        case "ext":return (entry.name as NSString).pathExtension
        case "fullname":return entry.name
        case "path":return entry.url.deletingLastPathComponent().path+"/"
        case "attributes":return entry.isSymbolicLink ? "link":(entry.isDirectory ? "d---":"-a--")
        case "size":
            guard !entry.isDirectory else{return nil}
            switch field.unit.lowercased() {case "bytes":return String(entry.size);case "kbytes":return String(format:"%.2f",Double(entry.size)/1024);case "mbytes":return String(format:"%.2f",Double(entry.size)/1048576);case "gbytes":return String(format:"%.2f",Double(entry.size)/1073741824);default:return sizeText(entry.size)}
        default:
            guard let date=date(field.name,entry:entry,local:local) else{return nil}
            let format=field.unit.isEmpty && field.name.hasSuffix("time") ? "h:m:s":field.unit
            if format.isEmpty{return dateText(date)}
            var calendar=Calendar(identifier:.gregorian);calendar.timeZone = .current
            let c=calendar.dateComponents([.year,.month,.day,.hour,.minute,.second,.nanosecond],from:date)
            return format.map {ch -> String in
                switch ch {case "Y":return String(format:"%04d",c.year ?? 0);case "y":return String(format:"%02d",(c.year ?? 0)%100);case "M":return String(format:"%02d",c.month ?? 0);case "D":return String(format:"%02d",c.day ?? 0);case "h":return String(format:"%02d",c.hour ?? 0);case "a":return String(format:"%02d",((c.hour ?? 0)+11)%12+1);case "m":return String(format:"%02d",c.minute ?? 0);case "s":return String(format:"%02d",c.second ?? 0);case "v":return String(format:"%03d",(c.nanosecond ?? 0)/1000000);case "P":return (c.hour ?? 0)<12 ? "am":"pm";case "p":return (c.hour ?? 0)<12 ? "a":"p";default:return String(ch)}
            }.joined()
        }
    }
}
