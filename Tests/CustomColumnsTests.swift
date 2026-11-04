import Foundation

@main struct CustomColumnsTests {
    static func main()throws {
        var count=0
        func check(_ condition:Bool,_ name:String){precondition(condition,name);count += 1}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("custom-columns-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        let url=root.appendingPathComponent("report.txt");try Data(repeating:1,count:2048).write(to:url)
        let entry=FileEntry(url:url,name:"report.txt",isDirectory:false,isSymbolicLink:false,size:2048,modified:Date(timeIntervalSince1970:1700000000))
        let folder=FileEntry(url:root,name:root.lastPathComponent,isDirectory:true,isSymbolicLink:false,size:0,modified:nil)
        func value(_ s:String,_ e:FileEntry?=nil,_ local:Bool=true)throws->String {try CustomColumnExpression(s).text(entry:e ?? entry,local:local,dateText:{_ in "date"},sizeText:{String($0)})}
        check(try value("[=tc.fullname]")=="report.txt","Full name")
        check(try value("[=tc.name]-[=tc.ext]")=="report-txt","Name and extension")
        check(try value("[=tc.size.bytes]")=="2048","Bytes")
        check(try value("[=tc.size.kbytes]")=="2.00","KiB")
        check(try value("[=tc.name:2-4]")=="epo","Substring")
        check(try value("[=tc.name:20-30]")=="","Out-of-range substring")
        check(try value("[=\"(\"tc.size.kbytes\" KiB)\"]")=="(2.00 KiB)","Conditional literal")
        check(try value("[=\"(\"tc.size.kbytes\" KiB)\"]",folder)=="","Absent size suppresses literals")
        check(try value("[=tc.creationdate]",entry,false)=="","Remote dates not read from disk")
        check(try value("[=tc.creationdate]")=="date","Local creation date")
        check(try value("[=tc.accessdate]")=="date","Local access date")
        check(try value("[=tc.writedate.Y-M-D]").hasPrefix("2023-11-"),"Date formatter")
        check(try value("[=tc.writetime]").split(separator:":").count==3,"Time formatter")
        check(try value("[=tc.path]").hasSuffix("/"),"Path slash")
        check(try value("[=tc.attributes]")=="-a--","Attributes")
        for bad in ["[=plugin.title]","[=tc.nope]","[=tc.size.bad]","[=tc.name:0-3]","[=tc.name:4-2]","[=tc.name","[=tc.writedate.zz]","[=tc.ext.bytes]"] {
            do{try CustomColumnExpression.validate(bad);fatalError("Accepted \(bad)")}catch{count += 1}
        }
        let small=FileEntry(url:url,name:"small",isDirectory:false,isSymbolicLink:false,size:2,modified:nil)
        let compare=try CustomColumnExpression("[=tc.size.bytes]").compare(small,entry,local:true,caseSensitive:false,dateText:{_ in ""},sizeText:{String($0)})
        check(compare == .orderedAscending,"Numeric order, not lexicographic")
        let set=CustomColumnSet(id:"one",name:"Details",columns:[.init(id:"size",title:"KiB",expression:"[=tc.size.kbytes]",width:120,alignment:.right)])
        try CustomColumnSettings.validate(sets:[set],activeID:"one");count += 1
        let data=try JSONEncoder().encode(set);check(try JSONDecoder().decode(CustomColumnSet.self,from:data)==set,"Round trip")
        do{try CustomColumnSettings.validate(sets:[set,set],activeID:"one");fatalError("Duplicate set")}catch{count += 1}
        do{try CustomColumnSettings.validate(sets:[set],activeID:"missing");fatalError("Missing set")}catch{count += 1}
        var invalid=set;invalid.columns[0].width=Double.nan
        do{try CustomColumnSettings.validate(sets:[invalid],activeID:"one");fatalError("Invalid width")}catch{count += 1}
        print("PASS: \(count) custom column expression/model assertions")
    }
}
