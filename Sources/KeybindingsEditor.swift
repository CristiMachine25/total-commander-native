import AppKit

extension ShortcutChord {
    var settingsLabel:String {
        var parts:[String]=[]
        for (flag,name) in [(Modifiers.control,"Ctrl"),(.option,"Alt"),(.shift,"Shift"),(.command,"Cmd")] where modifiers.contains(flag) {parts.append(name)}
        parts.append(key.count==1 || key.hasPrefix("F") ? key:key.capitalized)
        return parts.joined(separator:"+")
    }
}

final class ShortcutCaptureView:NSView {
    var captured:((ShortcutChord)->Void)?
    var cancelled:(()->Void)?
    let label=NSTextField(labelWithString:"Press a shortcut… (Esc cancels)")
    override var acceptsFirstResponder:Bool {true}
    override init(frame:NSRect){super.init(frame:frame);addSubview(label);label.translatesAutoresizingMaskIntoConstraints=false;NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo:leadingAnchor,constant:8),label.centerYAnchor.constraint(equalTo:centerYAnchor)]);setAccessibilityLabel("Record shortcut")}
    required init?(coder:NSCoder){fatalError()}
    override func performKeyEquivalent(with event:NSEvent)->Bool {
        guard window?.firstResponder === self else{return false}
        keyDown(with:event);return true
    }
    override func keyDown(with event:NSEvent) {
        let modifiers=event.modifierFlags.intersection([.control,.option,.shift,.command])
        if event.keyCode==53,modifiers.isEmpty {cancelled?();return}
        if let chord=ShortcutChord(event:event) {captured?(chord)} else {NSSound.beep()}
    }
}

