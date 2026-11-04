import AppKit
import Darwin

/// The ZIP snapshot is never edited in place. Saved editor bytes live in a
/// separate private file and survive failed rewrites until explicitly discarded.
final class ArchiveEditSession {
    static let maximumBytes = 4 * 1024 * 1024
    let localURL: URL
    let memberPath: String
    private let directory: URL
    private let lock = NSRecursiveLock()
    private var archive: ArchiveBrowserSession
    private var baseline: Data
    private var closed = false
    private var updating = false
    private let writeback: ((ArchiveBrowserSession,ArchiveBrowserSession)throws->ArchiveBrowserSession)?
    private static func failure(_ text: String) -> ArchiveBrowserError { .message(text) }

    static func prepare(session: ArchiveBrowserSession, path: String, writeback: ((ArchiveBrowserSession,ArchiveBrowserSession)throws->ArchiveBrowserSession)? = nil) throws -> ArchiveEditSession {
        guard session.original.isFileURL else { throw failure("Download remote archives before editing members.") }
        guard let node = session.node(path), !node.isDirectory, node.size <= maximumBytes else { throw failure("Archive text editing requires a regular member up to 4 MiB.") }
        let data = try read(session.readableMember(path))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("archive-edit-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        do {
            let local = root.appendingPathComponent((path as NSString).lastPathComponent)
            try data.write(to:local,options:.withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:local.path)
            return ArchiveEditSession(archive:session,path:path,directory:root,local:local,baseline:data,writeback:writeback)
        } catch { try? FileManager.default.removeItem(at:root);throw error }
    }
    private init(archive: ArchiveBrowserSession,path: String,directory: URL,local: URL,baseline: Data,writeback: ((ArchiveBrowserSession,ArchiveBrowserSession)throws->ArchiveBrowserSession)?) {
        self.archive=archive;self.memberPath=path;self.directory=directory;self.localURL=local;self.baseline=baseline;self.writeback=writeback
    }
    private static func read(_ url: URL) throws -> Data {
        guard url.isFileURL else { throw failure("Archive edit recovery requires a local file.") }
        let fd = open(url.path,O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw failure("Cannot read the private editor file; recovery copy retained.") };defer{close(fd)}
        var before=stat();guard fstat(fd,&before)==0,before.st_mode & S_IFMT == S_IFREG,before.st_size>=0,before.st_size<=maximumBytes else {throw failure("Archive editor file must be a regular file up to 4 MiB.")}
        var data=Data(),buffer=[UInt8](repeating:0,count:65536)
        while true {
            let amount=Darwin.read(fd,&buffer,buffer.count)
            if amount<0 {if errno==EINTR{continue};throw failure("Could not read saved editor bytes.")}
            if amount==0{break};data.append(contentsOf:buffer[0..<amount])
            guard data.count<=maximumBytes else {throw failure("Saved editor file exceeds 4 MiB.")}
        }
        var after=stat(),pathNow=stat()
        guard fstat(fd,&after)==0,lstat(url.path,&pathNow)==0,before.st_dev==after.st_dev,before.st_ino==after.st_ino,before.st_size==after.st_size,
              before.st_mtimespec.tv_sec==after.st_mtimespec.tv_sec,before.st_mtimespec.tv_nsec==after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec==after.st_ctimespec.tv_sec,before.st_ctimespec.tv_nsec==after.st_ctimespec.tv_nsec,
              pathNow.st_dev==before.st_dev,pathNow.st_ino==before.st_ino,data.count==before.st_size else {throw failure("Saved editor file changed while reading. Retry after saving finishes.")}
        return data
    }
    var archiveSession: ArchiveBrowserSession {lock.lock();defer{lock.unlock()};return archive}
    var hasPendingChanges: Bool {lock.lock();defer{lock.unlock()};return !closed && (try? Self.read(localURL)) != baseline}
    var isUpdating: Bool {lock.lock();defer{lock.unlock()};return updating}
    /// Caller obtains update consent first. Work runs off the main thread.
    /// Snapshot the saved bytes so another editor save during packing remains pending.
    @discardableResult func uploadSavedChanges() throws -> ArchiveBrowserSession {
        lock.lock()
        guard !closed,!updating else {lock.unlock();throw Self.failure("Archive editor is closed or already updating.")}
        let edited:Data
        do {edited=try Self.read(localURL)}catch{lock.unlock();throw error}
        let old=archive
        if edited==baseline {lock.unlock();return old}
        updating=true;lock.unlock()
        defer {lock.lock();updating=false;lock.unlock()}
        let saved=directory.appendingPathComponent(".saved-"+UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:saved)}
        try edited.write(to:saved,options:.withoutOverwriting)
        let prepared=try ArchiveMutationService.update(session:old,path:memberPath,from:saved)
        let new=try writeback?(old,prepared) ?? prepared
        lock.lock();archive=new;baseline=edited;lock.unlock()
        return new
    }
    func exportChanges(to destination: URL) throws {
        lock.lock();defer{lock.unlock()}
        guard !closed,destination.isFileURL else {throw Self.failure("Choose a new local file for recovery.")}
        try Self.read(localURL).write(to:destination,options:.withoutOverwriting)
    }
    /// Only call after a successful close check or explicit user discard.
    func discardAndClose() throws {
        lock.lock();defer{lock.unlock()}
        guard !updating else {throw Self.failure("Wait for the archive update before closing.")}
        try FileManager.default.removeItem(at:directory);closed=true
    }
    deinit {if !hasPendingChanges {try? FileManager.default.removeItem(at:directory)}}
}

