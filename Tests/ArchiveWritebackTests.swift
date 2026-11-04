import Foundation

private final class MockArchiveRemote:ArchiveRemoteTransport {
    var files:[String:Data]=[:]
    var uploads=0
    var failInstall=false
    var corruptInstall=false
    func metadata(_ path:String)throws->FTPEntry {
        guard let bytes=files[path] else{throw ArchiveBrowserError.message("Missing remote "+path)}
        return FTPEntry(name:(path as NSString).lastPathComponent,kind:.file,size:UInt64(bytes.count),modifiedAt:Date(timeIntervalSince1970:0))
    }
    func download(_ path:String,to:URL)throws {guard let bytes=files[path] else{throw ArchiveBrowserError.message("Missing remote")};try bytes.write(to:to,options:.withoutOverwriting)}
    func upload(_ local:URL,to:String)throws {guard files[to]==nil else{throw ArchiveBrowserError.message("Remote exists")};uploads += 1;files[to]=try Data(contentsOf:local)}
    func rename(_ from:String,to:String)throws {
        guard files[to]==nil,let bytes=files[from] else{throw ArchiveBrowserError.message("Cannot rename")}
        if from.contains(".tc-zip-stage-") && failInstall {throw ArchiveBrowserError.message("Simulated install failure")}
        files[to]=from.contains(".tc-zip-stage-") && corruptInstall ? Data("corrupt remote".utf8) : bytes;files.removeValue(forKey:from)
    }
    func remove(_ path:String)throws {files.removeValue(forKey:path)}
}
@main struct ArchiveWritebackTests {
    static var checks=0
    static func check(_ value:@autoclosure ()throws->Bool,_ message:String)throws{checks += 1;if try !value(){throw NSError(domain:"ArchiveWritebackTests",code:checks,userInfo:[NSLocalizedDescriptionKey:message])}}
    static func rejects(_ message:String,_ work:()throws->Void)throws{var rejected=false;do{try work()}catch{rejected=true};try check(rejected,message)}
    static func main()throws{
        let fm=FileManager.default,root=URL(fileURLWithPath:"/private/tmp").appendingPathComponent("archive-writeback-tests-"+UUID().uuidString)
        try fm.createDirectory(at:root,withIntermediateDirectories:false);defer{try? fm.removeItem(at:root)}
        let tool=URL(fileURLWithPath:CommandLine.arguments.count>1 ? CommandLine.arguments[1] : "/opt/homebrew/bin/7zz"),recovery=root.appendingPathComponent("recovery")
        let note=root.appendingPathComponent("note.txt"),inner=root.appendingPathComponent("inner.zip"),outer=root.appendingPathComponent("outer.zip")
        try Data("before".utf8).write(to:note);try NativeOperations.pack(sources:[note],archive:inner,tool:tool);try NativeOperations.pack(sources:[inner],archive:outer,tool:tool)
        let outerSession=try ArchiveBrowserSession(archive:outer,tool:tool),cachedInner=try outerSession.readableMember("inner.zip")
        let nestedOpened=try ArchiveBrowserSession(archive:cachedInner,tool:tool),workspace=try ArchiveWritebackWorkspace(copying:nestedOpened)
        let nested=try ArchiveBrowserSession(archive:workspace.url,tool:tool)
        let initialCache=try NativeOperations.sha256(cachedInner),origin=ArchiveWritebackOrigin.nested(parent:outerSession,path:"inner.zip",origin:.local,workspace:workspace)
        try Data("after".utf8).write(to:note)
        let newInner=try ArchiveMutationService.update(session:nested,path:"note.txt",from:note)
        try check(try NativeOperations.sha256(cachedInner)==initialCache,"Nested working rewrite leaves parent snapshot cache immutable")
        let committed=try ArchiveWritebackService.commit(old:nested,new:newInner,origin:origin,recoveryDirectory:recovery)
        let reopenedOuter=try ArchiveBrowserSession(archive:outer,tool:tool),reopenedInner=try ArchiveBrowserSession(archive:reopenedOuter.readableMember("inner.zip"),tool:tool)
        try check(try String(contentsOf:reopenedInner.readableMember("note.txt"),encoding:.utf8)=="after","Nested edit reaches actual outer ZIP")
        try check(committed.changes.count==2 && committed.changes[0].old === outerSession && committed.changes[1].old === nested,"Writeback reports changed enclosing and child sessions")
        try check(try NativeOperations.sha256(cachedInner)==initialCache,"Successful nested writeback does not mutate old parent cache")
        let advanced=try ArchiveMutationService.makeDirectory(session:committed.session,path:"second")
        let twice=try ArchiveWritebackService.commit(old:committed.session,new:advanced,origin:committed.origin,recoveryDirectory:recovery)
        try check(twice.changes.count==2,"Advanced origin supports repeated nested mutations")
        // External modification of the outer ZIP must preserve the user's new outer data.
        let outerBefore=try Data(contentsOf:outer);try Data("external outer".utf8).write(to:outer)
        let failedInner=try ArchiveMutationService.makeDirectory(session:twice.session,path:"failed")
        try rejects("Changed enclosing ZIP rejects nested update"){_=try ArchiveWritebackService.commit(old:twice.session,new:failedInner,origin:twice.origin,recoveryDirectory:recovery)}
        try check(try String(contentsOf:outer,encoding:.utf8)=="external outer","Stale outer ZIP preserved exactly")
        try check(try NativeOperations.sha256(workspace.url)==NativeOperations.sha256(twice.session.snapshot),"Failed nested update restores only owned workspace for retry")
        try check(try fm.contentsOfDirectory(at:recovery,includingPropertiesForKeys:nil).count==1,"Failed nested edit retained as recovery ZIP")
        try outerBefore.write(to:outer)
        let originalRemoteBytes=try Data(contentsOf:inner)
        func remoteFixture(_ remote:MockArchiveRemote)throws->(ArchiveBrowserSession,ArchiveWritebackOrigin,ArchiveWritebackWorkspace){
            remote.files["/remote.zip"]=originalRemoteBytes
            let opened=try ArchiveBrowserSession(archive:inner,tool:tool),work=try ArchiveWritebackWorkspace(copying:opened),session=try ArchiveBrowserSession(archive:work.url,tool:tool)
            return(session,.remote(transport:remote,path:"/remote.zip",workspace:work),work)
        }
        let remote=MockArchiveRemote(),(remoteSession,remoteOrigin,remoteWork)=try remoteFixture(remote)
        let remoteNew=try ArchiveMutationService.makeDirectory(session:remoteSession,path:"remote-change")
        let remoteResult=try ArchiveWritebackService.commit(old:remoteSession,new:remoteNew,origin:remoteOrigin,recoveryDirectory:recovery)
        try check(remote.files["/remote.zip"] == Data(contentsOf:remoteNew.snapshot),"Remote writeback installs verified updated bytes")
        let backups=remote.files.keys.filter{$0.contains(".tc-zip-original-")}
        try check(backups.count==1 && remote.files[backups[0]]==originalRemoteBytes,"Remote original retained under recovery name")
        try check(!remoteResult.warnings.isEmpty && !remote.files.keys.contains{$0.contains(".tc-zip-stage-")},"Successful writeback reports backup and consumes staging name")
        let secondRemote=try ArchiveMutationService.makeDirectory(session:remoteResult.session,path:"again")
        _=try ArchiveWritebackService.commit(old:remoteResult.session,new:secondRemote,origin:remoteResult.origin,recoveryDirectory:recovery)
        try check(remote.uploads==2,"Remote origin supports sequential verified edits")
        let staleRemote=MockArchiveRemote(),(staleSession,staleOrigin,staleWork)=try remoteFixture(staleRemote)
        let staleNew=try ArchiveMutationService.makeDirectory(session:staleSession,path:"mine")
        staleRemote.files["/remote.zip"]=Data("external remote".utf8)
        try rejects("Changed remote ZIP rejects overwrite"){_=try ArchiveWritebackService.commit(old:staleSession,new:staleNew,origin:staleOrigin,recoveryDirectory:recovery)}
        try check(staleRemote.uploads==0 && staleRemote.files["/remote.zip"]==Data("external remote".utf8),"Stale remote refuses even staging upload")
        try check(try NativeOperations.sha256(staleWork.url)==NativeOperations.sha256(staleSession.snapshot),"Failed remote update resets private workspace")
        let failedRemote=MockArchiveRemote(),(failedSession,failedOrigin,_)=try remoteFixture(failedRemote);failedRemote.failInstall=true
        let failedNew=try ArchiveMutationService.makeDirectory(session:failedSession,path:"mine")
        try rejects("Remote install rename failure reported"){_=try ArchiveWritebackService.commit(old:failedSession,new:failedNew,origin:failedOrigin,recoveryDirectory:recovery)}
        try check(failedRemote.files["/remote.zip"]==originalRemoteBytes,"Failed remote install restores original when name remains absent")
        let corruptRemote=MockArchiveRemote(),(corruptSession,corruptOrigin,_)=try remoteFixture(corruptRemote);corruptRemote.corruptInstall=true
        let corruptNew=try ArchiveMutationService.makeDirectory(session:corruptSession,path:"mine")
        try rejects("Installed remote bytes verified"){_=try ArchiveWritebackService.commit(old:corruptSession,new:corruptNew,origin:corruptOrigin,recoveryDirectory:recovery)}
        try check(corruptRemote.files.values.contains(originalRemoteBytes),"Post-install failure retains remote original backup")
        // Test whole chain: nested archive inside FTP archive.
        let chainRemote=MockArchiveRemote();chainRemote.files["/outer.zip"]=try Data(contentsOf:outer)
        let chainOpened=try ArchiveBrowserSession(archive:outer,tool:tool),chainWork=try ArchiveWritebackWorkspace(copying:chainOpened),chainParent=try ArchiveBrowserSession(archive:chainWork.url,tool:tool)
        let chainParentOrigin=ArchiveWritebackOrigin.remote(transport:chainRemote,path:"/outer.zip",workspace:chainWork)
        let chainChildOpened=try ArchiveBrowserSession(archive:chainParent.readableMember("inner.zip"),tool:tool),chainChildWork=try ArchiveWritebackWorkspace(copying:chainChildOpened),chainChild=try ArchiveBrowserSession(archive:chainChildWork.url,tool:tool)
        let chainOrigin=ArchiveWritebackOrigin.nested(parent:chainParent,path:"inner.zip",origin:chainParentOrigin,workspace:chainChildWork)
        let chainNew=try ArchiveMutationService.makeDirectory(session:chainChild,path:"inside-remote")
        let chainResult=try ArchiveWritebackService.commit(old:chainChild,new:chainNew,origin:chainOrigin,recoveryDirectory:recovery)
        let downloaded=root.appendingPathComponent("downloaded.zip");try chainRemote.files["/outer.zip"]!.write(to:downloaded)
        let chainVerified=try ArchiveBrowserSession(archive:downloaded,tool:tool),chainMember=try ArchiveBrowserSession(archive:chainVerified.readableMember("inner.zip"),tool:tool)
        try check(chainMember.node("inside-remote")?.isDirectory==true && chainResult.changes.count==2,"Nested FTP ZIP edit propagates through enclosing ZIP to remote server")
        var editorOrigin=chainResult.origin
        let editor=try ArchiveEditSession.prepare(session:chainResult.session,path:"note.txt",writeback:{old,new in
            let result=try ArchiveWritebackService.commit(old:old,new:new,origin:editorOrigin,recoveryDirectory:recovery)
            editorOrigin=result.origin;return result.session
        })
        try Data("editor to remote nested ZIP".utf8).write(to:editor.localURL,options:.atomic)
        _=try editor.uploadSavedChanges()
        try check(!editor.hasPendingChanges,"Archive editor only marks saved after enclosing FTP writeback succeeds")
        try Data("pending after stale remote".utf8).write(to:editor.localURL,options:.atomic)
        chainRemote.files["/outer.zip"]=Data("another writer".utf8)
        try rejects("Archive editor propagates remote writeback failure"){_=try editor.uploadSavedChanges()}
        try check(editor.hasPendingChanges && chainRemote.files["/outer.zip"]==Data("another writer".utf8),"Failed editor writeback retains local text and remote intervening data")
        try editor.discardAndClose()
        let moveRemote=MockArchiveRemote(),(moveArchive,moveOrigin,_)=try remoteFixture(moveRemote)
        moveRemote.files["/remote.zip"]=Data("stale remote".utf8)
        let moveSource=root.appendingPathComponent("move-source");try fm.createDirectory(at:moveSource,withIntermediateDirectories:false)
        let moving=moveSource.appendingPathComponent("moving.txt");try Data("must stay local".utf8).write(to:moving)
        let moveLocation=PaneLocation.local(moveSource),moveEntries=try moveLocation.list(showHidden:true)
        try rejects("Provider move aborts before source removal if archive writeback fails"){
            _=try ProviderTransferService.transfer(entries:moveEntries,source:moveLocation,target:.archive(moveArchive,path:""),move:true,archiveCommit:{old,new in
                try ArchiveWritebackService.commit(old:old,new:new,origin:moveOrigin,recoveryDirectory:recovery).session
            })
        }
        try check(try String(contentsOf:moving,encoding:.utf8)=="must stay local" && moveRemote.files["/remote.zip"]==Data("stale remote".utf8),"Failed destination writeback preserves move source and remote ZIP")
        _=remoteWork
        print("PASS: \(checks) archive writeback assertions")
    }
}
