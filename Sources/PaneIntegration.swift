import AppKit

extension PaneLocation {
    var shortName:String {
        switch self {
        case .local(let url):return url.lastPathComponent.isEmpty ? "/" : url.lastPathComponent
        case .archive(let session,let path):return path.isEmpty ? session.original.lastPathComponent : (path as NSString).lastPathComponent
        case .ftp(let client,let path):return path == "/" ? client.profile.host : (path as NSString).lastPathComponent
        }
    }
    func resolvePath(_ input:String)throws->PaneLocation {
        let value=(input as NSString).expandingTildeInPath
        switch self {
        case .local(let root):return .local(value.hasPrefix("/") ? URL(fileURLWithPath:value) : root.appendingPathComponent(value))
        case .archive(let session,let current):
            let prefix=(session.displayOrigin ?? session.original.path) + "!/"
            if value.hasPrefix(prefix) {return .archive(session,path:String(value.dropFirst(prefix.count)))}
            if value.hasPrefix("/") {return .local(URL(fileURLWithPath:value))}
            var components=current.split(separator:"/").map(String.init)
            for part in value.split(separator:"/") {if part == ".." {if !components.isEmpty {components.removeLast()}} else if part != "." {components.append(String(part))}}
            return .archive(session,path:components.joined(separator:"/"))
        case .ftp(let client,let current):
            if let url=URL(string:value),url.scheme == "ftp" || url.scheme == "ftps" {
                guard url.host == client.profile.host, url.user == nil || url.user == client.profile.username, url.password == nil, url.port == nil || url.port == client.profile.port, url.scheme == (client.profile.security == .plainFTP ? "ftp" : "ftps"), url.query == nil,url.fragment == nil else {throw FTPError.message("Use FTP Connect to change servers.")}
                return .ftp(client,path:try FTPClient.normalizedPath(url.path))
            }
            return .ftp(client,path:try FTPClient.normalizedPath(value.hasPrefix("/") ? value : current + "/" + value))
        }
    }
}