/// Edits the existing shortcut string as a validated draft; never saves preferences directly.
final class KeybindingsEditor:NSStackView,NSTableViewDataSource,NSTableViewDelegate,NSSearchFieldDelegate {
    struct Row {var chord:ShortcutChord;var command:String}
    private(set) var bindings:[Row]=[]
    private var initialError:Error?
    let table=NSTableView(),keyField=NSTextField(string:""),commandField=NSComboBox(),search=NSSearchField()
    let feedback=NSTextField(wrappingLabelWithString:"Choose a shortcut and command. Assign or Apply stages your edit; removing an override restores the built-in shortcut.")
    let capture=ShortcutCaptureView(frame:.zero)
    private var editingChord:ShortcutChord?
    init(shortcuts:String) {
        super.init(frame:.zero);orientation = .vertical;alignment = .leading;spacing=8
        do {bindings=try ShortcutSettings.parse(shortcuts:shortcuts,aliases:"").bindings.map{Row(chord:$0.key,command:$0.value)}.sorted{$0.chord.settingsLabel<$1.chord.settingsLabel}}catch{initialError=error}
        identifier=NSUserInterfaceItemIdentifier("configuration.keybindings")
        for (id,title,width) in [("key","Shortcut",170.0),("command","Command",330.0)] {let c=NSTableColumn(identifier:.init(id));c.title=title;c.width=width;table.addTableColumn(c)}
        table.delegate=self;table.dataSource=self;table.allowsEmptySelection=true;table.allowsMultipleSelection=false;table.rowHeight=23
        let scroll=NSScrollView();scroll.documentView=table;scroll.hasVerticalScroller=true;scroll.borderType = .bezelBorder;addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalToConstant:520).isActive=true;scroll.heightAnchor.constraint(equalToConstant:170).isActive=true
        search.placeholderString="Search native commands";search.delegate=self;search.setAccessibilityLabel("Search keybinding commands");addArrangedSubview(search);search.widthAnchor.constraint(equalToConstant:520).isActive=true
        keyField.placeholderString="Ctrl+Shift+B";keyField.setAccessibilityLabel("Shortcut")
        commandField.completes=true;commandField.hasVerticalScroller=true;commandField.numberOfVisibleItems=12;commandField.setAccessibilityLabel("Shortcut command");filterCommands()
        func row(_ title:String,_ view:NSView){let label=NSTextField(labelWithString:title);label.widthAnchor.constraint(equalToConstant:90).isActive=true;let row=NSStackView(views:[label,view]);row.spacing=8;view.widthAnchor.constraint(equalToConstant:410).isActive=true;addArrangedSubview(row)}
        row("Shortcut",keyField);row("Command",commandField)
        let buttons=NSStackView();buttons.spacing=8
        for (title,selector) in [("New",#selector(newBinding)),("Assign",#selector(assign)),("Remove",#selector(remove)),("Record shortcut",#selector(startRecording)),("Reset overrides",#selector(resetOverrides))] {buttons.addArrangedSubview(NSButton(title:title,target:self,action:selector))}
        addArrangedSubview(buttons);addArrangedSubview(capture);capture.widthAnchor.constraint(equalToConstant:520).isActive=true;capture.heightAnchor.constraint(equalToConstant:30).isActive=true;capture.isHidden=true
        capture.captured={ [weak self] chord in guard let self else{return};self.keyField.stringValue=chord.settingsLabel;self.finishRecording() }
        capture.cancelled={ [weak self] in self?.finishRecording() }
        feedback.widthAnchor.constraint(equalToConstant:520).isActive=true;addArrangedSubview(feedback)
        let builtins=NSTextField(wrappingLabelWithString:"Common built-ins: F3 View · F4 Edit · F5 Copy · F6 Move · F7 New folder · F8 Delete · Ctrl+F1 Brief · Ctrl+F2 Full · Shift+F1 Custom columns · Ctrl+Tab Next tab. Overrides apply while a file pane has focus. macOS may reserve some combinations.")
        builtins.font = .systemFont(ofSize:11);builtins.widthAnchor.constraint(equalToConstant:520).isActive=true;addArrangedSubview(builtins)
        if let initialError {show(initialError)}
    }
    required init?(coder:NSCoder){fatalError()}
    func numberOfRows(in tableView:NSTableView)->Int {bindings.count}
    func tableView(_ tableView:NSTableView,viewFor column:NSTableColumn?,row:Int)->NSView? {guard bindings.indices.contains(row) else{return nil};return NSTextField(labelWithString:column?.identifier.rawValue=="key" ? bindings[row].chord.settingsLabel:bindings[row].command)}
    func tableViewSelectionDidChange(_ notification:Notification) {guard bindings.indices.contains(table.selectedRow) else{editingChord=nil;return};let value=bindings[table.selectedRow];editingChord=value.chord;keyField.stringValue=value.chord.settingsLabel;commandField.stringValue=value.command}
    func controlTextDidChange(_ notification:Notification) {if notification.object as AnyObject? === search {filterCommands()}}
    private func filterCommands(){let value=commandField.stringValue,query=search.stringValue.lowercased();commandField.removeAllItems();commandField.addItems(withObjectValues:ShortcutSettings.supportedCommands.sorted().filter{query.isEmpty || $0.contains(query)});commandField.stringValue=value}
    private func show(_ error:Error){feedback.textColor = .systemRed;feedback.stringValue=error.localizedDescription}
    @discardableResult func stageBinding()throws->String {
        let chord=try ShortcutChord.parse(keyField.stringValue),command=commandField.stringValue.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
        guard ShortcutSettings.supportedCommands.contains(command) else{throw ShortcutSettings.failure("Choose a supported native command.")}
        if let index=bindings.firstIndex(where:{$0.chord==chord}),bindings[index].chord != editingChord {throw ShortcutSettings.failure("\(chord.settingsLabel) is already assigned to \(bindings[index].command). Select that row to replace it.")}
        if let editingChord,let index=bindings.firstIndex(where:{$0.chord==editingChord}) {bindings[index]=Row(chord:chord,command:command)}else{bindings.append(Row(chord:chord,command:command))}
        bindings.sort{$0.chord.settingsLabel<$1.chord.settingsLabel};initialError=nil;editingChord=chord;table.reloadData()
        if let index=bindings.firstIndex(where:{$0.chord==chord}) {table.selectRowIndexes(IndexSet(integer:index),byExtendingSelection:false)}
        return chord.settingsLabel
    }
    @objc func newBinding(){editingChord=nil;table.deselectAll(nil);keyField.stringValue="";commandField.stringValue="";feedback.textColor = .secondaryLabelColor;feedback.stringValue="Enter a new shortcut and command, then Assign or Apply.";window?.makeFirstResponder(keyField)}
    @objc func assign(){do{let label=try stageBinding();feedback.textColor = .secondaryLabelColor;feedback.stringValue="Staged \(label). Apply saves this override."}catch{show(error)}}
    @objc func remove(){guard bindings.indices.contains(table.selectedRow) else{return};bindings.remove(at:table.selectedRow);editingChord=nil;table.reloadData();keyField.stringValue="";commandField.stringValue="";feedback.textColor = .secondaryLabelColor;feedback.stringValue="Override removed from draft. Apply restores its built-in behavior."}
    @objc func resetOverrides(){bindings=[];initialError=nil;editingChord=nil;table.reloadData();keyField.stringValue="";commandField.stringValue="";feedback.textColor = .secondaryLabelColor;feedback.stringValue="All overrides cleared from draft. Cancel keeps your saved bindings."}
    @objc func startRecording(){capture.isHidden=false;window?.makeFirstResponder(capture)}
    private func finishRecording(){capture.isHidden=true;window?.makeFirstResponder(keyField)}
    func serializedBindings()throws->String {
        if let initialError{throw initialError}
        if !keyField.stringValue.isEmpty || !commandField.stringValue.isEmpty {
            let chord=try ShortcutChord.parse(keyField.stringValue),command=commandField.stringValue.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
            let unchanged=editingChord==chord && bindings.contains{$0.chord==chord && $0.command==command}
            if !unchanged {_=try stageBinding()}
        }
        let text=bindings.map{$0.chord.settingsLabel+"="+$0.command}.joined(separator:"; ");guard text.count<=16384 else{throw ShortcutSettings.failure("Shortcut definitions exceed the 16,384-character configuration limit.")};try ShortcutSettings.validate(shortcuts:text,aliases:"");return text}
}