#if !ARCHIVE_EDIT_BACKEND_TESTS
private final class ArchiveEditorOriginState {
    var origin:ArchiveWritebackOrigin
    var result:ArchiveWritebackResult?
    init(_ origin:ArchiveWritebackOrigin){self.origin=origin}
}
private final class ArchiveEditingCoordinator {
    let session: ArchiveEditSession
    private weak var commander: CommanderController?
    private var packing=false
    private let originState:ArchiveEditorOriginState
    init(session: ArchiveEditSession,commander: CommanderController?,originState:ArchiveEditorOriginState) {self.session=session;self.commander=commander;self.originState=originState}
    func saved() {
        guard !packing,session.hasPendingChanges else{return}
        let alert=NSAlert();alert.messageText="Update the edited member in the ZIP?"
        alert.informativeText="The ZIP and enclosing archives will be rebuilt and checked. FTP replacements use verified staging with a retained remote original, but cannot lock out other writers. Changed originals are rejected; your edited copy remains available on failure."
        alert.addButton(withTitle:"Update ZIP");alert.addButton(withTitle:"Keep Local")
        guard alert.runModal() == .alertFirstButtonReturn else{return}
        packing=true;let old=session.archiveSession
        DispatchQueue.global(qos:.userInitiated).async { [self] in
            let result=Result {try session.uploadSavedChanges()}
            DispatchQueue.main.async { [self] in
                packing=false
                switch result {
                case .success(let new):
                    if let result=originState.result {commander?.applyArchiveWriteback(result)} else {commander?.replaceArchiveSession(old,with:new)}
                    let alert=NSAlert();alert.messageText="Archive member updated."
                    alert.informativeText=session.hasPendingChanges ? "Newer saved edits remain to be packed." : session.memberPath
                    alert.runModal()
                case .failure(let error):
                    let alert=NSAlert(error:error);alert.informativeText += "\nLocal recovery copy: "+session.localURL.path;alert.runModal()
                }
            }
        }
    }
    func shouldClose() -> Bool {
        if packing || session.isUpdating {let alert=NSAlert();alert.messageText="Wait for the ZIP update to finish before closing.";alert.runModal();return false}
        guard session.hasPendingChanges else{return true}
        let alert=NSAlert();alert.messageText="Saved changes have not been packed into the ZIP."
        alert.informativeText="Keep editing, export a local copy, or explicitly discard the pending saved changes."
        alert.addButton(withTitle:"Keep Editing");alert.addButton(withTitle:"Export Local Copy");alert.addButton(withTitle:"Discard")
        switch alert.runModal() {
        case .alertSecondButtonReturn:
            let panel=NSSavePanel();panel.nameFieldStringValue=session.localURL.lastPathComponent
            guard panel.runModal() == .OK,let url=panel.url else{return false}
            do {try session.exportChanges(to:url);return true}catch{NSAlert(error:error).runModal();return false}
        case .alertThirdButtonReturn:return true
        default:return false
        }
    }
    func closed() {do{try session.discardAndClose()}catch{NSAlert(error:error).runModal()}}
}

extension CommanderController {
    func openArchiveEditor(entry: FileEntry) {
        guard !busy,!entry.isDirectory,!entry.isSymbolicLink,case .archive(let archive,_)=activePane.location else{NSSound.beep();return}
        let location=activePane.location
        guard canMutateArchive(archive) else { return }
        do {
            let path=try location.selectedPath(entry),state=ArchiveEditorOriginState(try archiveOrigin(archive))
            runOperation("Prepare archive text for editing",success:"Archive editor opened") { [weak self] in
                let session=try ArchiveEditSession.prepare(session:archive,path:path,writeback:{ old,new in
                    let result=try ArchiveWritebackService.commit(old:old,new:new,origin:state.origin)
                    state.origin=result.origin;state.result=result;return result.session
                })
                DispatchQueue.main.async { [weak self] in
                    let coordinator=ArchiveEditingCoordinator(session:session,commander:self,originState:state)
                    do {try EditorController.open(url:session.localURL,editable:true,onSaved:{_ in coordinator.saved()},shouldClose:{coordinator.shouldClose()},onClosed:{coordinator.closed()})}
                    catch {try? session.discardAndClose();self?.showError(error)}
                }
            }
        } catch {showError(error)}
    }
}
#endif
