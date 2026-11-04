import Foundation

@main struct FilePartsTests {
    static var count=0
    static func check(_ value:@autoclosure ()throws->Bool,_ label:String)throws{count+=1;if try !value(){throw FilePartsError.message("Test failed: "+label)}}
    static func rejects(_ label:String,_ work:()throws->Void)throws{var failed=false;do{try work()}catch{failed=true};try check(failed,label)}
    static func main()throws{
        let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("parts-tests-"+UUID().uuidString)
        try fm.createDirectory(at:root,withIntermediateDirectories:false);defer{try? fm.removeItem(at:root)}
        func folder(_ name:String)throws->URL{let u=root.appendingPathComponent(name);try fm.createDirectory(at:u,withIntermediateDirectories:false);return u}
        for (value,bytes) in [("1",UInt64(1)),("2k",2048),("3M",3145728),("1G",1073741824)] {try check(try FilePartsService.parsePartSize(value)==bytes,"size suffix "+value)}
        for invalid in ["0","-1","1.5M","999999999999999999999G",""]{try rejects("invalid size"){_=try FilePartsService.parsePartSize(invalid)}}
        let source=root.appendingPathComponent("sample.dat"),parts=try folder("parts")
        try Data("123456789".utf8).write(to:source)
        let outputs=try FilePartsService.split(source:source,destination:parts,bytesPerPart:4)
        try check(outputs.map(\.lastPathComponent)==["sample.001","sample.002","sample.003","sample.crc"],"TC stem part names")
        let manifest=try String(contentsOf:parts.appendingPathComponent("sample.crc"),encoding:.utf8)
        try check(manifest=="filename=sample.dat\r\nfilenameutf8=sample.dat\r\nsize=9\r\ncrc32=CBF43926\r\n","original CRC field layout and known vector")
        let plan=try FilePartsService.inspect(firstPart:outputs[0]);try check(plan.suggestedName=="sample.dat" && plan.parts.count==3,"manifest restores original filename")
        let combined=root.appendingPathComponent("combined")
        try FilePartsService.combine(firstPart:outputs[0],destination:combined)
        try check(try Data(contentsOf:combined)==Data(contentsOf:source),"binary roundtrip")
        try rejects("split no overwrite"){_=try FilePartsService.split(source:source,destination:parts,bytesPerPart:4)}
        try rejects("combine no overwrite"){_=try FilePartsService.combine(firstPart:outputs[0],destination:combined)}
        try rejects("must select first part"){_=try FilePartsService.inspect(firstPart:outputs[1])}
        try Data("xxxx".utf8).write(to:outputs[1])
        let bad=root.appendingPathComponent("bad")
        try rejects("CRC detects changed bytes"){_=try FilePartsService.combine(firstPart:outputs[0],destination:bad)}
        try check(!fm.fileExists(atPath:bad.path),"CRC failure commits nothing")
        try fm.removeItem(at:outputs[1]);try rejects("sequence gap"){_=try FilePartsService.inspect(firstPart:outputs[0])}
        let unix=try folder("unix")
        for (name,data) in [("file1aa","a"),("file1ab","b"),("file1ac","c")]{try Data(data.utf8).write(to:unix.appendingPathComponent(name))}
        let unixPlan=try FilePartsService.inspect(firstPart:unix.appendingPathComponent("file1aa"));try check(unixPlan.parts.count==3,"Unix suffix with digit in prefix")
        let unixOut=root.appendingPathComponent("unix-out");try FilePartsService.combine(firstPart:unixPlan.parts[0],destination:unixOut)
        try check(try String(contentsOf:unixOut,encoding:.utf8)=="abc","Unix alphabetic combination")
        let unix3=try folder("unix3")
        for name in ["prefixaaa","prefixaab"]{try Data([1]).write(to:unix3.appendingPathComponent(name))}
        try check(try FilePartsService.inspect(firstPart:unix3.appendingPathComponent("prefixaaa")).parts.count==2,"longer fixed-width Unix suffix")
        let dottedUnix=try folder("dotted-unix")
        for name in ["file1.aa","file1.ab"]{try Data([1]).write(to:dottedUnix.appendingPathComponent(name))}
        try check(try FilePartsService.inspect(firstPart:dottedUnix.appendingPathComponent("file1.aa")).parts.count==2,"Unix prefix with numeric dotted name")
        let numeric=try folder("numeric")
        for n in 0...2 {try Data([UInt8(n)]).write(to:numeric.appendingPathComponent(String(format:"file.%05d.zip.part",n)))}
        try check(try FilePartsService.inspect(firstPart:numeric.appendingPathComponent("file.00000.zip.part")).parts.count==3,"numeric suffix before zip.part")
        let upper=root.appendingPathComponent("UPPER.bin"),upperParts=try folder("upper");try Data([1]).write(to:upper)
        try check(try FilePartsService.split(source:upper,destination:upperParts,bytesPerPart:1).last?.lastPathComponent=="UPPER.CRC","uppercase CRC extension")
        let unicode=root.appendingPathComponent("fișier.bin"),unicodeParts=try folder("unicode");try Data([0,255,10]).write(to:unicode)
        let unicodeOutput=try FilePartsService.split(source:unicode,destination:unicodeParts,bytesPerPart:2)
        try check(try FilePartsService.inspect(firstPart:unicodeOutput[0]).suggestedName=="fișier.bin","UTF8 filename field")
        let cancelParts=try folder("cancel"),task=FilePartsTask()
        try rejects("cancelled split"){_=try FilePartsService.split(source:source,destination:cancelParts,bytesPerPart:2,task:task,progress:{_,_ in task.cancel()})}
        try check(try fm.contentsOfDirectory(atPath:cancelParts.path).isEmpty,"cancel split cleanup")
        let combineTask=FilePartsTask(),cancelOut=root.appendingPathComponent("cancel-output")
        try rejects("cancelled combine"){_=try FilePartsService.combine(firstPart:unixPlan.parts[0],destination:cancelOut,task:combineTask,progress:{_,_ in combineTask.cancel()})}
        try check(!fm.fileExists(atPath:cancelOut.path),"cancel combine cleanup")
        let changeParts=try folder("changing")
        try rejects("changed source detected"){_=try FilePartsService.split(source:source,destination:changeParts,bytesPerPart:3,progress:{done,_ in if done==3{try! Data("changed!!".utf8).write(to:source)}})}
        try check(try fm.contentsOfDirectory(atPath:changeParts.path).isEmpty,"source change cleanup")
        let raceParts=try folder("race"),raceSource=root.appendingPathComponent("race.bin");try Data("abcdef".utf8).write(to:raceSource)
        try rejects("destination race rolls back own committed parts"){_=try FilePartsService.split(source:raceSource,destination:raceParts,bytesPerPart:3,progress:{done,_ in
            if done==6{try! Data("other writer".utf8).write(to:raceParts.appendingPathComponent("race.002"))}
        })}
        try check(try fm.contentsOfDirectory(atPath:raceParts.path)==["race.002"] && String(contentsOf:raceParts.appendingPathComponent("race.002"),encoding:.utf8)=="other writer","rollback preserves racing writer file")
        let huge=root.appendingPathComponent("thousand");try Data(repeating:1,count:1000).write(to:huge)
        try rejects("999-part limit"){_=try FilePartsService.split(source:huge,destination:cancelParts,bytesPerPart:1)}
        let malicious=try folder("malicious");try Data([1]).write(to:malicious.appendingPathComponent("x.001"));try Data("filename=../escape\r\nsize=1\r\ncrc32=A505DF1B\r\n".utf8).write(to:malicious.appendingPathComponent("x.crc"))
        try rejects("manifest traversal"){_=try FilePartsService.inspect(firstPart:malicious.appendingPathComponent("x.001"))}
        let link=root.appendingPathComponent("link");try fm.createSymbolicLink(at:link,withDestinationURL:source)
        try rejects("symlink source"){_=try FilePartsService.split(source:link,destination:cancelParts,bytesPerPart:1)}
        print("File parts: \(count) checks passed")
    }
}
