import AppKit

final class CommanderButtonStrip:NSStackView {
    var configure:(()->Void)?
    override func menu(for event:NSEvent)->NSMenu? {
        let menu=NSMenu();let item=NSMenuItem(title:"Change…",action:#selector(change),keyEquivalent:"");item.target=self;menu.addItem(item);return menu
    }
    @objc private func change(){configure?()}
}
extension CommanderController {
    func rebuildButtonBar() {
        for view in buttonBar.arrangedSubviews {buttonBar.removeArrangedSubview(view);view.removeFromSuperview()}
        for (index,item) in barConfiguration.items.enumerated() {
            if item.separator {
                let line=NSBox();line.boxType = .separator;line.widthAnchor.constraint(equalToConstant:1).isActive=true;line.heightAnchor.constraint(equalToConstant:CGFloat(barConfiguration.iconSize)).isActive=true;buttonBar.addArrangedSubview(line);continue
            }
            let button=NSButton(title:barConfiguration.showLabels ? item.title : "",target:self,action:#selector(buttonBarAction(_:)))
            let image: NSImage?
            if item.icon.hasPrefix("/") || item.icon.hasPrefix("~/") {image=NSImage(contentsOfFile:(item.icon as NSString).expandingTildeInPath)}
            else {image=Bundle.main.resourceURL.flatMap{NSImage(contentsOf:$0.appendingPathComponent("icons/"+item.icon+".png"))}}
            let fallback=item.command.hasPrefix("/") || item.command.hasPrefix("~/") ? NSWorkspace.shared.icon(forFile:(item.command as NSString).expandingTildeInPath) : NSImage(systemSymbolName:"gearshape",accessibilityDescription:item.title)
            button.image=(image ?? fallback)?.copy() as? NSImage;button.image?.size=NSSize(width:CGFloat(barConfiguration.iconSize),height:CGFloat(barConfiguration.iconSize))
            button.imagePosition=barConfiguration.showLabels ? .imageLeading : .imageOnly
            button.bezelStyle = .smallSquare;button.tag=index;button.toolTip=item.title;button.setAccessibilityLabel(item.title)
            button.heightAnchor.constraint(equalToConstant:CGFloat(barConfiguration.iconSize+10)).isActive=true
            if !barConfiguration.showLabels {button.widthAnchor.constraint(equalToConstant:CGFloat(barConfiguration.iconSize+12)).isActive=true}
            let menu=NSMenu();let edit=NSMenuItem(title:"Change…",action:#selector(configureButtonBar),keyEquivalent:"");edit.target=self;menu.addItem(edit);button.menu=menu
            buttonBar.addArrangedSubview(button)
        }
        // A small permanent editor affordance also makes an empty bar recoverable.
        let edit=NSButton(title:"…",target:self,action:#selector(configureButtonBar));edit.toolTip="Change button bar";edit.setAccessibilityLabel("Change button bar");edit.bezelStyle = .smallSquare;buttonBar.addArrangedSubview(edit)
        barHeight?.constant=CGFloat(barConfiguration.iconSize+26)
    }
    @objc func configureButtonBar() {
        if let editor=barEditor {editor.showWindow(nil);editor.window?.makeKeyAndOrderFront(nil);return}
        let editor=ButtonBarEditor(self);barEditor=editor;editor.window?.center();editor.showWindow(nil);editor.window?.makeKeyAndOrderFront(nil)
    }
    @objc func buttonBarAction(_ sender:NSButton) {
        guard !busy,window.attachedSheet==nil,barConfiguration.items.indices.contains(sender.tag) else{return}
        let item=barConfiguration.items[sender.tag]
        guard !item.separator else{return}
        if item.command.lowercased().hasPrefix("cm_") {
            if !dispatchInternalCommand(item.command) {showMessage("Unavailable command",item.command+" is not available in the current pane.")};return
        }
        do {
            let url=URL(fileURLWithPath:(item.command as NSString).expandingTildeInPath)
            let args=try CommanderButtonBar.arguments(item.parameters)
            var directory:ObjCBool=false
            guard FileManager.default.fileExists(atPath:url.path,isDirectory:&directory) else {throw CommanderButtonBar.failure("The button target no longer exists: "+url.path)}
            if url.pathExtension.lowercased()=="app" {
                let options=NSWorkspace.OpenConfiguration();options.arguments=args
                NSWorkspace.shared.openApplication(at:url,configuration:options){[weak self] _,error in if let error{DispatchQueue.main.async{self?.showError(error)}}};return
            }
            if directory.boolValue {navigate(url);return}
            guard FileManager.default.isExecutableFile(atPath:url.path) else {NSWorkspace.shared.open(url);return}
            let cwd:URL
            if !item.directory.isEmpty {cwd=URL(fileURLWithPath:(item.directory as NSString).expandingTildeInPath)}
            else if let local=activePane.location.localDirectory {cwd=local}
            else {throw CommanderButtonBar.failure("Set a local Start path to run a program while browsing FTP or archives.")}
            runOperation("Running "+item.title,success:"Button command finished") {
                let process=Process();process.executableURL=url;process.arguments=args;process.currentDirectoryURL=cwd
                process.standardInput=FileHandle.nullDevice;process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.nullDevice
                try process.run();process.waitUntilExit()
                if process.terminationStatus != 0 {throw CommanderButtonBar.failure("Program exited with status \(process.terminationStatus).")}
            }
        } catch {showError(error)}
    }
}
