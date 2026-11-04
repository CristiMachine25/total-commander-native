import Foundation
import Darwin

@main struct ArchiveBrowserTests {
    static var checks=0
    static func check(_ condition:@autoclosure () throws -> Bool,_ name:String)throws{checks += 1;if try !condition(){throw NSError(domain:"ArchiveBrowserTests",code:checks,userInfo:[NSLocalizedDescriptionKey:name])}}
    static func rejects(_ name:String,_ body:()throws->Void)throws{var rejected=false;do{try body()}catch{rejected=true};try check(rejected,name)}
    static func zip(_ entries:[(String,Data)]) -> Data {
        func bytes(_ n:UInt32,_ count:Int)->[UInt8]{(0..<count).map{UInt8((n >> (8*$0)) & 255)}}
        var local=Data(),directory=Data()
        for (name,payload) in entries {
            var crc:UInt32=0xffffffff
            for byte in payload{crc ^= UInt32(byte);for _ in 0..<8{crc=(crc >> 1) ^ ((crc & 1)==1 ? 0xedb88320 : 0)}};crc ^= 0xffffffff
            let filename=Data(name.utf8),offset=UInt32(local.count)
            for (value,count) in [(UInt32(0x04034b50),4),(20,2),(0x800,2),(0,2),(0,2),(0,2),(crc,4),(UInt32(payload.count),4),(UInt32(payload.count),4),(UInt32(filename.count),2),(0,2)]{local.append(contentsOf:bytes(value,count))}
            local.append(filename);local.append(payload)
            for (value,count) in [(UInt32(0x02014b50),4),(20,2),(20,2),(0x800,2),(0,2),(0,2),(0,2),(crc,4),(UInt32(payload.count),4),(UInt32(payload.count),4),(UInt32(filename.count),2),(0,2),(0,2),(0,2),(0,2),(0,4),(offset,4)]{directory.append(contentsOf:bytes(value,count))}
            directory.append(filename)
        }
        var end=Data()
        for(value,count)in[(UInt32(0x06054b50),4),(0,2),(0,2),(UInt32(entries.count),2),(UInt32(entries.count),2),(UInt32(directory.count),4),(UInt32(local.count),4),(0,2)]{end.append(contentsOf:bytes(value,count))}
        return local+directory+end
    }
    static func main()throws{
        let fm=FileManager.default,base=URL(fileURLWithPath:"/private/tmp").appendingPathComponent("archive-browser-tests-"+UUID().uuidString)
        try fm.createDirectory(at:base,withIntermediateDirectories:true);defer{try? fm.removeItem(at:base)}
        let tool=URL(fileURLWithPath:CommandLine.arguments.count>1 ? CommandLine.arguments[1] : "/opt/homebrew/bin/7zz")
        let archive=base.appendingPathComponent("example.zip")
        let content=zip([("folder/deeper/file.txt",Data("hello".utf8)),("folder/other.txt",Data("other".utf8)),("root.txt",Data("root".utf8)),("empty/",Data())])
        try content.write(to:archive)
        let before=try NativeOperations.sha256(archive)
        let session=try ArchiveBrowserSession(archive:archive,tool:tool)
        let root=try session.children(in:"")
        try check(root.map(\.path)==["empty","folder","root.txt"],"Implicit directories listed before files")
        try check(try session.children(in:"folder").map(\.path)==["folder/deeper","folder/other.txt"],"Nested virtual directory listing")
        try check(session.node("folder/deeper")?.isDirectory==true,"Implicit nested parent synthesized")
        try check(try session.children(in:"empty").isEmpty,"Empty directory navigable")
        try rejects("Unknown virtual path rejects"){_=try session.children(in:"../escape")}
        try rejects("File cannot become directory"){_=try session.children(in:"root.txt")}
        try rejects("Unknown member cannot be viewed"){_=try session.readableMember("../outside")}
        try rejects("Directory cannot be viewed as file"){_=try session.readableMember("folder")}
        try check(try session.selectedRoots(["folder","folder/deeper/file.txt","root.txt"]) == ["folder","root.txt"],"Overlapping selection deduplicated")
        try session.testIntegrity();try check(true,"Streaming archive integrity test passes")
        let preview=try session.readableMember("folder/deeper/file.txt")
        try check(try Data(contentsOf:preview)==Data("hello".utf8),"Read-only member materialization exact")
        try check(try NativeOperations.sha256(archive)==before,"Browsing and integrity do not change original")
        try Data("replaced original".utf8).write(to:archive,options:.atomic)
        try check(try Data(contentsOf:session.readableMember("folder/other.txt"))==Data("other".utf8),"Session remains bound to immutable snapshot after original replacement")
        let target=base.appendingPathComponent("target");try fm.createDirectory(at:target,withIntermediateDirectories:false)
        let count=try session.extract(paths:["folder/deeper/file.txt"],to:target)
        try check(count==1 && (try Data(contentsOf:target.appendingPathComponent("folder/deeper/file.txt")))==Data("hello".utf8),"Selected extraction preserves full internal path")
        try check(!fm.fileExists(atPath:target.appendingPathComponent("folder/other.txt").path),"Unselected member not extracted")
        try rejects("Existing target roots not overwritten"){_=try session.extract(paths:["folder/other.txt"],to:target)}
        try check(try Data(contentsOf:target.appendingPathComponent("folder/deeper/file.txt"))==Data("hello".utf8),"Collision preserves previous target bytes")
        let link=base.appendingPathComponent("target-link");try fm.createSymbolicLink(at:link,withDestinationURL:target)
        try rejects("Symlink destination rejected"){_=try session.extract(paths:["root.txt"],to:link)}
        let hostile=base.appendingPathComponent("hostile.zip");try zip([("../escape",Data("bad".utf8))]).write(to:hostile)
        try rejects("Traversal archive rejected before browsing"){_=try ArchiveBrowserSession(archive:hostile,tool:tool)}
        let aliases=base.appendingPathComponent("alias.zip");try zip([("Folder/a",Data()),("folder/b",Data())]).write(to:aliases)
        try rejects("Implicit case-colliding directories rejected"){_=try ArchiveBrowserSession(archive:aliases,tool:tool)}
        let collision=base.appendingPathComponent("collision.zip");try zip([("a",Data("file".utf8)),("a/b",Data())]).write(to:collision)
        try rejects("File-parent collision rejected"){_=try ArchiveBrowserSession(archive:collision,tool:tool)}
        let corrupt=base.appendingPathComponent("crc.zip");var broken=zip([("file",Data("payload".utf8))]);broken[34] ^= 0xff;try broken.write(to:corrupt)
        try rejects("Opening catches corrupt member CRC before browsing"){_ = try ArchiveBrowserSession(archive:corrupt,tool:tool)}
        let corruptOutput=base.appendingPathComponent("corrupt-output");try fm.createDirectory(at:corruptOutput,withIntermediateDirectories:false)
        try rejects("Corrupt archive cannot be extracted"){try NativeOperations.unpack(archive:corrupt,destination:corruptOutput,tool:tool)}
        let archiveLink=base.appendingPathComponent("source-link.zip");try fm.createSymbolicLink(at:archiveLink,withDestinationURL:corrupt)
        try rejects("Symlink archive source rejected"){_=try ArchiveBrowserSession(archive:archiveLink,tool:tool)}
        let fifo=base.appendingPathComponent("source-fifo.zip")
        guard mkfifo(fifo.path,0o600)==0 else {throw NSError(domain:"ArchiveBrowserTests",code:90)}
        let fifoStart=Date()
        try rejects("FIFO archive source rejected without waiting for writer"){_=try ArchiveBrowserSession(archive:fifo,tool:tool)}
        try check(Date().timeIntervalSince(fifoStart)<5,"FIFO archive rejection returns promptly")
        let empty=base.appendingPathComponent("empty.zip");try zip([]).write(to:empty)
        let emptySession=try ArchiveBrowserSession(archive:empty,tool:tool)
        try check(try emptySession.children(in:"").isEmpty,"Empty ZIP lists no members")
        print("PASS: \(checks) archive browser assertions")
    }
}
