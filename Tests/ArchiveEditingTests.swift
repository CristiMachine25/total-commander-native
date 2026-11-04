import Foundation
import Darwin

@main struct ArchiveEditingTests {
    static var count=0
    static func check(_ value:@autoclosure ()throws->Bool,_ message:String)throws{count += 1;if try !value(){throw NSError(domain:"ArchiveEditingTests",code:count,userInfo:[NSLocalizedDescriptionKey:message])}}
    static func rejects(_ message:String,_ work:()throws->Void)throws{var rejected=false;do{try work()}catch{rejected=true};try check(rejected,message)}
    static func main()throws{
        let fm=FileManager.default,root=URL(fileURLWithPath:"/private/tmp").appendingPathComponent("archive-edit-tests-"+UUID().uuidString)
        try fm.createDirectory(at:root,withIntermediateDirectories:false);defer{try? fm.removeItem(at:root)}
        let source=root.appendingPathComponent("note.txt"),archive=root.appendingPathComponent("example.zip"),tool=URL(fileURLWithPath:CommandLine.arguments.count>1 ? CommandLine.arguments[1] : "/opt/homebrew/bin/7zz")
        try Data("original".utf8).write(to:source);try NativeOperations.pack(sources:[source],archive:archive,tool:tool)
        let initial=try ArchiveBrowserSession(archive:archive,tool:tool)
        let editor=try ArchiveEditSession.prepare(session:initial,path:"note.txt")
        try check(!editor.hasPendingChanges && editor.localURL != initial.readableMember("note.txt"),"Editor uses separate writable private file")
        try Data("first saved change".utf8).write(to:editor.localURL,options:.atomic)
        try check(editor.hasPendingChanges && String(contentsOf:initial.readableMember("note.txt"),encoding:.utf8)=="original","Saved edits leave archive snapshot unchanged")
        let updated=try editor.uploadSavedChanges()
        try check(!editor.hasPendingChanges && String(contentsOf:updated.readableMember("note.txt"),encoding:.utf8)=="first saved change","Saved changes rewrite archive and advance baseline")
        try check(editor.archiveSession === updated,"Editor uses new session for subsequent saves")
        try Data("second saved change".utf8).write(to:editor.localURL,options:.atomic)
        let second=try editor.uploadSavedChanges()
        try check(try String(contentsOf:second.readableMember("note.txt"),encoding:.utf8)=="second saved change","Repeated saved edits work from updated snapshot")
        let before=try NativeOperations.sha256(archive)
        let unchanged=try editor.uploadSavedChanges()
        try check(unchanged === second && NativeOperations.sha256(archive)==before,"No-change update does not rewrite ZIP")
        try Data("pending recovery".utf8).write(to:editor.localURL,options:.atomic)
        let external=try ArchiveMutationService.makeDirectory(session:second,path:"external")
        let externalHash=try NativeOperations.sha256(archive)
        try rejects("Stale ZIP refuses editor save-back"){_=try editor.uploadSavedChanges()}
        try check(editor.hasPendingChanges && NativeOperations.sha256(archive)==externalHash,"Failed stale update retains private edits and newer ZIP")
        let recovery=root.appendingPathComponent("recovery.txt");try editor.exportChanges(to:recovery)
        try check(try String(contentsOf:recovery,encoding:.utf8)=="pending recovery","Pending changes export after stale update")
        try rejects("Export refuses existing local file"){try editor.exportChanges(to:recovery)}
        let local=editor.localURL;try editor.discardAndClose()
        try check(!fm.fileExists(atPath:local.path),"Explicit discard cleans editor temporary file")
        try rejects("Closed editor cannot update"){_=try editor.uploadSavedChanges()}
        let linkEdit=try ArchiveEditSession.prepare(session:external,path:"note.txt")
        try fm.removeItem(at:linkEdit.localURL);try fm.createSymbolicLink(at:linkEdit.localURL,withDestinationURL:source)
        try rejects("Replaced private file symlink is not read or packed"){_=try linkEdit.uploadSavedChanges()}
        try check(try String(contentsOf:source,encoding:.utf8)=="original" && linkEdit.hasPendingChanges,"Outside symlink target untouched and failed edits stay pending")
        try linkEdit.discardAndClose()
        let fifoEdit=try ArchiveEditSession.prepare(session:external,path:"note.txt")
        try fm.removeItem(at:fifoEdit.localURL);precondition(mkfifo(fifoEdit.localURL.path,0o600)==0)
        try rejects("FIFO replacement fails without blocking"){_=try fifoEdit.uploadSavedChanges()}
        try fifoEdit.discardAndClose()
        var abandoned:ArchiveEditSession?=try ArchiveEditSession.prepare(session:external,path:"note.txt")
        let abandonedURL=abandoned!.localURL
        try Data("recover after release".utf8).write(to:abandonedURL,options:.atomic);abandoned=nil
        try check(try String(contentsOf:abandonedURL,encoding:.utf8)=="recover after release","Releasing session does not erase pending failed/unpacked edits")
        try fm.removeItem(at:abandonedURL.deletingLastPathComponent())
        try rejects("Archive directories cannot be text-edited"){_=try ArchiveEditSession.prepare(session:external,path:"external")}
        try check(try NativeOperations.sha256(archive)==externalHash,"Rejected operations leave archive byte-identical")
        print("PASS: \(count) archive editing assertions")
    }
}
