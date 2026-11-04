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

/// Labels describe native dispatch, while defaults are verified against Main.handleKey,
/// performFunction and KeyboardFeatures.handleExtendedKey. This is not an inventory
/// of every context-sensitive original Windows shortcut.
enum KeybindingActions {
    static let aliases:[String:String] = ["cm_listinternalonly":"cm_list","cm_listonly":"cm_list","cm_editexistingfile":"cm_edit","cm_copyotherpanel":"cm_copy","cm_copytoarchive":"cm_packfiles","cm_ftpnew":"cm_ftpconnect","cm_quit":"cm_exit","cm_versioninfo":"cm_about"]
    static func canonical(_ command:String)->String {aliases[command.lowercased()] ?? command.lowercased()}
    static let titles:[String:String] = [
        "cm_switchdarkmode":"Toggle dark appearance","cm_enabledarkmode":"Use dark appearance","cm_disabledarkmode":"Use light appearance",
        "cm_srccustomviewmenu":"Choose custom columns","cm_srcviewmodelist":"Choose view mode","cm_customcolumnconfig":"Configure custom columns","cm_customcolumndlg":"Edit custom columns","cm_configviewmodes":"Configure view modes","cm_configviewmodeswitch":"Configure automatic view switching","cm_toggleautoviewmodeswitch":"Toggle automatic view switching",
        "cm_about":"About this app","cm_buttonconfig":"Configure button bar","cm_clearall":"Clear selection","cm_closealltabs":"Close other tabs","cm_closecurrenttab":"Close current tab",
        "cm_combine":"Combine files","cm_comparedirs":"Compare directories","cm_comparefilesbycontent":"Compare file contents","cm_config":"Open settings","cm_configchangeinifiles":"Edit configuration file",
        "cm_configsavepos":"Save window position","cm_configsavesettings":"Save settings","cm_copy":"Copy files","cm_copyfiledetailstoclip":"Copy file details","cm_copyfpfiledetailstoclip":"Copy file details with paths",
        "cm_copyfullnamestoclip":"Copy full paths","cm_copynamestoclip":"Copy file names","cm_copytoclipboard":"Copy files to clipboard",
        "cm_crccheck":"Verify checksums","cm_crccreate":"Create checksums","cm_delete":"Delete files","cm_directoryhotlist":"Open favorite folders","cm_edit":"Edit file",
        "cm_editnewfile":"Create text file","cm_exchange":"Swap panes","cm_exchangeselection":"Invert selection","cm_exit":"Quit app",
        "cm_filesync":"Synchronize directories","cm_ftpconnect":"Connect to FTP","cm_ftpdisconnect":"Disconnect FTP","cm_ftphiddenfiles":"Show hidden FTP files","cm_getfilespace":"Calculate folder sizes","cm_gotonextdir":"Next directory","cm_gotopreviousdir":"Previous directory","cm_keyboard":"Keyboard help","cm_list":"View file",
        "cm_loadselectionfromfile":"Load selection from file","cm_matchsrc":"Show current folder in opposite pane","cm_mkdir":"Create folder","cm_multirenamefiles":"Rename multiple files","cm_opendesktop":"Open Desktop","cm_opennewtab":"New tab","cm_packfiles":"Pack files","cm_pastefromclipboard":"Paste files",
        "cm_renamesinglefile":"Rename file","cm_renmov":"Move files","cm_rereadsource":"Refresh pane","cm_restoreselection":"Restore selection","cm_saveselection":"Save selection","cm_saveselectiontofile":"Save selection to file","cm_searchfor":"Search files","cm_selectall":"Select all files","cm_selectcurrentextension":"Select matching extension",
        "cm_separatetree1":"Show one separate tree","cm_separatetree2":"Show two separate trees","cm_separatetreeoff":"Hide separate trees","cm_showonlyselected":"Show selected files only","cm_shrinkselection":"Unselect by pattern","cm_split":"Split file","cm_spreadselection":"Select by pattern",
        "cm_srcallfiles":"Show all files","cm_srcbydatetime":"Sort by date","cm_srcbyext":"Sort by extension","cm_srcbyname":"Sort by name","cm_srcbysize":"Sort by size","cm_srcexecs":"Show executable files","cm_srclong":"Full view","cm_srcnegorder":"Reverse sort order","cm_srcquickview":"Quick view","cm_srcshort":"Brief view","cm_srcthumbs":"Thumbnail view","cm_srctree":"Tree view","cm_srcunsorted":"Unsorted view","cm_srcuserdef":"Choose file mask","cm_srcuserspec":"Use last file mask","cm_testarchive":"Test archive","cm_unpackfiles":"Unpack files","cm_verticalpanels":"Stack panes vertically","cm_visithomepage":"Open Total Commander website"
    ]
    static func title(_ command:String)->String {
        let command=canonical(command)
        if let title=titles[command] {return title}
        if command.hasPrefix("cm_srccustomview"),let number=Int(command.dropFirst("cm_srccustomview".count)){return "Custom columns \(number)"}
        if command.hasPrefix("cm_srcviewmode"),let number=Int(command.dropFirst("cm_srcviewmode".count)){return number==0 ? "Default view mode":"View mode \(number)"}
        return command
    }
    static let defaults:[String:[String]] = [
        "cm_rereadsource":["F2","Ctrl+R"],"cm_list":["F3","Shift+F3"],"cm_edit":["F4"],"cm_copy":["F5"],"cm_renmov":["F6"],"cm_mkdir":["F7"],"cm_delete":["F8","Delete"],
        "cm_searchfor":["Alt+F7"],"cm_packfiles":["Alt+F5"],"cm_unpackfiles":["Alt+F6","Alt+F9"],"cm_exit":["Alt+F4"],"cm_gotopreviousdir":["Alt+Left"],"cm_gotonextdir":["Alt+Right"],
        "cm_multirenamefiles":["Ctrl+M"],"cm_exchange":["Ctrl+U"],"cm_opennewtab":["Ctrl+T"],"cm_closecurrenttab":["Ctrl+W"],"cm_closealltabs":["Ctrl+Shift+W"],"cm_selectall":["Ctrl+A","Ctrl+Plus"],"cm_clearall":["Ctrl+Minus"],"cm_directoryhotlist":["Ctrl+D"],"cm_srccustomviewmenu":["Shift+F1"],"cm_renamesinglefile":["Shift+F6"],
        "cm_srcshort":["Ctrl+F1"],"cm_srclong":["Ctrl+F2"],"cm_srcbyname":["Ctrl+F3"],"cm_srcbyext":["Ctrl+F4"],"cm_srcbydatetime":["Ctrl+F5"],"cm_srcbysize":["Ctrl+F6"],"cm_srcunsorted":["Ctrl+F7"],"cm_srctree":["Ctrl+F8"],"cm_srcexecs":["Ctrl+F11"],"cm_srcuserdef":["Ctrl+F12"],"cm_srcallfiles":["Ctrl+F10"],"cm_srcquickview":["Ctrl+Q"],"cm_ftpconnect":["Ctrl+F","Ctrl+N"],"cm_getfilespace":["Ctrl+L"],"cm_copytoclipboard":["Ctrl+C"],"cm_pastefromclipboard":["Ctrl+V"],"cm_srcthumbs":["Ctrl+Shift+F1"],"cm_ftpdisconnect":["Ctrl+Shift+F"],"cm_editnewfile":["Shift+F4"],"cm_comparedirs":["Shift+F2"]
    ]
    // Context-only bindings do not have an equivalent allowlisted command; still
    // identify them when a proposed override would replace their behavior.
    static let contextualDefaults:[String:String] = ["F1":"Help","F9":"Show menu","F10":"Show menu","Tab":"Switch pane","Return":"Open item or run command","Backspace":"Parent folder","Space":"Mark file","Insert":"Mark file","Escape":"Clear filter and selection","Home":"First item","End":"Last item","Ctrl+Tab":"Next tab","Ctrl+Shift+Tab":"Previous tab","Ctrl+Up":"Open item in new tab","Ctrl+Shift+Up":"Open item in opposite new tab","Ctrl+Left":"Open in left pane","Ctrl+Right":"Open in right pane","Ctrl+Shift+T":"New background tab","Shift+F5":"Copy in same folder","Shift+F7":"Create folder in opposite pane","Shift+F10":"Context menu","Alt+Return":"File properties","Ctrl+S":"Quick filter","Alt+Down":"Directory history","Ctrl+Down":"Command history","Ctrl+Shift+U":"Swap tabs between panes","Ctrl+Shift+A":"List tabs","Ctrl+Shift+F8":"Cycle separate trees","Ctrl+Pageup":"Parent folder","Ctrl+Pagedown":"Open item","Ctrl+Return":"Append file name to command line","Ctrl+Shift+Return":"Append full path to command line","Ctrl+P":"Append current path to command line","Ctrl+I":"Open opposite folder","Ctrl+Backslash":"Root folder","Alt+F1":"Choose left folder","Alt+F2":"Choose right folder","Alt+F8":"Command history","Shift+Escape":"Minimize window"]
    static func isNumberedProfile(_ command:String)->Bool {
        for prefix in ["cm_srccustomview","cm_srcviewmode"] where command.hasPrefix(prefix) {if let number=Int(command.dropFirst(prefix.count)){return number != 0}}
        return false
    }
    static var commands:[String] {Array(Set(ShortcutSettings.supportedCommands.map(canonical))).sorted{title($0).localizedStandardCompare(title($1)) == .orderedAscending}}
    static func defaultCommand(for chord:ShortcutChord)->String? {defaults.first{$0.value.contains{(try? ShortcutChord.parse($0))==chord}}?.key}
    static func defaultTitle(for chord:ShortcutChord)->String? {
        if let command=defaultCommand(for:chord){return title(command)}
        return contextualDefaults.first{(try? ShortcutChord.parse($0.key))==chord}?.value
    }
}