extension CommanderController {
    @discardableResult func navigate(_ next:PaneLocation,pane:Pane?=nil,recordHistory:Bool=true,focus:Bool=true,storeTab:Bool=true,viewModeTabSwitch:Bool=false,completion:((Bool)->Void)?=nil)->Bool {
        guard !busy else {completion?(false);return false}
        let target=pane ?? activePane
        if storeTab,target.lockedTabRoots[target.selectedTab] != nil,next != target.location {
            return openLocationInNewTab(next,pane:target,background:false,completion:completion)
        }
        target.loadTask?.cancel();target.loadGeneration += 1
        let generation=target.loadGeneration,previous=target.location,showHidden=self.showHidden
        func commit(_ rows:[FileEntry]) {
            if recordHistory && previous != next {target.backHistory.append(previous);target.backHistory=Array(target.backHistory.suffix(runtimeConfig.historyLimit));target.forwardHistory.removeAll()}
            target.applyListing(rows,location:next);if storeTab {target.storeTab()}
            applyAutomaticViewMode(to:target,directoryChanged:previous != next,tabSwitch:viewModeTabSwitch)
            if remember,runtimeConfig.saveOnExit,let local=next.localDirectory {UserDefaults.standard.set(local.path,forKey:target === left ? "leftPath" : "rightPath")}
            if target === activePane {quickSearchText=""}
            status.stringValue=next.displayPath
            if focus {window.makeFirstResponder(target.fileResponder)}
            updateQuickView();separateTrees.refreshRoots();completion?(true)
        }
        if next.localDirectory != nil {
            target.isLoading=false;target.loadTask=nil
            do {try commit(next.list(showHidden:showHidden));return true}
            catch {target.path.stringValue=previous.displayPath;showError(error);completion?(false);return false}
        }
        target.isLoading=true;let task=FTPTask();target.loadTask=task;status.stringValue="Loading " + next.displayPath
        DispatchQueue.global(qos:.userInitiated).async { [weak self,weak target] in
            let result=Result {try next.list(showHidden:showHidden,task:task)}
            DispatchQueue.main.async {
                guard let self,let target,target.loadGeneration == generation else {return}
                target.isLoading=false;target.loadTask=nil
                switch result {
                case .success(let rows):commit(rows)
                case .failure(let error):target.path.stringValue=target.location.displayPath;self.showError(error);completion?(false)
                }
            }
        }
        return true
    }
    func reloadPane(_ pane:Pane) { _=navigate(pane.location,pane:pane,recordHistory:false,focus:false) }
    func selectTab(_ index:Int,pane:Pane?=nil) {
        let p=pane ?? activePane
        guard !busy,p.tabs.indices.contains(index) else {return}
        let next=p.tabs[index]
        navigate(next,pane:p,recordHistory:false,storeTab:false,viewModeTabSwitch:true) { success in
            if success,p.tabs.indices.contains(index) {p.selectedTab=index;p.tabs[index]=p.location}
            p.updateTabs()
        }
    }
    @discardableResult func openLocationInNewTab(_ location:PaneLocation,pane:Pane?=nil,background:Bool=false,completion:((Bool)->Void)?=nil)->Bool {
        let p=pane ?? activePane;guard !busy else {completion?(false);return false}
        let index=runtimeConfig.newTabBesideCurrent ? p.selectedTab+1 : p.tabs.count
        if background {p.insertTab(location,at:index);p.updateTabs();completion?(true);return true}
        return navigate(location,pane:p,recordHistory:false,storeTab:false) {success in
            if success {p.insertTab(location,at:index);p.selectedTab=index;p.updateTabs()}
            completion?(success)
        }
    }
    func swapPaneTabs() {
        guard !busy,!left.isLoading,!right.isLoading else {return}
        let leftLocation=left.location,rightLocation=right.location,hidden=showHidden
        busy=true;status.stringValue="Exchanging tabs…"
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            let result=Result { (try leftLocation.list(showHidden:hidden),try rightLocation.list(showHidden:hidden)) }
            DispatchQueue.main.async {
                guard let self else{return};self.busy=false
                switch result {
                case .success(let rows):
                    let tabs=self.left.tabs,index=self.left.selectedTab,back=self.left.backHistory,forward=self.left.forwardHistory,locks=self.left.lockedTabRoots
                    self.left.lockedTabRoots=self.right.lockedTabRoots;self.right.lockedTabRoots=locks
                    self.left.tabs=self.right.tabs;self.left.selectedTab=self.right.selectedTab;self.left.backHistory=self.right.backHistory;self.left.forwardHistory=self.right.forwardHistory
                    self.right.tabs=tabs;self.right.selectedTab=index;self.right.backHistory=back;self.right.forwardHistory=forward
                    self.left.applyListing(rows.1,location:rightLocation);self.right.applyListing(rows.0,location:leftLocation);self.left.updateTabs();self.right.updateTabs();self.applyAutomaticViewMode(to:self.left);self.applyAutomaticViewMode(to:self.right);self.updateQuickView()
                case .failure(let error):self.showError(error)
                }
                self.drainArchiveUpdates()
            }
        }
    }
    func openArchiveInPane(_ entry:FileEntry,source explicitSource:PaneLocation?=nil,target:Pane?=nil,newTab:Bool=false,focus:Bool=true,password:String?=nil) {
        let pane=target ?? activePane,source=explicitSource ?? activePane.location
        let newTab = newTab || pane.lockedTabRoots[pane.selectedTab] != nil
        guard let tool=Bundle.main.url(forResource:"7zz",withExtension:nil) else {showMessage("Archive tool missing","Reinstall the app.");return}
        let parentOrigin:ArchiveWritebackOrigin
        do {if case .archive(let parent,_)=source {parentOrigin=try archiveOrigin(parent)} else {parentOrigin = .local}}
        catch {showError(error);return}
        pane.loadTask?.cancel();pane.loadGeneration += 1;let generation=pane.loadGeneration
        pane.isLoading=true;let task=FTPTask();pane.loadTask=task;status.stringValue="Opening " + entry.name
        DispatchQueue.global(qos:.userInitiated).async { [weak self,weak pane] in
            let result=Result { ()throws->(ArchiveBrowserSession,PaneReadableMaterialization,ArchiveWritebackOrigin) in
                let lease=try source.readableMaterialization(entry,task:task)
                let opened=try ArchiveBrowserSession(archive:lease.url,tool:tool,password:password)
                if source.localDirectory != nil {return(opened,lease,.local)}
                let workspace=try ArchiveWritebackWorkspace(copying:opened)
                let session=try ArchiveBrowserSession(archive:workspace.url,tool:tool,password:password)
                let path=try source.selectedPath(entry),origin:ArchiveWritebackOrigin
                switch source {
                case .archive(let parent,_):origin = .nested(parent:parent,path:path,origin:parentOrigin,workspace:workspace)
                case .ftp(let client,_):origin = .remote(transport:FTPArchiveTransport(client:client),path:path,workspace:workspace)
                case .local:origin = .local
                }
                return(session,lease,origin)
            }
            DispatchQueue.main.async {
                guard let self,let pane,pane.loadGeneration == generation else{return}
                pane.isLoading=false;pane.loadTask=nil
                switch result {
                case .success(let result):
                    let session=result.0;session.displayOrigin=source.displayPath+(source.displayPath.hasSuffix("/") ? "" : "/")+entry.name;self.archiveParents[ObjectIdentifier(session)]=source;self.archiveLeases[ObjectIdentifier(session)]=result.1
                    self.registerArchiveOrigin(result.2,session:session)
                    if newTab {pane.tabs.append(.archive(session,path:""));pane.selectedTab=pane.tabs.count-1;pane.updateTabs()}
                    self.navigate(.archive(session,path:""),pane:pane,recordHistory:!newTab,focus:focus)
                case .failure(let error):
                    if error is ArchivePasswordRequired {
                        self.requestArchivePassword(name:entry.name,retry:password != nil) { [weak self,weak pane] value in
                            guard let self,let pane,pane.loadGeneration==generation else{return}
                            self.openArchiveInPane(entry,source:source,target:pane,newTab:newTab,focus:focus,password:value)
                        }
                    } else {self.showError(error)}
                }
            }
        }
    }
    func requestArchivePassword(name:String,retry:Bool,completion:@escaping(String)->Void) {
        let alert=NSAlert();alert.messageText=retry ? "Incorrect password" : "Archive password"
        alert.informativeText=name;alert.addButton(withTitle:"Open");alert.addButton(withTitle:"Cancel")
        let field=NSSecureTextField(frame:NSRect(x:0,y:0,width:320,height:24));field.placeholderString="Password";alert.accessoryView=field
        alert.beginSheetModal(for:window) {result in if result == .alertFirstButtonReturn {completion(field.stringValue)};field.stringValue=""}
        alert.window.makeFirstResponder(field)
    }
    func transferBetweenProviders(move:Bool) {
        let source=activePane.location,target=otherPane.location,entries=activePane.selectedEntries
        guard !entries.isEmpty,!busy else{return}
        if case .archive(let archive,_)=target,!canMutateArchive(archive) {return}
        if move,case .archive(let archive,_)=source,!canMutateArchive(archive) {return}
        let alert=NSAlert();alert.messageText="\(move ? "Move" : "Copy") \(entries.count) item(s)?"
        alert.informativeText="\(source.displayPath)\n→ \(target.displayPath)\nExisting destination names will not be overwritten." + (move ? "\nSources are removed only after destination contents verify. Remote deletion is permanent; FTP cannot lock other writers out during verification and deletion." : "")
        alert.addButton(withTitle:move ? "Move" : "Copy");alert.addButton(withTitle:"Cancel")
        alert.beginSheetModal(for:window) { [weak self] response in
            guard response == .alertFirstButtonReturn,let self else{return}
            self.runProviderTransfer(entries:entries,source:source,target:target,move:move)
        }
    }
    func runProviderTransfer(entries:[FileEntry],source:PaneLocation,target:PaneLocation,move:Bool) {
        guard !busy else{return}
        if case .archive(let archive,_)=target,!canMutateArchive(archive){return}
        if move,case .archive(let archive,_)=source,!canMutateArchive(archive){return}
        var origins:[ObjectIdentifier:ArchiveWritebackOrigin]=[:]
        do {for location in [source,target] {if case .archive(let session,_)=location {origins[ObjectIdentifier(session)]=try archiveOrigin(session)}}}
        catch {showError(error);return}
        busy=true
        let task=FTPTask(),progress=NSAlert();progress.messageText=move ? "Moving files" : "Copying files";progress.informativeText="Preparing…";progress.addButton(withTitle:"Cancel transfer")
        let spinner=NSProgressIndicator(frame:NSRect(x:0,y:0,width:420,height:16));spinner.style = .bar;spinner.isIndeterminate=true;spinner.startAnimation(nil);progress.accessoryView=spinner
        progress.beginSheetModal(for:window) {response in if response == .alertFirstButtonReturn {task.cancel()} }
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            var writebacks:[ArchiveWritebackResult]=[]
            let result=Result {try ProviderTransferService.transfer(entries:entries,source:source,target:target,move:move,task:task,progress:{text in DispatchQueue.main.async {progress.informativeText=text}},archiveCommit:{ old,new in
                let report=try ArchiveWritebackService.commit(old:old,new:new,origin:origins[ObjectIdentifier(old)] ?? .local)
                for change in report.changes {origins[ObjectIdentifier(change.new)]=change.origin}
                writebacks.append(report);return report.session
            })}
            DispatchQueue.main.async {
                guard let self else{return};self.busy=false
                if progress.window.sheetParent != nil {self.window.endSheet(progress.window,returnCode:.stop)}
                let updates:[ProviderArchiveSessionUpdate]
                switch result {
                case .success(let report):updates=report.updatedArchiveSessions
                case .failure(let error):updates=(error as? ProviderTransferFailure)?.result.updatedArchiveSessions ?? []
                }
                for report in writebacks {self.applyArchiveWriteback(report)}
                for update in updates {self.replaceArchiveSession(update.previous,with:update.replacement)}
                self.drainArchiveUpdates();self.refresh()
                switch result {
                case .success(let report):self.status.stringValue="Copied \(report.copiedCount), moved \(report.movedCount) item(s)."
                case .failure(let error):self.showError(error)
                }
            }
        }
    }
    func renameProviderEntry() {
        let location=activePane.location;guard let entry=activePane.currentEntry else{return}
        if case .archive(let session,_)=location {
            prompt(title:"Rename archive member",detail:location.displayPath,value:entry.name,action:"Rename") { [weak self] name in
                self?.runArchiveMutation("Renaming archive member",session:session) {try ArchiveMutationService.rename(session:session,path:location.selectedPath(entry),toName:name)}
            };return
        }
        prompt(title:"Rename",detail:location.displayPath,value:entry.name,action:"Rename") { [weak self] name in
            self?.runOperation("Renaming",success:"Renamed") {try location.rename(entry,toName:name)}
        }
    }
    func makeProviderFolder() {
        let location=activePane.location
        if case .archive(let session,let path)=location {
            prompt(title:"New archive folder",detail:location.displayPath,value:"New folder",action:"Create") { [weak self] name in
                guard ShortcutContract.validCopyName(name) else {self?.showMessage("Invalid name",name);return}
                self?.runArchiveMutation("Creating archive folder",session:session) {try ArchiveMutationService.makeDirectory(session:session,path:path.isEmpty ? name : path+"/"+name)}
            };return
        }
        prompt(title:"New folder",detail:location.displayPath,value:"New folder",action:"Create") { [weak self] name in
            self?.runOperation("Creating folder",success:"Folder created") {try location.makeDirectory(name:name)}
        }
    }
    func deleteProviderEntries() {
        let location=activePane.location,entries=activePane.selectedEntries
        guard !entries.isEmpty else{return}
        if case .archive(let session,_)=location {
            let alert=NSAlert();alert.messageText="Delete \(entries.count) archive member(s)?";alert.informativeText="The archive will be rebuilt and verified before replacement. Members do not go to Trash.";alert.addButton(withTitle:"Delete members");alert.addButton(withTitle:"Cancel")
            alert.beginSheetModal(for:window) { [weak self] result in if result == .alertFirstButtonReturn {self?.runArchiveMutation("Deleting archive members",session:session) {try ArchiveMutationService.delete(session:session,paths:entries.map{try location.selectedPath($0)})}} };return
        }
        guard case .ftp(let client,let path)=location else {return}
        let alert=NSAlert();alert.messageText="Permanently delete \(entries.count) remote item(s)?";alert.informativeText="\(location.displayPath)\nRemote files do not go to the Mac Trash.\n"+entries.map(\.name).joined(separator:"\n")
        alert.addButton(withTitle:"Delete permanently");alert.addButton(withTitle:"Cancel");alert.alertStyle = .warning
        alert.beginSheetModal(for:window) { [weak self] result in
            if result == .alertFirstButtonReturn {self?.runOperation("Deleting remote items",success:"Deleted remote items") {for entry in entries {try client.delete(remotePath:FTPClient.childPath(path,name:entry.name),recursive:entry.isDirectory)}}}
        }
    }
    @discardableResult func requireLocalPane(_ pane:Pane?=nil)->Bool {
        guard !separateTrees.hasFocus,!(pane ?? activePane).isTreeMode else {NSSound.beep();return false}
        guard (pane ?? activePane).location.localDirectory != nil else {showMessage("Local folder required","This action is currently available in local folders.");return false};return true
    }
}

