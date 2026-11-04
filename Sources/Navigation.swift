import AppKit

extension CommanderController {
    @objc func homeFolder() { navigate(FileManager.default.homeDirectoryForCurrentUser) }
    @objc func backFolder() {
        guard !busy,!activePane.isLoading else{return}
        let pane=activePane,previous=pane.location
        var history=pane.backHistory
        while history.last == previous {history.removeLast()}
        guard let next=history.popLast() else{return}
        let future=pane.forwardHistory+[previous]
        navigate(next,pane:pane,recordHistory:false) {success in if success {pane.backHistory=history;pane.forwardHistory=future}}
    }
    @objc func forwardFolder() {
        guard !busy,!activePane.isLoading else{return}
        let pane=activePane,previous=pane.location
        var future=pane.forwardHistory
        while future.last == previous {future.removeLast()}
        guard let next=future.popLast() else{return}
        let history=pane.backHistory+[previous]
        navigate(next,pane:pane,recordHistory:false) {success in if success {pane.forwardHistory=future;pane.backHistory=history}}
    }
    @objc func newTab() {openLocationInNewTab(activePane.location)}
    @objc func closeTab() {closeFolderTab(activePane.selectedTab,pane:activePane)}
    @objc func invertSelection() {
        let all = Set(activePane.entries.filter{runtimeConfig.selectionIncludesDirectories || !$0.isDirectory}.map(\.url)); activePane.marked = activePane.marked.symmetricDifference(all)
        activePane.table.reloadData(); activePane.updateFooter()
    }
    @objc func clearSelection() { activePane.clearMarks() }
    @objc func runCommand(_ field: NSTextField) {
        var command = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, !busy else { return }
        do {if let alias=try configuredShortcuts().command(forAlias:command){command=alias}}
        catch {showError(error);return}
        if command.lowercased().hasPrefix("cm_") {
            field.stringValue = ""
            if !dispatchInternalCommand(command) { showMessage("Unknown internal command",command + " is not implemented in this native build.") }
            return
        }
        if command == "cd" { homeFolder(); field.stringValue = ""; return }
        if command.hasPrefix("cd ") { go(String(command.dropFirst(3))); field.stringValue = ""; return }
        guard requireLocalPane() else {return}
        var history = UserDefaults.standard.stringArray(forKey: "commandHistory") ?? []
        history.removeAll { $0 == command }; history.insert(command,at:0); UserDefaults.standard.set(Array(history.prefix(runtimeConfig.historyLimit)),forKey:"commandHistory")
        let directory = activePane.directory
        // Deliberate shell command entered by the user, never filenames interpolated into it.
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        runOperation("Running command", success: "Command finished") { [weak self] in
            FileManager.default.createFile(atPath: output.path, contents: nil)
            let file = try FileHandle(forWritingTo: output); defer { try? file.close() }
            let task = Process(); task.executableURL = URL(fileURLWithPath: "/bin/zsh")
            task.arguments = ["-c", command]; task.currentDirectoryURL = directory
            task.standardOutput = file; task.standardError = file; task.standardInput = FileHandle.nullDevice
            try task.run(); task.waitUntilExit()
            DispatchQueue.main.async { [weak self] in
                do { try EditorController.open(url: output, editable: false) } catch { self?.showError(error) }
            }
            if task.terminationStatus != 0 { throw FileServiceError.invalid("Command exited with status \(task.terminationStatus). Output is shown in the viewer.") }
        }
        field.stringValue = ""
    }
    @objc func openMenuButton(_ sender: NSButton) {
        let menu = makeMenu(sender.title)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }
    func makeMenu(_ title: String) -> NSMenu {
        if let original = referenceMenu(title: title) { return original }
        let menu = NSMenu(title: title)
        func item(_ title: String, _ action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = []) {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
            entry.target = self; entry.keyEquivalentModifierMask = modifiers; menu.addItem(entry)
        }
        func function(_ title: String, _ tag: Int) {
            let entry = NSMenuItem(title: title, action: #selector(menuAction(_:)), keyEquivalent: ""); entry.target = self; entry.tag = tag; menu.addItem(entry)
        }
        switch title {
        case "Files":
            function("View\tF3",3); function("Edit\tF4",4); function("Copy\tF5",5); function("Move/Rename\tF6",6)
            item("Rename…",#selector(renameCurrent),key:"r",modifiers:[.command,.shift]); function("New folder\tF7",7); function("Delete\tF8",8); menu.addItem(.separator())
            item("Pack files…\tAlt+F5",#selector(packFiles)); item("Unpack files…\tAlt+F9",#selector(unpackFiles))
            item("Compare by Contents…",#selector(compareFiles)); item("Calculate Occupied Space…\tCtrl+L",#selector(calculateSpace)); item("Properties…\tAlt+Enter",#selector(fileProperties)); item("Compare directories…",#selector(compareDirectories)); item("Multi-Rename Tool…\tCtrl+M",#selector(multiRename))
            item("Create checksum file…",#selector(createChecksums)); item("Verify checksums…",#selector(verifyChecksums)); item("Calculate SHA-256 checksums…",#selector(checksumFiles)); menu.addItem(.separator())
            let close = NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
            close.keyEquivalentModifierMask = [.command]; menu.addItem(close)
            item("Quit\tAlt+F4",#selector(exitApp))
        case "Mark": item("Select All\tCtrl+A",#selector(selectAllFiles)); item("Unselect All",#selector(clearSelection)); item("Invert Selection",#selector(invertSelection))
        case "Commands":
            item("Search…\tAlt+F7",#selector(searchFiles)); item("Synchronize Dirs…",#selector(synchronizeDirectories)); item("Go to parent",#selector(parent)); item("Go to home",#selector(homeFolder)); item("Directory hotlist…\tCtrl+D",#selector(showPlaces))
            item("Back\tAlt+Left",#selector(backFolder)); item("Forward\tAlt+Right",#selector(forwardFolder)); item("Swap panels\tCtrl+U",#selector(swap))
            item("New folder tab\tCtrl+T",#selector(newTab)); item("Close folder tab\tCtrl+W",#selector(closeTab))
        case "Show": item("Brief\tCtrl+F1",#selector(briefView)); item("Full\tCtrl+F2",#selector(fullView)); item("Quick Filter\tCtrl+S",#selector(quickFilter)); item("All Files\tCtrl+F10",#selector(showAllFiles)); item("Refresh\tCtrl+R",#selector(refreshSource)); item("Hidden files",#selector(hidden(_:))); item("Go to path…",#selector(focusPath))
        case "Help": item("Keyboard guide",#selector(help)); item("Implementation coverage",#selector(coverage))
        case "Net": item("FTP Connect…\tCtrl+F",#selector(connectFTP)); item("FTP New Connection…\tCtrl+N",#selector(connectFTP)); item("Mounted disks and network volumes…",#selector(showPlaces))
        case "Start": item("Focus command line",#selector(focusCommand))
        case "Configuration": item("Options…",#selector(configuration)); item("Change Settings Files Directly…",#selector(configurationFile)); item("Show hidden files",#selector(hidden(_:)))
        default: break
        }
        return menu
    }
    @objc func showPlaces() { places() }
    @objc func focusCommand() { window.makeFirstResponder(commandField) }
    @objc func exitApp() { NSApp.terminate(nil) }
    @objc func coverage() {
        showMessage("Native implementation coverage", "Implemented scopes include local file management, queued transfers, copy-only synchronization, rename masks, ZIP browsing, FTP/FTPS, checksums and text comparison. This remains an independent native reconstruction with incomplete Total Commander parity. See the bundled analysis/native-coverage.md and remaining-parity-gaps.md for tested scope and differences.")
    }
}

extension CommanderController {
    @objc func synchronizeDirectories() { guard requireLocalPane(left),requireLocalPane(right) else {return}; SynchronizationController.show(left:activePane.directory,right:otherPane.directory,onComplete:{ [weak self] in self?.refresh() }) }
}

extension CommanderController {
    @objc func connectFTP() {
        let pane:Pane
        switch runtimeConfig.ftpOpenPanel {case 1:pane=left;case 2:pane=right;case 3:pane=otherPane;default:pane=activePane}
        let options=FTPConnectionOptions(passiveMode:runtimeConfig.ftpPassiveMode,connectTimeout:runtimeConfig.ftpConnectTimeout,transferTimeout:runtimeConfig.ftpTransferTimeout)
        FTPBrowserWindow(downloadDirectory:otherPane.directory,options:options,onConnect:{ [weak self,weak pane] client,path in
            guard let self,let pane else{return};self.navigate(.ftp(client,path:path),pane:pane)
        }).display()
    }
}
