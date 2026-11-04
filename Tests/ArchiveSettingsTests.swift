import Foundation

@main struct ArchiveSettingsTests {
    static var count=0
    static func check(_ value:@autoclosure ()throws->Bool,_ message:String)throws {count += 1;if try !value(){throw NSError(domain:"ArchiveSettingsTests",code:count,userInfo:[NSLocalizedDescriptionKey:message])}}
    static func rejects(_ message:String,_ work:()throws->Void)throws {var rejected=false;do{try work()}catch{rejected=true};try check(rejected,message)}
    static func main()throws {
        let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("archive-settings-"+UUID().uuidString)
        try fm.createDirectory(at:root,withIntermediateDirectories:false);defer{try? fm.removeItem(at:root)}
        let tool=URL(fileURLWithPath:CommandLine.arguments[1]),source=root.appendingPathComponent("fixture.txt")
        try Data(repeating:65,count:64*1024).write(to:source)
        let date=Date(timeIntervalSince1970:1_600_000_000)
        try fm.setAttributes([.modificationDate:date],ofItemAtPath:source.path)
        let stored=root.appendingPathComponent("stored.zip"),compressed=root.appendingPathComponent("compressed.zip")
        try NativeOperations.pack(sources:[source],archive:stored,tool:tool,options:.init(compressionLevel:0,verifyAfterPacking:true,setDateToNewest:true))
        try NativeOperations.pack(sources:[source],archive:compressed,tool:tool,options:.init(compressionLevel:9,verifyAfterPacking:true,setDateToNewest:false))
        let raw=try Data(contentsOf:stored),zipped=try Data(contentsOf:compressed)
        try check(raw[8]==0 && raw[9]==0,"Store level uses ZIP method 0")
        try check(zipped[8]==8 && zipped[9]==0,"Compressed level uses deflate")
        try check(zipped.count<raw.count/4,"Compression setting has material output effect")
        try check(abs((try fm.attributesOfItem(atPath:stored.path)[.modificationDate] as! Date).timeIntervalSince(date))<1,"Newest timestamp applied")
        try check(abs((try fm.attributesOfItem(atPath:compressed.path)[.modificationDate] as! Date).timeIntervalSinceNow)<30,"Disabled newest-date keeps creation time")
        let folder=root.appendingPathComponent("nested");try fm.createDirectory(at:folder,withIntermediateDirectories:false)
        let child=folder.appendingPathComponent("child.txt");try Data("nested".utf8).write(to:child)
        let later=date.addingTimeInterval(3600);try fm.setAttributes([.modificationDate:later],ofItemAtPath:child.path)
        let nested=root.appendingPathComponent("nested.zip")
        try NativeOperations.pack(sources:[source,folder],archive:nested,tool:tool,options:.init(setDateToNewest:true))
        try check(abs((try fm.attributesOfItem(atPath:nested.path)[.modificationDate] as! Date).timeIntervalSince(later))<1,"Newest date includes recursive files")
        let bad=root.appendingPathComponent("bad.zip")
        try rejects("Out-of-range compression refused"){try NativeOperations.pack(sources:[source],archive:bad,tool:tool,options:.init(compressionLevel:10))}
        try check(!fm.fileExists(atPath:bad.path),"Invalid settings create no archive")
        let wrapper=root.appendingPathComponent("test-failing-tool")
        let quoted="'"+tool.path.replacingOccurrences(of:"'",with:"'\\''")+"'"
        try ("#!/bin/sh\nif [ \"$1\" = t ]; then exit 42; fi\nexec "+quoted+" \"$@\"\n").write(to:wrapper,atomically:true,encoding:.utf8)
        try fm.setAttributes([.posixPermissions:0o700],ofItemAtPath:wrapper.path)
        try rejects("Enabled verification runs full integrity check"){try NativeOperations.pack(sources:[source],archive:bad,tool:wrapper)}
        try check(!fm.fileExists(atPath:bad.path),"Failed integrity check does not publish archive")
        try NativeOperations.pack(sources:[source],archive:bad,tool:wrapper,options:.init(verifyAfterPacking:false))
        try check(fm.fileExists(atPath:bad.path),"Disabled optional verification skips full integrity command")
        try check(try fm.contentsOfDirectory(atPath:root.path).allSatisfy{!$0.hasPrefix(".archive-")},"Temporary packing files cleaned")
        print("PASS: \(count) archive setting assertions")
    }
}
