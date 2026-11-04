import Foundation

/// Total Commander-style include masks separated by semicolons, followed by | exclusions.
enum PanelFilter {
    static func matches(name:String,mask:String)->Bool {
        let parts=mask.split(separator:"|",maxSplits:1,omittingEmptySubsequences:false).map(String.init)
        func group(_ value:String)->Bool {
            value.split(separator:";").contains { raw in
                let pattern=raw.trimmingCharacters(in:.whitespaces)
                if pattern=="*.*" || pattern=="*" {return true}
                let expression="^"+pattern.map{$0=="*" ? ".*" : ($0=="?" ? "." : NSRegularExpression.escapedPattern(for:String($0)))}.joined()+"$"
                return name.range(of:expression,options:[.regularExpression,.caseInsensitive]) != nil
            }
        }
        return (parts.first?.trimmingCharacters(in:.whitespaces).isEmpty != false || group(parts[0])) && (parts.count<2 || !group(parts[1]))
    }
    static func isProgram(_ entry:FileEntry)->Bool {
        if ["app","exe","com","bat","cmd","sh","command"].contains((entry.name as NSString).pathExtension.lowercased()) {return true}
        return entry.url.isFileURL && !entry.isDirectory && FileManager.default.isExecutableFile(atPath:entry.url.path)
    }
}
enum SelectionFile {
    static func encode(_ names:[String])throws->Data {
        guard names.allSatisfy({!$0.contains("\n") && !$0.contains("\r") && !$0.contains("\0")}) else {throw NSError(domain:"SelectionFile",code:1,userInfo:[NSLocalizedDescriptionKey:"A selected filename contains a line break and cannot be saved in a selection list."])}
        return Data((names.joined(separator:"\r\n")+"\r\n").utf8)
    }
    static func decode(_ data:Data)throws->Set<String> {
        guard data.count<=16*1024*1024 else {throw NSError(domain:"SelectionFile",code:2,userInfo:[NSLocalizedDescriptionKey:"Selection list exceeds 16 MiB."])}
        let text:String?
        if data.starts(with:[0xff,0xfe]) || data.starts(with:[0xfe,0xff]) {text=String(data:data,encoding:.utf16)}
        else {text=String(data:data,encoding:.utf8) ?? String(data:data,encoding:.windowsCP1252)}
        guard let text else {throw NSError(domain:"SelectionFile",code:3,userInfo:[NSLocalizedDescriptionKey:"Cannot decode selection list."])}
        return Set(text.replacingOccurrences(of:"\u{feff}",with:"").components(separatedBy:.newlines).filter{!$0.isEmpty})
    }
}

#if !PANEL_COMMANDS_TEST
import AppKit
extension CommanderController {
    @objc func showPrograms() {activePane.fileMask="";activePane.selectedOnly=nil;activePane.showProgramsOnly=true;recordManualViewChange(in:activePane);refreshSource()}
    @objc func customFileMask() {
        let pane=activePane
        prompt(title:"Define selection",detail:"Include masks separated by semicolons. Put exclusions after |.",value:pane.fileMask.isEmpty ? "*.*" : pane.fileMask,action:"OK") { [weak self] mask in
            pane.fileMask=mask;pane.showProgramsOnly=false;pane.selectedOnly=nil
            UserDefaults.standard.set(mask,forKey:"lastFileMask");self?.recordManualViewChange(in:pane);self?.reloadPane(pane)
        }
    }
    @objc func lastFileMask() {activePane.fileMask=UserDefaults.standard.string(forKey:"lastFileMask") ?? "*.*";activePane.showProgramsOnly=false;activePane.selectedOnly=nil;recordManualViewChange(in:activePane);refreshSource()}
    @objc func showSelectedOnly() {activePane.selectedOnly=Set(activePane.selectedEntries.map(\.url));recordManualViewChange(in:activePane);reloadPane(activePane)}
    @objc func reverseOrder() {activePane.ascending.toggle();activePane.sortEntries();activePane.table.reloadData();activePane.updateFooter();recordManualViewChange(in:activePane)}
    @objc func unsortedOrder() {activePane.sortColumn="unsorted";recordManualViewChange(in:activePane);refreshSource()}
    @objc func saveSelectionFile() {
        let names=activePane.selectedEntries.map(\.name)
        guard !names.isEmpty else{return}
        let panel=NSSavePanel();panel.nameFieldStringValue="selection.txt";panel.directoryURL=activePane.location.localDirectory
        guard panel.runModal() == .OK,let url=panel.url else{return}
        do {try SelectionFile.encode(names).write(to:url,options:.atomic)}catch{showError(error)}
    }
    @objc func loadSelectionFile() {
        let pane=activePane,panel=NSOpenPanel();panel.canChooseDirectories=false;panel.allowsMultipleSelection=false
        guard panel.runModal() == .OK,let url=panel.url else{return}
        do {
            let values=try url.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey]);guard values.isRegularFile==true,(values.fileSize ?? Int.max)<=16*1024*1024 else {throw FileServiceError.invalid("Choose a regular selection list up to 16 MiB.")}
            let names=try SelectionFile.decode(Data(contentsOf:url));pane.savedSelection=pane.marked
            pane.marked=Set(pane.entries.filter{names.contains($0.name) || names.contains($0.url.path)}.map(\.url));pane.table.reloadData();pane.updateFooter()
        }catch{showError(error)}
    }
    func copyDetails(withPaths:Bool) {
        let date=ISO8601DateFormatter()
        let lines=activePane.selectedEntries.map{entry in
            [withPaths ? shortcutEntryPath(entry) : entry.name,entry.isDirectory ? "<DIR>" : String(entry.size),entry.modified.map{date.string(from:$0)} ?? "",entry.isSymbolicLink ? "link" : (entry.isDirectory ? "d---" : "-a--")].joined(separator:"\t")
        }
        NSPasteboard.general.clearContents();NSPasteboard.general.setString(lines.joined(separator:"\r\n"),forType:.string)
    }
    @objc func disconnectFTP() {
        guard case .ftp(let client,_)=activePane.location else{return}
        for pane in [left,right] {
            pane.loadTask?.cancel()
            let home=PaneLocation.local(pane.directory)
            pane.tabs=pane.tabs.map {if case .ftp(let candidate,_) = $0,candidate===client{return home};return $0}
            pane.backHistory.removeAll{if case .ftp(let candidate,_) = $0{return candidate===client};return false}
            pane.forwardHistory.removeAll{if case .ftp(let candidate,_) = $0{return candidate===client};return false}
            if case .ftp(let candidate,_)=pane.location,candidate===client {navigate(home,pane:pane,recordHistory:false,focus:false)}
            pane.updateTabs()
        }
        status.stringValue="FTP disconnected"
    }
}
#endif