extension CommanderController {
    func drainArchiveUpdates() {
        guard !busy else{return};let pending=deferredArchiveUpdates;deferredArchiveUpdates.removeAll()
        for (old,new) in pending {replaceArchiveSession(old,with:new)}
    }
    func replaceArchiveSession(_ old:ArchiveBrowserSession,with new:ArchiveBrowserSession) {
        if busy {deferredArchiveUpdates.append((old,new));return}
        func mapped(_ location:PaneLocation)->PaneLocation {
            if case .archive(let session,let path)=location,session.original.standardizedFileURL == old.original.standardizedFileURL {
                return .archive(new,path:path.isEmpty || new.node(path)?.isDirectory == true ? path : "")
            };return location
        }
        for (key,parent) in archiveParents {archiveParents[key]=mapped(parent)}
        if let parent=archiveParents[ObjectIdentifier(old)] {archiveParents[ObjectIdentifier(new)]=parent}
        if let lease=archiveLeases[ObjectIdentifier(old)] {archiveLeases[ObjectIdentifier(new)]=lease}
        for pane in [left,right] {
            pane.tabs=pane.tabs.map(mapped);pane.backHistory=pane.backHistory.map(mapped);pane.forwardHistory=pane.forwardHistory.map(mapped)
            let next=mapped(pane.location)
            if next != pane.location {navigate(next,pane:pane,recordHistory:false,focus:false)}
        }
    }
    func canMutateArchive(_ session:ArchiveBrowserSession)->Bool {
        do {
            guard session.isWritableZIP else{throw ArchiveBrowserError.message("This archive format supports browsing, viewing and extraction. Member changes require an unencrypted ZIP.")}
            func writable(_ origin:ArchiveWritebackOrigin)->Bool {if case .nested(let parent,_,let ancestor,_)=origin{return parent.isWritableZIP && writable(ancestor)};return true}
            guard writable(try archiveOrigin(session)) else{throw ArchiveBrowserError.message("An enclosing archive is read-only. Extract the ZIP before modifying it.")};return true
        }catch{showError(error);return false}
    }

