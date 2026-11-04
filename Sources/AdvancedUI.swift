import AppKit

private final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}

private var advancedWindows: [NSWindowController] = []

private class ResultsWindow: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    let table = NSTableView()
    let message = NSTextField(wrappingLabelWithString: "")
    let contentStack = NSStackView()
    var rows: [[String]] = []
    var onOpen: ((Int) -> Void)?
    var onClose: (() -> Void)?

    init(title: String, columns: [(String, CGFloat)]) {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 520), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.title = title; w.isReleasedWhenClosed = false
        super.init(window: w); w.delegate = self
        table.dataSource = self; table.delegate = self
        table.target = self; table.doubleAction = #selector(openRow)
        table.rowHeight = 23; table.usesAlternatingRowBackgroundColors = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        for (index, column) in columns.enumerated() {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(String(index)))
            c.title = column.0; c.width = column.1; c.minWidth = 70; table.addTableColumn(c)
        }
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.documentView = table
        contentStack.orientation = .vertical; contentStack.alignment = .leading; contentStack.spacing = 9
        contentStack.addArrangedSubview(scroll); contentStack.addArrangedSubview(message)
        w.contentView!.addSubview(contentStack); contentStack.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false; message.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: w.contentView!.leadingAnchor, constant: 14),
            contentStack.trailingAnchor.constraint(equalTo: w.contentView!.trailingAnchor, constant: -14),
            contentStack.topAnchor.constraint(equalTo: w.contentView!.topAnchor, constant: 14),
            contentStack.bottomAnchor.constraint(equalTo: w.contentView!.bottomAnchor, constant: -14),
            scroll.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180),
            message.widthAnchor.constraint(equalTo: contentStack.widthAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func display() { advancedWindows.append(self); window?.center(); showWindow(nil) }
    func windowWillClose(_ notification: Notification) { onClose?(); advancedWindows.removeAll { $0 === self } }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row), let column = Int(tableColumn?.identifier.rawValue ?? "0"), rows[row].indices.contains(column) else { return nil }
        let label = NSTextField(labelWithString: rows[row][column]); label.lineBreakMode = .byTruncatingMiddle; label.toolTip = rows[row][column]
        label.font = NSFont.systemFont(ofSize: 12); return label
    }
    @objc private func openRow() { let row = table.clickedRow; if rows.indices.contains(row) { onOpen?(row) } }
    func setRows(_ value: [[String]], detail: String) { rows = value; table.reloadData(); message.stringValue = detail }
}

private final class SearchWindow: ResultsWindow {
    let root: URL
    let pattern = NSTextField(string: "*")
    let contains = NSTextField(string: "")
    let hidden = NSButton(checkboxWithTitle: "Include hidden files", target: nil, action: nil)
    let start = NSButton(title: "Start search", target: nil, action: nil)
    let cancel = NSButton(title: "Stop", target: nil, action: nil)
    var matches: [URL] = []
    var cancellation: CancellationFlag?
    let navigate: (URL) -> Void