/// Draft-only editor: Apply/OK is owned by Preferences, never by this view.
final class KeybindingsEditor:NSStackView,NSTableViewDataSource,NSTableViewDelegate,NSSearchFieldDelegate {
    struct Row {var chord:ShortcutChord;var command:String}
    private(set) var bindings:[Row]=[]
    private var initialError:Error?
    let table=NSTableView(),keyField=NSTextField(string:""),commandField=NSComboBox(),search=NSSearchField(),aliasField=NSTextField(string:"")
    let feedback=NSTextField(wrappingLabelWithString:"Choose an action, then record a shortcut.")
    let capture=ShortcutCaptureView(frame:.zero),advanced=NSStackView()
    let replaceButton=NSButton(title:"Replace shortcut",target:nil,action:nil)
    let recordButton=NSButton(title:"Record shortcut",target:nil,action:nil),restoreButton=NSButton(title:"Restore default",target:nil,action:nil)
    private(set) var visibleCommands:[String]=KeybindingActions.commands
    private(set) var selectedCommand:String?
    private var pendingConflict:(ShortcutChord,String)?
    private var refreshing=false
    init(shortcuts:String,aliases:String="") {
        super.init(frame:.zero);orientation = .vertical;alignment = .leading;spacing=8
        do {bindings=try ShortcutSettings.parse(shortcuts:shortcuts,aliases:"").bindings.map{Row(chord:$0.key,command:$0.value)}.sorted{$0.chord.settingsLabel<$1.chord.settingsLabel}}catch{initialError=error}
        aliasField.stringValue=aliases;identifier=NSUserInterfaceItemIdentifier("configuration.keybindings")
        search.placeholderString="Search actions or shortcuts";search.delegate=self;search.setAccessibilityLabel("Search keybinding actions");addArrangedSubview(search);search.widthAnchor.constraint(equalToConstant:520).isActive=true
        for (id,title,width) in [("action","Action",265.0),("key","Shortcut",245.0)] {let c=NSTableColumn(identifier:.init(id));c.title=title;c.width=width;table.addTableColumn(c)}
        table.delegate=self;table.dataSource=self;table.allowsEmptySelection=true;table.allowsMultipleSelection=false;table.rowHeight=25
        let scroll=NSScrollView();scroll.documentView=table;scroll.hasVerticalScroller=true;scroll.borderType = .bezelBorder;addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalToConstant:520).isActive=true;scroll.heightAnchor.constraint(equalToConstant:245).isActive=true
        recordButton.target=self;recordButton.action=#selector(startRecording);restoreButton.target=self;restoreButton.action=#selector(restoreDefault)
        let buttons=NSStackView(views:[recordButton,restoreButton]);buttons.spacing=8;addArrangedSubview(buttons)
        addArrangedSubview(capture);capture.widthAnchor.constraint(equalToConstant:520).isActive=true;capture.heightAnchor.constraint(equalToConstant:30).isActive=true;capture.isHidden=true
        capture.captured={ [weak self] chord in guard let self else{return};self.keyField.stringValue=chord.settingsLabel;self.finishRecording();self.assign() }
        capture.cancelled={ [weak self] in self?.finishRecording() }
        feedback.widthAnchor.constraint(equalToConstant:520).isActive=true;feedback.font = .systemFont(ofSize:11);addArrangedSubview(feedback)
        replaceButton.target=self;replaceButton.action=#selector(replaceConflict);replaceButton.isHidden=true;addArrangedSubview(replaceButton)
        let disclosure=NSButton(checkboxWithTitle:"Advanced",target:self,action:#selector(toggleAdvanced));addArrangedSubview(disclosure)
        advanced.orientation = .vertical;advanced.alignment = .leading;advanced.spacing=6;advanced.isHidden=true;addArrangedSubview(advanced)
        keyField.placeholderString="Ctrl+Shift+B";keyField.setAccessibilityLabel("Shortcut")
        commandField.completes=true;commandField.hasVerticalScroller=true;commandField.numberOfVisibleItems=12;commandField.setAccessibilityLabel("Shortcut command");commandField.addItems(withObjectValues:ShortcutSettings.supportedCommands.sorted())
        func row(_ title:String,_ view:NSView){let label=NSTextField(labelWithString:title);label.widthAnchor.constraint(equalToConstant:90).isActive=true;let row=NSStackView(views:[label,view]);row.spacing=8;view.widthAnchor.constraint(equalToConstant:410).isActive=true;advanced.addArrangedSubview(row)}
        row("Shortcut",keyField);row("Command ID",commandField);row("Aliases",aliasField);aliasField.placeholderString="full=cm_SrcLong";aliasField.setAccessibilityLabel("Command aliases")
        let advancedButtons=NSStackView();advancedButtons.spacing=8
        for (title,selector) in [("Assign",#selector(assign)),("Remove shortcut",#selector(remove)),("Reset all",#selector(resetOverrides))] {advancedButtons.addArrangedSubview(NSButton(title:title,target:self,action:selector))};advanced.addArrangedSubview(advancedButtons)
        let note=NSTextField(wrappingLabelWithString:"* Custom shortcut. Defaults stay active unless reassigned. Applies in file panes; macOS may reserve some keys.");note.font = .systemFont(ofSize:11);note.textColor = .secondaryLabelColor;note.widthAnchor.constraint(equalToConstant:520).isActive=true;addArrangedSubview(note)
        filterActions();if let initialError {show(initialError)}
    }
    required init?(coder:NSCoder){fatalError()}
    func numberOfRows(in tableView:NSTableView)->Int {visibleCommands.count}
    func shortcutSummary(for command:String)->String {
        let action=KeybindingActions.canonical(command)
        let overrides=bindings.filter{KeybindingActions.canonical($0.command)==action}.map{$0.chord.settingsLabel}
        let defaults=(KeybindingActions.defaults[action] ?? []).filter{label in guard let chord=try? ShortcutChord.parse(label) else{return false};return !bindings.contains{$0.chord==chord}}
        let all=defaults.map{($0.hasSuffix("Plus") || $0.hasSuffix("Minus")) ? $0+" (keypad)":$0}+overrides.map{$0+" *"}
        return all.isEmpty ? "—":all.joined(separator:", ")
    }
    func tableView(_ tableView:NSTableView,viewFor column:NSTableColumn?,row:Int)->NSView? {
        guard visibleCommands.indices.contains(row) else{return nil};let command=visibleCommands[row]
        let field=NSTextField(labelWithString:column?.identifier.rawValue=="key" ? shortcutSummary(for:command):KeybindingActions.title(command));field.toolTip=column?.identifier.rawValue=="key" ? shortcutSummary(for:command)+"\n* Custom shortcut. Other keys are built-in defaults.":nil;return field
    }
    func tableViewSelectionDidChange(_ notification:Notification) {
        guard !refreshing else{return}
        selectedCommand=visibleCommands.indices.contains(table.selectedRow) ? visibleCommands[table.selectedRow]:nil
        keyField.stringValue="";commandField.stringValue=selectedCommand ?? "";pendingConflict=nil;replaceButton.isHidden=true;capture.isHidden=true
        feedback.textColor = .secondaryLabelColor;feedback.stringValue=selectedCommand.map{"Record an additional shortcut for \(KeybindingActions.title($0))."} ?? "Choose an action, then record a shortcut.";updateButtons()
    }
    func controlTextDidChange(_ notification:Notification) {if notification.object as AnyObject? === search {filterActions()}}
    private func filterActions(){
        let query=search.stringValue.lowercased(),bound=Set(bindings.map{KeybindingActions.canonical($0.command)})
        visibleCommands=KeybindingActions.commands.filter {command in
            if query.isEmpty {return !KeybindingActions.isNumberedProfile(command) || bound.contains(command)}
            return KeybindingActions.title(command).lowercased().contains(query) || command.contains(query) || shortcutSummary(for:command).lowercased().contains(query)
        }
        refreshTable()
    }
    private func refreshTable(){refreshing=true;table.reloadData();if let selectedCommand,let index=visibleCommands.firstIndex(of:selectedCommand){table.selectRowIndexes(IndexSet(integer:index),byExtendingSelection:false)}else{table.deselectAll(nil);selectedCommand=nil};refreshing=false;updateButtons()}
    private func updateButtons(){recordButton.isEnabled=selectedCommand != nil;restoreButton.isEnabled=selectedCommand != nil}
    private func show(_ error:Error){feedback.textColor = .systemRed;feedback.stringValue=error.localizedDescription}
    private func conflict(chord:ShortcutChord,command:String)->String? {
        if let existing=bindings.first(where:{$0.chord==chord}) {return KeybindingActions.canonical(existing.command)==KeybindingActions.canonical(command) ? nil:KeybindingActions.title(existing.command)}
        if KeybindingActions.defaultCommand(for:chord).map(KeybindingActions.canonical)==KeybindingActions.canonical(command){return nil}
        return KeybindingActions.defaultTitle(for:chord)
    }
    @discardableResult func stageBinding(replacingConflict:Bool=false)throws->String {
        let chord=try ShortcutChord.parse(keyField.stringValue),command=commandField.stringValue.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
        guard ShortcutSettings.supportedCommands.contains(command) else{throw ShortcutSettings.failure("Choose a supported action or command ID.")}
        if !replacingConflict,let title=conflict(chord:chord,command:command) {pendingConflict=(chord,command);replaceButton.isHidden=false;throw ShortcutSettings.failure("\(chord.settingsLabel) is used by \(title). Replace it?")}
        // Adding a shortcut never silently removes another shortcut for this action.
        bindings.removeAll{$0.chord==chord}
        if KeybindingActions.defaultCommand(for:chord).map(KeybindingActions.canonical) != KeybindingActions.canonical(command) {bindings.append(Row(chord:chord,command:command))}
        bindings.sort{$0.chord.settingsLabel<$1.chord.settingsLabel};initialError=nil;pendingConflict=nil;replaceButton.isHidden=true;selectedCommand=KeybindingActions.canonical(command);filterActions();return chord.settingsLabel
    }
    @objc func assign(){do{let label=try stageBinding();feedback.textColor = .secondaryLabelColor;feedback.stringValue="\(label) assigned. Apply saves your changes."}catch{show(error)}}
    @objc func replaceConflict(){guard let pendingConflict else{return};keyField.stringValue=pendingConflict.0.settingsLabel;commandField.stringValue=pendingConflict.1;do{_=try stageBinding(replacingConflict:true);feedback.textColor = .secondaryLabelColor;feedback.stringValue="Shortcut replaced. Apply saves your changes."}catch{show(error)}}
    @objc func restoreDefault(){guard let selectedCommand else{return};let defaults=Set((KeybindingActions.defaults[selectedCommand] ?? []).compactMap{try? ShortcutChord.parse($0)});bindings.removeAll{KeybindingActions.canonical($0.command)==selectedCommand || defaults.contains($0.chord)};keyField.stringValue="";pendingConflict=nil;replaceButton.isHidden=true;filterActions();feedback.textColor = .secondaryLabelColor;feedback.stringValue="Default shortcuts restored. Apply saves your changes."}
    @objc func remove(){guard let chord=try? ShortcutChord.parse(keyField.stringValue) else{return};bindings.removeAll{$0.chord==chord};keyField.stringValue="";pendingConflict=nil;replaceButton.isHidden=true;filterActions();feedback.textColor = .secondaryLabelColor;feedback.stringValue="Custom shortcut removed. Apply saves your changes."}
    @objc func resetOverrides(){bindings=[];initialError=nil;pendingConflict=nil;replaceButton.isHidden=true;keyField.stringValue="";filterActions();feedback.textColor = .secondaryLabelColor;feedback.stringValue="Default shortcuts restored for all actions. Apply saves your changes."}
    @objc func startRecording(){guard let selectedCommand else{return};commandField.stringValue=selectedCommand;capture.isHidden=false;window?.makeFirstResponder(capture)}
    private func finishRecording(){capture.isHidden=true;window?.makeFirstResponder(table)}
    @objc func toggleAdvanced(_ sender:NSButton){advanced.isHidden=sender.state != .on}
    func serializedBindings()throws->String {
        if let initialError{throw initialError}
        if pendingConflict != nil {throw ShortcutSettings.failure("Resolve the shortcut conflict before applying, or select another action to cancel it.")}
        if !keyField.stringValue.isEmpty {
            let chord=try ShortcutChord.parse(keyField.stringValue),command=commandField.stringValue.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
            let unchanged=bindings.contains{$0.chord==chord && $0.command==command} || (KeybindingActions.defaultCommand(for:chord)==command && !bindings.contains{$0.chord==chord})
            if !unchanged {_=try stageBinding()}
        }
        let text=bindings.map{$0.chord.settingsLabel+"="+$0.command}.joined(separator:"; ");guard text.utf8.count<=16384 else{throw ShortcutSettings.failure("Shortcut definitions exceed the 16,384-byte configuration limit.")};try ShortcutSettings.validate(shortcuts:text,aliases:aliasField.stringValue);return text
    }
}