    func runArchiveMutation(_ name:String,session:ArchiveBrowserSession,operation:@escaping ()throws->ArchiveBrowserSession) {
        guard !busy,canMutateArchive(session) else{return}
        let origin:ArchiveWritebackOrigin
        do {origin=try archiveOrigin(session)}catch{showError(error);return}
        busy=true;status.stringValue=name+"…"
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            let result=Result {try ArchiveWritebackService.commit(old:session,new:operation(),origin:origin)}
            DispatchQueue.main.async {
                guard let self else{return};self.busy=false
                switch result {
                case .success(let report):self.applyArchiveWriteback(report);self.status.stringValue=name+" completed"+(report.warnings.isEmpty ? "" : " — "+report.warnings.joined(separator:"; "))
                case .failure(let error):self.showError(error)
                }
                self.drainArchiveUpdates()
            }
        }
    }
}


extension CommanderController {
    func unpackArchive(_ archive:URL,to destination:URL,tool:URL,password:String?=nil) {
        guard !busy else{return};busy=true;status.stringValue="Unpacking…"
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            let result=Result {
                _=try NativeOperations.listArchive(archive:archive,tool:tool,password:password)
                try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:false)
                do {try NativeOperations.unpack(archive:archive,destination:destination,tool:tool,password:password)}
                catch {_ = destination.path.withCString{rmdir($0)};throw error}
            }
            DispatchQueue.main.async {
                guard let self else{return};self.busy=false
                switch result {
                case .success:self.refresh();self.status.stringValue="Extracted to "+destination.path
                case .failure(let error):
                    if error is ArchivePasswordRequired {self.requestArchivePassword(name:archive.lastPathComponent,retry:password != nil){[weak self] value in self?.unpackArchive(archive,to:destination,tool:tool,password:value)}}
                    else {self.showError(error)}
                }
                self.drainArchiveUpdates()
            }
        }
    }
}
