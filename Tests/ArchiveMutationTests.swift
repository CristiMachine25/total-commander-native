import Foundation
import Darwin

@main struct ArchiveMutationTests {
    static var checks=0
    static func check(_ value:@autoclosure () throws -> Bool,_ name:String)throws {checks += 1;if try !value(){throw NSError(domain:"ArchiveMutationTests",code:checks,userInfo:[NSLocalizedDescriptionKey:name])}}
    static func rejects(_ name:String,_ work:()throws->Void)throws {var rejected=false;do{try work()}catch{rejected=true};try check(rejected,name)}
    static func main()throws {
        let fm=FileManager.default,root=URL(fileURLWithPath:"/private/tmp").appendingPathComponent("archive-mutation-tests-"+UUID().uuidString)
        try fm.createDirectory(at:root,withIntermediateDirectories:false);defer{try? fm.removeItem(at:root)}
        func directory(_ name:String)throws->URL {let u=root.appendingPathComponent(name);try fm.createDirectory(at:u,withIntermediateDirectories:true);return u}
        func write(_ name:String,_ text:String)throws->URL {let u=root.appendingPathComponent(name);try Data(text.utf8).write(to:u);return u}
        func text(_ s:ArchiveBrowserSession,_ path:String)throws->String {try String(contentsOf:s.readableMember(path),encoding:.utf8)}
        let tool=URL(fileURLWithPath:CommandLine.arguments.count>1 ? CommandLine.arguments[1] : "/opt/homebrew/bin/7zz"),archive=root.appendingPathComponent("test.zip")
        let base=try directory("base"),initial=try write("base/original.txt","original bytes")
        try NativeOperations.pack(sources:[base],archive:archive,tool:tool)
        let original=try ArchiveBrowserSession(archive:archive,tool:tool)
        let added=try write("new.txt","new bytes")
        var session=try ArchiveMutationService.add(session:original,sources:[added],at:"base")
        try check(try text(session,"base/new.txt")=="new bytes" && text(session,"base/original.txt")=="original bytes","Add into internal directory preserves existing bytes")
        try check(session.original==archive && original.node("base/new.txt")==nil,"Returned session targets original while old snapshot remains immutable")
        let unchanged=try NativeOperations.sha256(archive)
        try rejects("Stale original session refuses updates"){_=try ArchiveMutationService.makeDirectory(session:original,path:"stale")}
        try check(try NativeOperations.sha256(archive)==unchanged,"Stale rejection leaves ZIP unchanged")
        try rejects("Default add refuses existing member"){_=try ArchiveMutationService.add(session:session,sources:[added],at:"base")}
        try check(try NativeOperations.sha256(archive)==unchanged,"Collision failure preserves original bytes")
        _=try write("new.txt","replacement bytes")
        session=try ArchiveMutationService.add(session:session,sources:[added],at:"base",overwrite:true)
        try check(try text(session,"base/new.txt")=="replacement bytes","Explicit overwrite updates selected member")
        session=try ArchiveMutationService.makeDirectory(session:session,path:"base/empty")
        try check(session.node("base/empty")?.isDirectory==true,"Creates empty internal directory")
        session=try ArchiveMutationService.rename(session:session,path:"base/new.txt",toName:"renamed.txt")
        try check(session.node("base/new.txt")==nil && (try text(session,"base/renamed.txt"))=="replacement bytes","Rename retains bytes and removes old member name")
        try rejects("Rename refuses collision"){_=try ArchiveMutationService.rename(session:session,path:"base/renamed.txt",toName:"original.txt")}
        let edited=try write("edited.txt","edited member contents")
        session=try ArchiveMutationService.update(session:session,path:"base/renamed.txt",from:edited)
        try check(try text(session,"base/renamed.txt")=="edited member contents","Explicit edited-member update round trips")
        for path in ["../escape","/absolute","base/../escape","base//bad","base/bad\\name","base/C:name","base/\nname"] {
            try rejects("Reject invalid member path \(path)"){_=try ArchiveMutationService.makeDirectory(session:session,path:path)}
        }
        try rejects("Rename cannot move through new-name path"){_=try ArchiveMutationService.rename(session:session,path:"base/original.txt",toName:"../outside")}
        try rejects("Adding into missing parent is explicit error"){_=try ArchiveMutationService.add(session:session,sources:[added],at:"missing")}
        let beforeInvalid=try NativeOperations.sha256(archive)
        let link=root.appendingPathComponent("linked.txt");try fm.createSymbolicLink(at:link,withDestinationURL:initial)
        try rejects("Link source rejected before original change"){_=try ArchiveMutationService.add(session:session,sources:[link],at:"")}
        let fifo=root.appendingPathComponent("pipe");precondition(mkfifo(fifo.path,0o600)==0)
        try rejects("FIFO source rejected without blocking"){_=try ArchiveMutationService.add(session:session,sources:[fifo],at:"")}
        try check(try NativeOperations.sha256(archive)==beforeInvalid,"Failed staging preserves original ZIP")
        let another=try directory("another");_=try write("another/item.txt","tree bytes")
        session=try ArchiveMutationService.add(session:session,sources:[another],at:"")
        try check(try text(session,"another/item.txt")=="tree bytes","Directory addition preserves subtree")
        session=try ArchiveMutationService.delete(session:session,paths:["base/empty","another","another/item.txt"])
        try check(session.node("base/empty")==nil && session.node("another")==nil && session.node("base/original.txt") != nil,"Delete deduplicates selected descendant roots")
        let beforeExternal=try NativeOperations.sha256(archive)
        try Data("external replacement".utf8).write(to:archive)
        try rejects("External replacement cannot be overwritten from stale session"){_=try ArchiveMutationService.delete(session:session,paths:["base"])}
        try check(try String(contentsOf:archive,encoding:.utf8)=="external replacement","External bytes preserved exactly")
        try fm.removeItem(at:archive);try fm.copyItem(at:session.snapshot,to:archive)
        try check(try NativeOperations.sha256(archive)==beforeExternal,"Restored immutable fixture matches prior ZIP")
        session=try ArchiveMutationService.delete(session:session,paths:["base"])
        try check(try session.children(in:"").isEmpty,"Deleting all members produces valid empty ZIP")
        try session.testIntegrity()
        session=try ArchiveMutationService.makeDirectory(session:session,path:"new-folder")
        try check(session.node("new-folder")?.isDirectory==true,"Empty ZIP can be modified again")
        session=try ArchiveMutationService.rename(session:session,path:"new-folder",toName:"New-Folder")
        try check(session.node("New-Folder")?.isDirectory==true && session.node("new-folder")==nil,"Case-only rename changes exact ZIP member spelling")
        let failingTool=try write("bad-tool","#!/bin/sh\nexit 7\n")
        try fm.setAttributes([.posixPermissions:0o700],ofItemAtPath:failingTool.path)
        let failedSession=try ArchiveBrowserSession(archive:archive,tool:failingTool),beforeToolFailure=try NativeOperations.sha256(archive)
        try rejects("External archive tool failure aborts rewrite"){_=try ArchiveMutationService.makeDirectory(session:failedSession,path:"not-created")}
        try check(try NativeOperations.sha256(archive)==beforeToolFailure,"Failed external staging tool leaves original archive byte-identical")
        try check(try fm.contentsOfDirectory(at:root,includingPropertiesForKeys:nil).allSatisfy{!$0.lastPathComponent.hasPrefix(".zip-update-")},"Successful rewrite cleans preserved temporary ZIP")
        // Simultaneous first reads share one lazy extraction and both return bytes.
        let concurrent=try ArchiveBrowserSession(archive:original.snapshot,tool:tool)
        let group=DispatchGroup(),lock=NSLock();var outcomes:[String]=[]
        for _ in 0..<8 {group.enter();DispatchQueue.global().async {defer{group.leave()};let value=(try? String(contentsOf:concurrent.readableMember("base/original.txt"),encoding:.utf8)) ?? "ERROR";lock.lock();outcomes.append(value);lock.unlock()}}
        try check(group.wait(timeout:.now()+10) == .success && outcomes.count==8 && outcomes.allSatisfy{$0=="original bytes"},"Concurrent lazy materialization extracts once safely")
        print("PASS: \(checks) archive mutation assertions")
    }
}
