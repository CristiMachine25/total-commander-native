import AppKit

private final class FilePartsProgress: NSWindowController, NSWindowDelegate {
    let task = FilePartsTask()
    private let detail = NSTextField(labelWithString:"Preparing…"), indicator = NSProgressIndicator()
    init(title: String) {
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:440,height:130),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        super.init(window:window); window.title=title; window.isReleasedWhenClosed=false;window.delegate=self
        let cancel=NSButton(title:"Cancel",target:self,action:#selector(cancelJob))
        indicator.isIndeterminate=false;indicator.minValue=0;indicator.maxValue=100
        let stack=NSStackView(views:[detail,indicator,cancel]);stack.orientation = .vertical;stack.spacing=14;stack.translatesAutoresizingMaskIntoConstraints=false
        window.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor,constant:20),stack.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor,constant:-20),stack.topAnchor.constraint(equalTo:window.contentView!.topAnchor,constant:20),indicator.widthAnchor.constraint(equalTo:stack.widthAnchor)])
        window.center()
    }
    required init?(coder:NSCoder){fatalError()}
    func update(_ complete:UInt64,_ total:UInt64) {
        DispatchQueue.main.async { [weak self] in
            self?.indicator.doubleValue=total==0 ? 0 : Double(complete)/Double(total)*100
            self?.detail.stringValue="\(complete) / \(total) bytes"
        }
    }
    @objc private func cancelJob(){task.cancel();detail.stringValue="Cancelling…"}
    func windowShouldClose(_ sender:NSWindow)->Bool{cancelJob();return false}
    func finished(){window?.delegate=nil;close()}
}
extension CommanderController {
    @objc func splitFile() {
        guard permitFileAction(),!busy,let entry=activePane.currentEntry,!entry.isDirectory,!entry.isSymbolicLink,entry.url.isFileURL else {showMessage("Split File","Choose one ordinary local file.");return}
        let dialog=NSAlert();dialog.messageText="Split “\(entry.name)”";dialog.informativeText="Bytes per part (k, M and G use powers of 1024). Output uses .001 through .999 plus a CRC verification file."
        dialog.addButton(withTitle:"Choose Destination");dialog.addButton(withTitle:"Cancel")
        let size=NSComboBox(frame:NSRect(x:0,y:0,width:260,height:26));size.addItems(withObjectValues:["1M","10M","100M","1G"]);size.stringValue="10M";dialog.accessoryView=size
        guard dialog.runModal() == .alertFirstButtonReturn else{return}
        do {
            let partSize=try FilePartsService.parsePartSize(size.stringValue)
            let panel=NSOpenPanel();panel.canChooseFiles=false;panel.canChooseDirectories=true;panel.canCreateDirectories=true;panel.allowsMultipleSelection=false;panel.directoryURL=otherPane.location.localDirectory ?? entry.url.deletingLastPathComponent();panel.prompt="Split Here"
            guard panel.runModal() == .OK,let target=panel.url else{return}
            let progress=FilePartsProgress(title:"Split File");progress.showWindow(nil)
            runOperation("Splitting file",success:"Split files and CRC verification created") {
                defer{DispatchQueue.main.async{progress.finished()}}
                _=try FilePartsService.split(source:entry.url,destination:target,bytesPerPart:partSize,task:progress.task,progress:progress.update)
            }
        } catch {showError(error)}
    }
    @objc func combineFiles() {
        guard permitFileAction(),!busy,let entry=activePane.currentEntry,!entry.isDirectory,!entry.isSymbolicLink,entry.url.isFileURL else{showMessage("Combine Files","Choose the first ordinary local part (.001, .000 or aa).");return}
        do {
            let plan=try FilePartsService.inspect(firstPart:entry.url)
            let panel=NSSavePanel();panel.nameFieldStringValue=plan.suggestedName;panel.directoryURL=otherPane.location.localDirectory ?? entry.url.deletingLastPathComponent();panel.prompt="Combine";panel.message="Combine \(plan.parts.count) consecutive parts. " + (plan.manifest == nil ? "No CRC file found; completeness cannot be verified." : "Original size and CRC32 will be verified.")
            guard panel.runModal() == .OK,let target=panel.url else{return}
            let progress=FilePartsProgress(title:"Combine Files");progress.showWindow(nil)
            runOperation("Combining files",success:"Parts combined and available CRC verified") {
                defer{DispatchQueue.main.async{progress.finished()}}
                _=try FilePartsService.combine(firstPart:entry.url,destination:target,task:progress.task,progress:progress.update)
            }
        } catch {showError(error)}
    }
}