    init(root: URL, showHidden: Bool, navigate: @escaping (URL) -> Void) {
        self.root = root; self.navigate = navigate
        super.init(title: "Find Files — \(root.path)", columns: [("Name", 200), ("Path", 570)])
        pattern.placeholderString = "File-name wildcard, for example *.swift"
        contains.placeholderString = "UTF-8 text, case-sensitive (optional)"
        hidden.state = showHidden ? .on : .off
        start.target = self; start.action = #selector(search)
        cancel.target = self; cancel.action = #selector(stop); cancel.isEnabled = false
        let fields = NSStackView(views: [NSTextField(labelWithString: "Search for:"), pattern, NSTextField(labelWithString: "Containing:"), contains])
        fields.orientation = .horizontal; fields.spacing = 8
        let controls = NSStackView(views: [hidden, start, cancel]); controls.orientation = .horizontal; controls.spacing = 12
        contentStack.insertArrangedSubview(fields, at: 0); contentStack.insertArrangedSubview(controls, at: 1)
        fields.translatesAutoresizingMaskIntoConstraints = false; fields.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        pattern.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        contains.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        message.stringValue = "Searches within \(root.path). Double-click a result to show it in the active panel."
        onOpen = { [weak self] row in guard let self, self.matches.indices.contains(row) else { return }; self.navigate(self.matches[row]) }
        onClose = { [weak self] in self?.cancellation?.cancel() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func stop() { cancellation?.cancel(); message.stringValue = "Stopping search…" }
    @objc private func search() {
        guard cancellation == nil else { return }
        let flag = CancellationFlag(); cancellation = flag
        let query = pattern.stringValue.isEmpty ? "*" : pattern.stringValue
        let text = contains.stringValue.isEmpty ? nil : contains.stringValue
        let includeHidden = hidden.state == .on
        start.isEnabled = false; cancel.isEnabled = true; message.stringValue = "Searching \(root.path)…"
        let searchRoot = root
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let report = try NativeOperations.search(root: searchRoot, pattern: query, contains: text, showHidden: includeHidden, cancelled: { flag.isCancelled })
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.matches = report.matches
                    let warnings = report.warnings.isEmpty ? "" : "\n" + report.warnings.prefix(5).joined(separator: "\n") + (report.warnings.count > 5 ? "\n\(report.warnings.count - 5) more warnings." : "")
                    self.setRows(report.matches.map { [$0.lastPathComponent, $0.path] }, detail: "\(report.matches.count) result(s)\(report.cancelled ? " — search stopped; results are partial" : "").\(warnings)")
                    self.start.isEnabled = true; self.cancel.isEnabled = false; self.cancellation = nil
                }
            } catch {
                DispatchQueue.main.async { guard let self else { return }; self.message.stringValue = error.localizedDescription; self.start.isEnabled = true; self.cancel.isEnabled = false; self.cancellation = nil }
            }
        }
    }
}

private final class RenameWindow: ResultsWindow {
    let openedAt = Date()
    let sources: [URL]
    let find = NSTextField(string: "")
    let replacement = NSTextField(string: "")
    let nameMask = NSTextField(string: "[N]")
    let extensionMask = NSTextField(string: "[E]")
    let counterStart = NSTextField(string: "1")
    let counterStep = NSTextField(string: "1")
    let counterDigits = NSTextField(string: "1")
    let regex = NSButton(checkboxWithTitle:"RegEx",target:nil,action:nil)
    let caseSensitive = NSButton(checkboxWithTitle:"Case sensitive",target:nil,action:nil)
    let caseMode = NSPopUpButton(frame:.zero,pullsDown:false)
    let apply = NSButton(title: "Rename", target: nil, action: nil)
    var preview: [RenameItem] = []
    let performRename: ([RenameItem]) -> Void

