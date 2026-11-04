import AppKit
import Darwin

struct ArchiveBrowserNode {
    let path: String
    let isDirectory: Bool
    let size: UInt64
    var name: String { (path as NSString).lastPathComponent }
}
enum ArchiveBrowserError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}

/// Read-only immutable ZIP session; target files change only in extract().
final class ArchiveBrowserSession {
    let original: URL
    var displayOrigin: String?
    let snapshot: URL
    let tool: URL
    let items: [ArchiveItem]
    let isWritableZIP: Bool
    private let password: String?
    private let temporary: URL
    private let nodes: [String: ArchiveBrowserNode]
    private var extracted: URL?
    private let materializationLock = NSRecursiveLock()
    private let fm = FileManager.default
    init(archive: URL, tool: URL, originalLocation: URL? = nil, password: String? = nil) throws {
        self.original = originalLocation ?? archive; self.tool = tool; self.password = password
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: tool.path) else { throw ArchiveBrowserError.message("Bundled archive tool is missing.") }
        let root = fm.temporaryDirectory.appendingPathComponent("native-archive-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions:0o700])
        self.temporary = root; self.snapshot = root.appendingPathComponent(archive.lastPathComponent)
        do {
            try Self.copySnapshot(archive, to: snapshot)
            self.items = try NativeOperations.listArchive(archive: snapshot, tool: tool, password: password)
            let header = try FileHandle(forReadingFrom: snapshot); defer { try? header.close() }
            let magic = try header.read(upToCount: 4) ?? Data()
            self.isWritableZIP = password == nil && (magic == Data([0x50,0x4b,0x03,0x04]) || magic == Data([0x50,0x4b,0x05,0x06]))
            var entries: [String: ArchiveBrowserNode] = [:], normalized: [String:String] = [:]
            for item in items {
                let parts = item.path.split(separator:"/").map(String.init)
                for index in parts.indices {
                    let path = parts[0...index].joined(separator:"/")
                    let directory = index < parts.count-1 || item.isDirectory
                    let key = path.precomposedStringWithCanonicalMapping.lowercased()
                    if let previous=normalized[key], previous != path { throw ArchiveBrowserError.message("Ambiguous Archive directory names: \(previous) / \(path)") }
                    normalized[key]=path
                    if let previous=entries[path], previous.isDirectory != directory { throw ArchiveBrowserError.message("Archive file/directory collision: \(path)") }
                    if entries[path] == nil { entries[path]=ArchiveBrowserNode(path:path,isDirectory:directory,size:directory ? 0 : item.size) }
                    guard entries.count <= 100_000 else { throw ArchiveBrowserError.message("Archive directory tree exceeds the supported limit.") }
                }
            }
            nodes=entries
        } catch { try? fm.removeItem(at:root); throw error }
    }
    deinit { try? fm.removeItem(at:temporary) }
    private static func copySnapshot(_ source: URL, to destination: URL) throws {
        let input = open(source.path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK)
        guard input >= 0 else { throw ArchiveBrowserError.message("Cannot open archive: \(source.path)") }; defer { close(input) }
        var before=stat(); guard fstat(input,&before)==0, before.st_mode & S_IFMT == S_IFREG, before.st_size>=0, before.st_size<=536_870_912 else { throw ArchiveBrowserError.message("Choose a regular archive file up to 512 MiB.") }
        let output=open(destination.path,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0o600)
        guard output>=0 else { throw ArchiveBrowserError.message("Cannot create private archive snapshot.") };defer{close(output)}
        var bytes=[UInt8](repeating:0,count:262144), total=0
        while true {
            let count=read(input,&bytes,bytes.count)
            if count<0 { if errno==EINTR { continue };throw ArchiveBrowserError.message("Archive snapshot read failed.") }
            if count==0 {break};total += count
            guard total<=536_870_912 else { throw ArchiveBrowserError.message("Archive grew beyond the snapshot limit.") }
            var written=0
            while written<count {
                let amount=bytes.withUnsafeBytes { write(output,$0.baseAddress!.advanced(by:written),count-written) }
                if amount<0 && errno==EINTR {continue}
                guard amount>0 else {throw ArchiveBrowserError.message("Archive snapshot write failed.")};written += amount
            }
        }
        var after=stat(), pathNow=stat()
        guard fstat(input,&after)==0,lstat(source.path,&pathNow)==0,
              before.st_dev==after.st_dev,before.st_ino==after.st_ino,before.st_size==after.st_size,
              before.st_mtimespec.tv_sec==after.st_mtimespec.tv_sec,before.st_mtimespec.tv_nsec==after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec==after.st_ctimespec.tv_sec,before.st_ctimespec.tv_nsec==after.st_ctimespec.tv_nsec,
              pathNow.st_dev==before.st_dev,pathNow.st_ino==before.st_ino,total==before.st_size,fsync(output)==0 else {throw ArchiveBrowserError.message("Archive changed while it was opened; reopen it.")}
    }
    func children(in path: String) throws -> [ArchiveBrowserNode] {
        if !path.isEmpty {guard nodes[path]?.isDirectory == true else {throw ArchiveBrowserError.message("Not an archive directory: \(path)")}}
        return nodes.values.filter { ($0.path as NSString).deletingLastPathComponent == path }.sorted {
            if $0.isDirectory != $1.isDirectory{return $0.isDirectory};return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    func node(_ path: String) -> ArchiveBrowserNode? {nodes[path]}
    func selectedRoots(_ paths: [String]) throws -> [String] {
        guard !paths.isEmpty else {throw ArchiveBrowserError.message("Select an archive member.")}
        let selected=Set(paths)
        guard selected.allSatisfy({nodes[$0] != nil}) else {throw ArchiveBrowserError.message("Unknown archive member.")}
        return selected.filter { path in !selected.contains(where: {path.hasPrefix($0+"/")}) }.sorted()
    }
    private func materialize() throws -> URL {
        materializationLock.lock(); defer { materializationLock.unlock() }
        if let extracted{return extracted}
        let output=temporary.appendingPathComponent("contents")
        try fm.createDirectory(at:output,withIntermediateDirectories:false)
        do {try NativeOperations.unpack(archive:snapshot,destination:output,tool:tool,password:password);extracted=output;return output}
        catch {try? fm.removeItem(at:output);throw error}
    }
    func readableMember(_ path: String) throws -> URL {
        guard let node=nodes[path],!node.isDirectory else {throw ArchiveBrowserError.message("Choose a file to view.")}
        let root=try materialize(), url=root.appendingPathComponent(path)
        let values=try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])
        guard values.isRegularFile==true,values.isSymbolicLink != true else {throw ArchiveBrowserError.message("Extracted member is not a regular file.")}
        return url
    }
    /// Copies selected members preserving their full internal paths; never overwrites.
    /// A private staging subtree is transferred to the target only after full validation.
    func extract(paths: [String], to destination: URL) throws -> Int {
        let selected=try selectedRoots(paths)
        let targetValues=try destination.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
        guard targetValues.isDirectory==true,targetValues.isSymbolicLink != true else {throw ArchiveBrowserError.message("Choose an ordinary destination directory.")}
        let source=try materialize()
        let stage=temporary.appendingPathComponent("selection-"+UUID().uuidString)
        try fm.createDirectory(at:stage,withIntermediateDirectories:false);defer{try? fm.removeItem(at:stage)}
        for path in selected {
            let target=stage.appendingPathComponent(path)
            try fm.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
            try fm.copyItem(at:source.appendingPathComponent(path),to:target)
        }
        let roots=try fm.contentsOfDirectory(at:stage,includingPropertiesForKeys:nil)
        try FileService.transfer(roots,to:destination,move:false)
        return selected.count
    }
    func testIntegrity(cancelled: () -> Bool = {false}) throws {
        guard !cancelled() else { throw ArchiveBrowserError.message("Archive integrity test cancelled.") }
        _ = try NativeOperations.listArchive(archive: snapshot, tool: tool, password: password, cancelled: cancelled)
        guard !cancelled() else { throw ArchiveBrowserError.message("Archive integrity test cancelled.") }
    }

}

