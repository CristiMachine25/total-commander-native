import Foundation

protocol ArchiveRemoteTransport {
    func metadata(_ path:String)throws->FTPEntry
    func download(_ path:String,to:URL)throws
    func upload(_ local:URL,to:String)throws
    func rename(_ from:String,to:String)throws
    func remove(_ path:String)throws
}
struct FTPArchiveTransport:ArchiveRemoteTransport {
    let client:FTPClient
    func metadata(_ path:String)throws->FTPEntry {
        let parent=(path as NSString).deletingLastPathComponent,name=(path as NSString).lastPathComponent
        guard let entry=try client.list(path:parent).first(where:{$0.name==name}),entry.kind == .file,let size=entry.size,size<=536_870_912 else {throw ArchiveBrowserError.message("The remote ZIP disappeared, changed type, or exceeds 512 MiB.")};return entry
    }
    func download(_ path:String,to:URL)throws {try client.download(remotePath:path,to:to,maxBytes:536_870_912)}
    func upload(_ local:URL,to:String)throws {try client.upload(localFile:local,remotePath:to,overwrite:false)}
    func rename(_ from:String,to:String)throws {try client.rename(from:from,to:to)}
    func remove(_ path:String)throws {try client.delete(remotePath:path)}
}
/// Independent writable ZIP copy. In particular, nested editing never overwrites
/// a parent session's cached extracted member.
final class ArchiveWritebackWorkspace {
    let directory:URL
    let url:URL
    var preserveForRecovery=false
    init(copying session:ArchiveBrowserSession)throws {
        directory=FileManager.default.temporaryDirectory.appendingPathComponent("archive-working-"+UUID().uuidString)
        url=directory.appendingPathComponent(session.original.lastPathComponent)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        do {try FileManager.default.copyItem(at:session.snapshot,to:url)}catch{try? FileManager.default.removeItem(at:directory);throw error}
    }
    deinit {if !preserveForRecovery{try? FileManager.default.removeItem(at:directory)}}
}
indirect enum ArchiveWritebackOrigin {
    case local
    case nested(parent:ArchiveBrowserSession,path:String,origin:ArchiveWritebackOrigin,workspace:ArchiveWritebackWorkspace)
    case remote(transport:ArchiveRemoteTransport,path:String,workspace:ArchiveWritebackWorkspace)
    var workspace:ArchiveWritebackWorkspace? {switch self {case .local:return nil;case .nested(_,_,_,let workspace),.remote(_,_,let workspace):return workspace}}
}
struct ArchiveSessionChange {
    let old:ArchiveBrowserSession
    let new:ArchiveBrowserSession
    let origin:ArchiveWritebackOrigin
}
struct ArchiveWritebackResult {
    let session:ArchiveBrowserSession
    let origin:ArchiveWritebackOrigin
    let changes:[ArchiveSessionChange]
    let warnings:[String]
}