    init(sources: [URL], perform: @escaping ([RenameItem]) -> Void) {
        self.sources = sources; self.performRename = perform
        super.init(title: "Multi-Rename Tool", columns: [("Old name", 370), ("New name", 370)])
        caseMode.addItems(withTitles:RenameMaskOptions.CaseConversion.allCases.map(\.rawValue))
        let grid = NSGridView(views: [
            [NSTextField(labelWithString:"Rename mask: File name"),nameMask,NSTextField(labelWithString:"Extension"),extensionMask],
            [NSTextField(labelWithString:"Search for"),find,NSTextField(labelWithString:"Replace with"),replacement],
            [NSTextField(labelWithString:"Counter start"),counterStart,NSTextField(labelWithString:"Step"),counterStep],
            [NSTextField(labelWithString:"Digits (0 = auto)"),counterDigits,NSTextField(labelWithString:"Upper/lowercase"),caseMode],
            [regex,caseSensitive,NSView(),NSView()]])
        grid.columnSpacing = 10; grid.rowSpacing = 8
        for input in [find,replacement,nameMask,extensionMask] { input.widthAnchor.constraint(greaterThanOrEqualToConstant:150).isActive = true }
        let refresh = NSButton(title: "Preview", target: self, action: #selector(updatePreview))
        apply.target = self; apply.action = #selector(confirmRename); apply.isEnabled = false
        let controls = NSStackView(views: [refresh, apply]); controls.orientation = .horizontal; controls.spacing = 10
        contentStack.insertArrangedSubview(grid, at: 0); contentStack.insertArrangedSubview(controls, at: 1)
        message.stringValue = "[N] Name · [E] Extension · [C] Counter · [N1-5] Range · [Y][M][D] Date. Preview before applying."
        setRows(sources.map { [$0.lastPathComponent, $0.lastPathComponent] }, detail: message.stringValue)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func updatePreview() {
        do {
            guard let start=Int(counterStart.stringValue), let step=Int(counterStep.stringValue), let digits=Int(counterDigits.stringValue), digits >= 0 else { throw FileServiceError.invalid("Enter integer counter values; digits must be zero or positive.") }
            var options=RenameMaskOptions(); options.openedAt=openedAt; options.nameMask=nameMask.stringValue; options.extensionMask=extensionMask.stringValue
            options.counterStart=start; options.counterStep=step; options.counterDigits=digits == 0 ? nil : digits
            options.search=find.stringValue; options.replacement=replacement.stringValue; options.regularExpression=regex.state == .on; options.caseSensitiveSearch=caseSensitive.state == .on
            options.caseConversion=RenameMaskOptions.CaseConversion(rawValue:caseMode.titleOfSelectedItem ?? "unchanged") ?? .unchanged
            preview = try RenameMaskEngine.preview(sources:sources,options:options).map { RenameItem(source:$0.source,destination:$0.destination) }.filter { $0.source != $0.destination }
            setRows(preview.map { [$0.source.lastPathComponent, $0.destination.lastPathComponent] }, detail: preview.isEmpty ? "No names would change." : "\(preview.count) rename(s) ready. Existing destinations and collisions are checked before applying.")
            apply.isEnabled = !preview.isEmpty
        } catch { preview = []; apply.isEnabled = false; message.stringValue = error.localizedDescription }
    }
    @objc private func confirmRename() {
        updatePreview(); guard !preview.isEmpty, let window else { return }
        let plan = preview
        let alert = NSAlert(); alert.messageText = "Rename \(plan.count) item(s)?"; alert.informativeText = "Apply the previewed names. No existing destination will be overwritten."
        alert.addButton(withTitle: "Rename"); alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            self.performRename(plan); self.close()
        }
    }
}

extension CommanderController {
    private func archiveTool() throws -> URL {
        guard let tool = Bundle.main.url(forResource: "7zz", withExtension: nil), FileManager.default.isExecutableFile(atPath: tool.path) else { throw FileServiceError.invalid("The bundled archive tool is missing. Reinstall the app.") }
        return tool
    }
    private func validArchiveName(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else { throw FileServiceError.invalid("Enter a file name without / or a null character.") }
    }
    @objc func searchFiles() {
        guard requireLocalPane() else {return}
        let search = SearchWindow(root: activePane.directory, showHidden: showHidden) { [weak self] url in
            guard let self else { return }
            self.navigate(url.deletingLastPathComponent())
            if let i = self.activePane.entries.firstIndex(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
                self.activePane.table.selectRowIndexes(IndexSet(integer: i + 1), byExtendingSelection: false); self.activePane.table.scrollRowToVisible(i + 1)
            }
            self.window.makeKeyAndOrderFront(nil)
        }
        search.display()
    }
    @objc func multiRename() {
        guard requireLocalPane() else {return}
        let sources = activePane.selectedURLs
        guard !sources.isEmpty else { NSSound.beep(); return }
        RenameWindow(sources: sources) { [weak self] plan in self?.runOperation("Renaming", success: "Renamed \(plan.count) item(s)") { try NativeOperations.applyRename(plan) } }.display()
    }
    @objc func compareDirectories() {
        guard requireLocalPane(),requireLocalPane(otherPane) else {return}
        let leftURL = activePane.directory, rightURL = otherPane.directory
        let result = ResultsWindow(title: "Compare Directories", columns: [("Status", 160), ("Relative path", 610)])
        let flag = CancellationFlag(); result.onClose = { flag.cancel() }
        result.message.stringValue = "Comparing file contents…\nSource: \(leftURL.path)\nTarget: \(rightURL.path)"; result.display()
        DispatchQueue.global(qos: .userInitiated).async { [weak result] in
            do {
                let items = try NativeOperations.compare(left: leftURL, right: rightURL, byContent: true, cancelled: { flag.isCancelled })
                DispatchQueue.main.async { result?.setRows(items.map { [$0.status, $0.relativePath] }, detail: "\(items.count) comparison records. Read-only comparison; no files changed. Source: \(leftURL.path) | Target: \(rightURL.path)") }
            } catch { DispatchQueue.main.async { result?.message.stringValue = error.localizedDescription } }
        }
    }
    @objc func packFiles() {
        guard requireLocalPane(),requireLocalPane(otherPane) else {return}
        let sources = activePane.selectedURLs, destination = otherPane.directory
        guard !sources.isEmpty else { NSSound.beep(); return }
        prompt(title: "Pack Files", detail: "Create a ZIP archive in \(destination.path)", value: (sources.count == 1 ? sources[0].deletingPathExtension().lastPathComponent : "Archive") + ".zip", action: "Pack") { [weak self] name in
            guard let self else { return }
            do { try self.validArchiveName(name); guard name.lowercased().hasSuffix(".zip") else { throw FileServiceError.invalid("This build creates ZIP archives. Use a .zip file name.") }; let tool = try self.archiveTool(); let archive = destination.appendingPathComponent(name)
                let options=NativeOperations.ZIPOptions(compressionLevel:self.runtimeConfig.zipCompressionLevel,verifyAfterPacking:self.runtimeConfig.zipVerifyAfterPacking,setDateToNewest:self.runtimeConfig.archiveSetDateToNewest)
                self.runOperation("Packing", success: "Created \(name)") { try NativeOperations.pack(sources: sources, archive: archive, tool: tool,options:options) }
            } catch { self.showError(error) }
        }
    }
    @objc func unpackFiles() {
        guard requireLocalPane(),requireLocalPane(otherPane) else {return}
        guard let archive = activePane.currentEntry?.url else { NSSound.beep(); return }
        let destination = otherPane.directory
        prompt(title: "Unpack Files", detail: "Extract the selected archive into a new folder in \(destination.path).", value: archive.deletingPathExtension().lastPathComponent, action: "Unpack") { [weak self] name in
            guard let self else { return }
            do { try self.validArchiveName(name); let tool = try self.archiveTool(); let folder = destination.appendingPathComponent(name)
                self.unpackArchive(archive,to:folder,tool:tool)
            } catch { self.showError(error) }
        }
    }
    @objc func checksumFiles() {
        guard requireLocalPane() else {return}
        let sources = activePane.selectedURLs
        guard !sources.isEmpty else { NSSound.beep(); return }
        let result = ResultsWindow(title: "SHA-256 Checksums", columns: [("File", 280), ("SHA-256 / error", 490)])
        result.message.stringValue = "Calculating checksums…"; result.display()
        DispatchQueue.global(qos: .userInitiated).async { [weak result] in
            let rows = sources.map { url -> [String] in
                do { return [url.path, try NativeOperations.sha256(url)] }
                catch { return [url.path, error.localizedDescription] }
            }
            DispatchQueue.main.async { result?.setRows(rows, detail: "SHA-256 calculated for selected regular files. Directories or unreadable items report an error. This view does not yet write or verify checksum manifests.") }
        }
    }
}

extension CommanderController {
    @objc func createChecksums() {
        guard requireLocalPane() else {return}
        let urls = activePane.selectedURLs, directory = activePane.directory
        guard !urls.isEmpty else { return }
        prompt(title: "Create checksum file", detail: "Choose extension: .sha256, .sha1, .md5 or .sfv", value: "checksums.sha256", action: "Create") { [weak self] name in
            guard let self else { return }
            do {
                try self.validArchiveName(name)
                guard let algorithm = ChecksumAlgorithm(rawValue: URL(fileURLWithPath:name).pathExtension.lowercased()) else { throw FileServiceError.invalid("Use .sha256, .sha1, .md5 or .sfv") }
                self.runOperation("Calculating checksums", success:"Checksum file created") { try ChecksumService.create(sources:urls,destination:directory.appendingPathComponent(name),algorithm:algorithm) }
            } catch { self.showError(error) }
        }
    }
    @objc func verifyChecksums() {
        guard requireLocalPane() else {return}
        guard let manifest = activePane.currentEntry?.url, let algorithm = ChecksumAlgorithm(rawValue:manifest.pathExtension.lowercased()) else { showMessage("Verify checksums","Select a .sha256, .sha1, .md5 or .sfv file."); return }
        let result = ResultsWindow(title:"Verify Checksums",columns:[("File",550),("Result",200)]); result.message.stringValue = "Verifying…"; result.display()
        DispatchQueue.global(qos:.userInitiated).async { [weak result] in
            do { let records = try ChecksumService.verify(manifest:manifest,algorithm:algorithm); DispatchQueue.main.async { result?.setRows(records.map { [$0.0,$0.1] },detail:"\(records.filter { $0.1 == "OK" }.count) of \(records.count) verified") } }
            catch { DispatchQueue.main.async { result?.message.stringValue = error.localizedDescription } }
        }
    }
}