private final class ArchiveBrowserTable: NSTableView {
    var handle: ((NSEvent)->Bool)?
    override func keyDown(with event:NSEvent){if handle?(event)==true{return};super.keyDown(with:event)}
}
private final class ArchiveCancellation: @unchecked Sendable {
    private let lock=NSLock();private var value=false
    func cancel(){lock.lock();value=true;lock.unlock()}
    var cancelled:Bool{lock.lock();defer{lock.unlock()};return value}
}

final class ArchiveBrowserController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private static var retained:[ArchiveBrowserController]=[]
    static var hasActiveTransfers:Bool{retained.contains{$0.extracting}}
    private var session:ArchiveBrowserSession?
    private var directory=""
    private var members:[ArchiveBrowserNode]=[]
    private let table=ArchiveBrowserTable()
    private let pathField=NSTextField(labelWithString:"/")
    private let status=NSTextField(wrappingLabelWithString:"")
    private let destination:URL
    private let completion:()->Void
    private var working=false,extracting=false
    private var cancellation:ArchiveCancellation?
    private var buttons:[NSButton]=[]
    static func show(archive:URL,tool:URL,destination:URL,onComplete:@escaping ()->Void={}) throws {
        guard FileManager.default.isExecutableFile(atPath:tool.path) else {throw ArchiveBrowserError.message("Bundled archive tool is missing.")}
        let controller=ArchiveBrowserController(archive:archive,destination:destination,completion:onComplete)
        retained.append(controller);controller.window?.center();controller.showWindow(nil)
        controller.load(archive:archive,tool:tool)
    }
    private init(archive:URL,destination:URL,completion:@escaping ()->Void) {
        self.destination=destination;self.completion=completion
        let w=NSWindow(contentRect:NSRect(x:0,y:0,width:840,height:540),styleMask:[.titled,.closable,.resizable,.miniaturizable],backing:.buffered,defer:false)
        w.title="Archive — "+archive.lastPathComponent;w.isReleasedWhenClosed=false;w.appearance=nil
        super.init(window:w);w.delegate=self
        let bar=NSStackView();bar.orientation = .horizontal;bar.spacing=10
        for (title,selector) in [("Parent",#selector(parent)),("View F3",#selector(viewMember)),("Extract selected…",#selector(extractSelected)),("Extract all…",#selector(extractAll)),("Test archive",#selector(testArchive))] {
            let b=NSButton(title:title,target:self,action:selector);buttons.append(b);bar.addArrangedSubview(b)
        }
        table.dataSource=self;table.delegate=self;table.target=self;table.doubleAction=#selector(openMember);table.allowsMultipleSelection=true;table.rowHeight=24;table.usesAlternatingRowBackgroundColors=true
        for (id,title,width) in [("name","Name",560.0),("size","Size",180.0)] {let c=NSTableColumn(identifier:.init(id));c.title=title;c.width=width;table.addTableColumn(c)}
        table.handle = { [weak self] event in
            guard let self else{return false}
            if event.keyCode==99 {self.viewMember();return true}
            if event.keyCode==36 || event.keyCode==76 {self.openMember();return true}
            if event.keyCode==51 {self.parent();return true}
            return false
        }
        let scroll=NSScrollView();scroll.documentView=table;scroll.hasVerticalScroller=true
        let note=NSTextField(wrappingLabelWithString:"Archive browsing. Double-click folders to navigate, files to view. Extraction preserves internal paths and refuses existing destination roots. Use the main panes to edit unencrypted ZIP members.")
        let stack=NSStackView(views:[bar,pathField,note,scroll,status]);stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=10
        w.contentView!.addSubview(stack);stack.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:w.contentView!.leadingAnchor,constant:14),stack.trailingAnchor.constraint(equalTo:w.contentView!.trailingAnchor,constant:-14),stack.topAnchor.constraint(equalTo:w.contentView!.topAnchor,constant:14),stack.bottomAnchor.constraint(equalTo:w.contentView!.bottomAnchor,constant:-14)])
        for view in [pathField,note,scroll,status]{view.translatesAutoresizingMaskIntoConstraints=false;view.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true}
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:250).isActive=true
    }
    required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
    func windowShouldClose(_ sender:NSWindow)->Bool {if extracting{status.stringValue="Extraction is in progress. Wait before closing.";return false};cancellation?.cancel();return true}
    func windowWillClose(_ notification:Notification){cancellation?.cancel();Self.retained.removeAll{$0===self}}
    private func setWorking(_ value:Bool){working=value;buttons.forEach{$0.isEnabled = !value};if !value{window?.makeFirstResponder(table)}}
    private func load(archive:URL,tool:URL){
        setWorking(true);status.stringValue="Opening a private read-only snapshot…"
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            let result=Result{try ArchiveBrowserSession(archive:archive,tool:tool)}
            DispatchQueue.main.async{guard let self else{return};self.setWorking(false);switch result{case .success(let session):self.session=session;self.navigate("");case .failure(let error):self.status.stringValue=error.localizedDescription;self.buttons.forEach{$0.isEnabled=false}}}
        }
    }
    private func navigate(_ path:String){guard !working,let session else{return};do{members=try session.children(in:path);directory=path;pathField.stringValue=path.isEmpty ? "/" : "/"+path;table.reloadData();if !members.isEmpty{table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)};status.stringValue="\(members.count) member(s). Archive remains unchanged."}catch{status.stringValue=error.localizedDescription}}
    func numberOfRows(in tableView:NSTableView)->Int{members.count}
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView?{
        guard members.indices.contains(row) else{return nil};let item=members[row]
        let label=NSTextField(labelWithString:tableColumn?.identifier.rawValue=="size" ? (item.isDirectory ? "<DIR>" : String(item.size)) : (item.isDirectory ? "["+item.name+"]" : item.name));label.lineBreakMode = .byTruncatingMiddle;label.toolTip=item.path;return label
    }
    @objc private func parent(){guard !working else{return};navigate((directory as NSString).deletingLastPathComponent)}
    @objc private func openMember(){guard !working else{return};let row=table.selectedRow;guard members.indices.contains(row) else{return};if members[row].isDirectory{navigate(members[row].path)}else{view(path:members[row].path)}}
    @objc private func viewMember(){guard !working,members.indices.contains(table.selectedRow),!members[table.selectedRow].isDirectory else{return};view(path:members[table.selectedRow].path)}
    private func view(path:String){
        guard let session else{return};setWorking(true);status.stringValue="Validating and preparing read-only member…"
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            let result=Result{try session.readableMember(path)}
            DispatchQueue.main.async{guard let self else{return};self.setWorking(false);do{try ListerController.open(url:result.get());self.status.stringValue="Opened read-only member; archive unchanged."}catch{self.status.stringValue=error.localizedDescription}}
        }
    }
    @objc private func extractSelected(){let paths=table.selectedRowIndexes.compactMap{members.indices.contains($0) ? members[$0].path : nil};requestExtraction(paths)}
    @objc private func extractAll(){guard let session else{return};do{requestExtraction(try session.children(in:"").map(\.path))}catch{status.stringValue=error.localizedDescription}}
    private func requestExtraction(_ paths:[String]){
        guard !working,!paths.isEmpty,let session,let window else{return}
        let alert=NSAlert();alert.messageText="Extract \(paths.count) selected item(s)?";alert.informativeText="Destination directory. Internal paths are preserved; existing destination roots will not be replaced."
        let field=NSTextField(string:destination.path);field.frame=NSRect(x:0,y:0,width:550,height:25);alert.accessoryView=field;alert.addButton(withTitle:"Extract");alert.addButton(withTitle:"Cancel")
        alert.beginSheetModal(for:window){[weak self] response in
            guard let self,response == .alertFirstButtonReturn else{return}
            let expanded=(field.stringValue as NSString).expandingTildeInPath
            guard expanded.hasPrefix("/") else{self.status.stringValue="Use an absolute destination directory.";return}
            let target=URL(fileURLWithPath:expanded);self.setWorking(true);self.extracting=true;self.status.stringValue="Extracting selected members…"
            DispatchQueue.global(qos:.userInitiated).async{[weak self] in
                let result=Result{try session.extract(paths:paths,to:target)}
                DispatchQueue.main.async{guard let self else{return};self.extracting=false;self.setWorking(false);switch result{case .success(let count):self.status.stringValue="Extracted \(count) selection(s) to \(target.path).";case .failure(let error):self.status.stringValue=error.localizedDescription};self.completion()}
            }
        }
    }
    @objc private func testArchive(){
        guard !working,let session else{return};let token=ArchiveCancellation();cancellation=token;setWorking(true);status.stringValue="Testing archive integrity… Close this window to cancel the test."
        DispatchQueue.global(qos:.userInitiated).async{[weak self] in
            let result=Result{try session.testIntegrity(cancelled:{token.cancelled})}
            DispatchQueue.main.async{guard let self else{return};self.cancellation=nil;self.setWorking(false);switch result{case .success:self.status.stringValue="Archive integrity test passed. No destination files changed.";case .failure(let error):self.status.stringValue=error.localizedDescription}}
        }
    }
}