enum ArchiveWritebackService {
    private static let fm=FileManager.default
    /// The provided mutation already rewrote old.original. Propagate it through
    /// each enclosing provider. On failure preserve the edited ZIP and reset only
    /// owned private working copies; never reset a user's or remote original.
    static func commit(old:ArchiveBrowserSession,new:ArchiveBrowserSession,origin:ArchiveWritebackOrigin,recoveryDirectory:URL?=nil)throws->ArchiveWritebackResult {
        do {
            switch origin {
            case .local:return ArchiveWritebackResult(session:new,origin:origin,changes:[.init(old:old,new:new,origin:origin)],warnings:[])
            case .nested(let parent,let path,let parentOrigin,let workspace):
                try validateWorkspace(old,workspace)
                let changedParent=try ArchiveMutationService.update(session:parent,path:path,from:new.snapshot)
                let propagated=try commit(old:parent,new:changedParent,origin:parentOrigin,recoveryDirectory:recoveryDirectory)
                let advanced=ArchiveWritebackOrigin.nested(parent:propagated.session,path:path,origin:propagated.origin,workspace:workspace)
                return ArchiveWritebackResult(session:new,origin:advanced,changes:propagated.changes+[.init(old:old,new:new,origin:advanced)],warnings:propagated.warnings)
            case .remote(let transport,let path,let workspace):
                try validateWorkspace(old,workspace)
                let backup=try replaceRemote(old:old,new:new,path:path,transport:transport)
                return ArchiveWritebackResult(session:new,origin:origin,changes:[.init(old:old,new:new,origin:origin)],warnings:["Remote original retained for recovery: "+backup])
            }
        } catch {
            guard let workspace=origin.workspace else{throw error}
            var recovery=workspace.url.path
            do {
                let root=recoveryDirectory ?? fm.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Total Commander Native/Archive Recovery")
                try fm.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
                let saved=root.appendingPathComponent("Recovered-"+UUID().uuidString+".zip")
                try fm.copyItem(at:new.snapshot,to:saved);recovery=saved.path
                // Only an explicitly-owned private workspace may be restored.
                try validateWorkspace(old,workspace)
                let reset=workspace.directory.appendingPathComponent(".reset-"+UUID().uuidString)
                try fm.copyItem(at:old.snapshot,to:reset)
                guard rename(reset.path,workspace.url.path)==0 else {try? fm.removeItem(at:reset);throw ArchiveBrowserError.message("Cannot reset private ZIP workspace.")}
            } catch {workspace.preserveForRecovery=true}
            throw ArchiveBrowserError.message(error.localizedDescription+"\nUpdated ZIP recovery copy: "+recovery)
        }
    }
    private static func validateWorkspace(_ session:ArchiveBrowserSession,_ workspace:ArchiveWritebackWorkspace)throws {
        guard session.original.standardizedFileURL.path==workspace.url.standardizedFileURL.path else {throw ArchiveBrowserError.message("Archive workspace identity mismatch.")}
    }
    private static func replaceRemote(old:ArchiveBrowserSession,new:ArchiveBrowserSession,path:String,transport:ArchiveRemoteTransport)throws->String {
        let temporary=fm.temporaryDirectory.appendingPathComponent("archive-remote-check-"+UUID().uuidString)
        try fm.createDirectory(at:temporary,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);defer{try? fm.removeItem(at:temporary)}
        let expected=try NativeOperations.sha256(old.snapshot),replacement=try NativeOperations.sha256(new.snapshot)
        var counter=0
        func checkedHash(_ path:String)throws->String {
            let before=try transport.metadata(path)
            guard before.kind == .file,let size=before.size,size<=536_870_912 else {throw ArchiveBrowserError.message("Remote item is not a bounded regular ZIP.")}
            counter += 1;let file=temporary.appendingPathComponent("check-\(counter)")
            try transport.download(path,to:file)
            guard before == (try transport.metadata(path)) else {throw ArchiveBrowserError.message("Remote ZIP changed during verification.")}
            return try NativeOperations.sha256(file)
        }
        guard try checkedHash(path)==expected else {throw ArchiveBrowserError.message("Remote ZIP changed since opening. It was not overwritten.")}
        let parent=(path as NSString).deletingLastPathComponent
        let staged=try FTPClient.childPath(parent,name:".tc-zip-stage-"+UUID().uuidString+".zip")
        let backup=try FTPClient.childPath(parent,name:".tc-zip-original-"+UUID().uuidString+".zip")
        var movedOriginal=false,installed=false,uploaded=false
        do {
            try transport.upload(new.snapshot,to:staged);uploaded=true
            guard try checkedHash(staged)==replacement else {throw ArchiveBrowserError.message("Staged remote ZIP did not verify.")}
            guard try checkedHash(path)==expected else {throw ArchiveBrowserError.message("Remote ZIP changed while staging. It was not overwritten.")}
            try transport.rename(path,to:backup);movedOriginal=true
            guard try checkedHash(backup)==expected else {throw ArchiveBrowserError.message("Remote original changed at replacement; preserved backup requires review.")}
            try transport.rename(staged,to:path);installed=true
            guard try checkedHash(path)==replacement else {throw ArchiveBrowserError.message("Installed remote ZIP could not be verified. Keep the local recovery copy and remote backup.")}
            return backup
        } catch {
            // Restore only if the transport preflight finds no destination.
            // FTP RNTO has no conditional-create primitive: an intervening writer
            // can still race that preflight. Retain recovery paths rather than
            // claiming atomic or guaranteed no-clobber behavior.
            if movedOriginal && !installed {try? transport.rename(backup,to:path)}
            if !installed && uploaded {try? transport.remove(staged)}
            throw ArchiveBrowserError.message(error.localizedDescription+(movedOriginal ? "\nRemote recovery original (unless restored): "+backup : "")+(!installed ? "\nRemote staging path (may remain after failure): "+staged : ""))
        }
    }
}

#if !ARCHIVE_WRITEBACK_TESTS
import ObjectiveC
private var archiveOriginKey:UInt8=0
private final class ArchiveOriginBox {let origin:ArchiveWritebackOrigin;init(_ origin:ArchiveWritebackOrigin){self.origin=origin}}
private final class ArchiveOriginRegistry {let origins=NSMapTable<AnyObject,ArchiveOriginBox>(keyOptions:[.weakMemory,.objectPointerPersonality],valueOptions:.strongMemory)}
extension CommanderController {
    private var archiveOriginRegistry:ArchiveOriginRegistry {
        if let registry=objc_getAssociatedObject(self,&archiveOriginKey) as? ArchiveOriginRegistry{return registry}
        let registry=ArchiveOriginRegistry();objc_setAssociatedObject(self,&archiveOriginKey,registry,.OBJC_ASSOCIATION_RETAIN_NONATOMIC);return registry
    }
    func archiveOrigin(_ session:ArchiveBrowserSession)throws->ArchiveWritebackOrigin {
        if let box=archiveOriginRegistry.origins.object(forKey:session){return box.origin}
        if let parent=archiveParents[ObjectIdentifier(session)],parent.localDirectory==nil {throw ArchiveBrowserError.message("Reopen this virtual ZIP to establish its verified writeback origin.")}
        return .local
    }
    func registerArchiveOrigin(_ origin:ArchiveWritebackOrigin,session:ArchiveBrowserSession){archiveOriginRegistry.origins.setObject(ArchiveOriginBox(origin),forKey:session)}
    func applyArchiveWriteback(_ result:ArchiveWritebackResult){
        for change in result.changes {registerArchiveOrigin(change.origin,session:change.new);replaceArchiveSession(change.old,with:change.new)}
    }
}
#endif
