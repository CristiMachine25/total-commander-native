import AppKit

final class ButtonBarEditor:NSWindowController,NSWindowDelegate,NSTableViewDataSource,NSTableViewDelegate {
    private weak var commander:CommanderController?
    private var baseline:CommanderButtonBar
    var draft:CommanderButtonBar
    let table=NSTableView(),titleField=NSTextField(),commandField=NSTextField(),parametersField=NSTextField(),directoryField=NSTextField(),iconField=NSTextField()
    private let chooser=NSPopUpButton(),size=NSPopUpButton(),labels=NSButton(checkboxWithTitle:"Show text labels",target:nil,action:nil)
    private let note=NSTextField(wrappingLabelWithString:"")
    private var editingRow = -1
    private var loading=false
    init(_ commander:CommanderController) {
        self.commander=commander;baseline=commander.barConfiguration;draft=baseline
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:820,height:580),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.title="Change button bar";window.isReleasedWhenClosed=false;window.minSize=NSSize(width:760,height:560)
        super.init(window:window);window.delegate=self
        let column=NSTableColumn(identifier:NSUserInterfaceItemIdentifier("button"));column.title="Buttons";column.width=235;table.addTableColumn(column);table.headerView=nil;table.delegate=self;table.dataSource=self;table.allowsEmptySelection=false
        let scroll=NSScrollView();scroll.documentView=table;scroll.hasVerticalScroller=true;scroll.widthAnchor.constraint(equalToConstant:240).isActive=true
        func button(_ text:String,_ action:Selector)->NSButton{NSButton(title:text,target:self,action:action)}
        let tools=NSStackView(views:[button("Add",#selector(add)),button("Separator",#selector(addSeparator)),button("Delete",#selector(remove))]);tools.spacing=4
        let order=NSStackView(views:[button("Move Up",#selector(up)),button("Move Down",#selector(down))]);order.spacing=4
        let list=NSStackView(views:[scroll,tools,order]);list.orientation = .vertical;list.alignment = .leading;list.spacing=8
        for field in [titleField,commandField,parametersField,directoryField,iconField] {field.font = .systemFont(ofSize:13);field.lineBreakMode = .byTruncatingMiddle}
        let form=NSStackView();form.orientation = .vertical;form.alignment = .leading;form.spacing=8
        func row(_ name:String,_ field:NSTextField,_ action:Selector?=nil) {
            let label=NSTextField(labelWithString:name);form.addArrangedSubview(label)
            field.setAccessibilityLabel(name)
            var views:[NSView]=[field];if let action {views.append(button("Browse…",action))}
            let stack=NSStackView(views:views);stack.spacing=6;form.addArrangedSubview(stack);stack.widthAnchor.constraint(equalTo:form.widthAnchor).isActive=true
        }
        row("Tooltip / label",titleField)
        chooser.addItem(withTitle:"Choose internal command…")
        let catalog=try? ReferenceMenuCatalog.load()
        var commands=Set(CommanderButtonBar.defaultItems.map(\.command)+CommanderButtonBar.extraCommands)
        if let catalog {for definition in catalog.commandsBySymbol.values where ReferenceCommandRouting.isSupported(definition.id){commands.insert(definition.symbol)}}
        for command in commands.sorted() {chooser.addItem(withTitle:command)}
        chooser.target=self;chooser.action=#selector(chooseCommand);form.addArrangedSubview(chooser)
        row("Command",commandField,#selector(browseCommand));row("Parameters",parametersField);row("Start path",directoryField,#selector(browseDirectory));row("Icon file",iconField,#selector(browseIcon))
        let help=NSTextField(wrappingLabelWithString:"Use a cm_ command or a Mac application, program or folder. Quote parameters containing spaces. Parameters are literal: Windows % macros and shell expansions are not supported.");help.font = .systemFont(ofSize:11);help.textColor = .secondaryLabelColor;form.addArrangedSubview(help);help.widthAnchor.constraint(equalTo:form.widthAnchor).isActive=true
        form.addArrangedSubview(NSView())
        let main=NSStackView(views:[list,form]);main.orientation = .horizontal;main.alignment = .top;main.spacing=18
        list.heightAnchor.constraint(equalTo:main.heightAnchor).isActive=true
        form.heightAnchor.constraint(equalTo:main.heightAnchor).isActive=true
        size.addItems(withTitles:["16","22","24","32","48"]);size.selectItem(withTitle:String(draft.iconSize));labels.state=draft.showLabels ? .on : .off
        let settings=NSStackView(views:[NSTextField(labelWithString:"Icon size:"),size,labels,NSView(),button("Restore Defaults",#selector(reset))]);settings.spacing=10
        let cancel=button("Cancel",#selector(cancel));cancel.keyEquivalent="\u{1b}"
        let ok=button("OK",#selector(ok));ok.keyEquivalent="\r"
        let bottom=NSStackView(views:[NSView(),cancel,button("Apply",#selector(apply)),ok]);bottom.spacing=8
        note.font = .systemFont(ofSize:11);note.textColor = .secondaryLabelColor
        let root=NSStackView(views:[main,settings,note,bottom]);root.orientation = .vertical;root.alignment = .leading;root.spacing=12
        window.contentView=root;root.edgeInsets=NSEdgeInsets(top:16,left:16,bottom:16,right:16)
        for view in [main,settings,note,bottom] {view.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-32).isActive=true}
        reload(select:0)
    }
    required init?(coder:NSCoder){fatalError()}
    func numberOfRows(in tableView:NSTableView)->Int{draft.items.count}
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView? {
        let item=draft.items[row];return NSTextField(labelWithString:item.separator ? "──────── Separator" : item.title)
    }
    func tableViewSelectionDidChange(_ notification:Notification) {
        guard !loading else{return};capture();editingRow=table.selectedRow;loadFields()
    }
    private func capture() {
        guard draft.items.indices.contains(editingRow),!draft.items[editingRow].separator else{return}
        draft.items[editingRow].title=titleField.stringValue;draft.items[editingRow].command=commandField.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        draft.items[editingRow].parameters=parametersField.stringValue;draft.items[editingRow].directory=directoryField.stringValue;draft.items[editingRow].icon=iconField.stringValue
    }
    private func loadFields() {
        let item=draft.items.indices.contains(editingRow) ? draft.items[editingRow] : CommanderBarItem(title:"",command:"",separator:true)
        for field in [titleField,commandField,parametersField,directoryField,iconField] {field.isEnabled = !item.separator}
        chooser.isEnabled = !item.separator
        titleField.stringValue=item.title;commandField.stringValue=item.command;parametersField.stringValue=item.parameters;directoryField.stringValue=item.directory;iconField.stringValue=item.icon
        chooser.selectItem(at:0)
    }
    private func reload(select:Int) {
        loading=true;table.reloadData();editingRow=draft.items.isEmpty ? -1 : max(0,min(select,draft.items.count-1))
        if editingRow>=0{table.selectRowIndexes(IndexSet(integer:editingRow),byExtendingSelection:false);table.scrollRowToVisible(editingRow)}
        loading=false;loadFields()
    }
    @objc func add(){capture();let index=max(0,editingRow+1);draft.items.insert(.init(title:"New button",command:"cm_RereadSource"),at:index);reload(select:index)}
    @objc func addSeparator(){capture();let index=max(0,editingRow+1);draft.items.insert(.init(title:"",command:"",separator:true),at:index);reload(select:index)}
    @objc func remove(){guard draft.items.indices.contains(editingRow) else{return};draft.items.remove(at:editingRow);reload(select:editingRow)}
    private func move(_ offset:Int){capture();let target=editingRow+offset;guard draft.items.indices.contains(editingRow),draft.items.indices.contains(target) else{return};draft.items.swapAt(editingRow,target);reload(select:target)}
    @objc func up(){move(-1)}
    @objc func down(){move(1)}
    @objc private func chooseCommand(){guard chooser.indexOfSelectedItem>0 else{return};commandField.stringValue=chooser.titleOfSelectedItem ?? ""}
    @objc private func reset(){draft=CommanderButtonBar();size.selectItem(withTitle:"22");labels.state = .off;reload(select:0);note.stringValue="Defaults staged. Choose Apply or OK to save."}
    private func browse(_ field:NSTextField,directories:Bool,files:Bool) {
        guard field.isEnabled,let window else{return}
        let panel=NSOpenPanel();panel.canChooseDirectories=directories;panel.canChooseFiles=files;panel.allowsMultipleSelection=false
        panel.beginSheetModal(for:window){response in if response == .OK,let url=panel.url{field.stringValue=url.path}}
    }
    @objc private func browseCommand(){browse(commandField,directories:true,files:true)}
    @objc private func browseDirectory(){browse(directoryField,directories:true,files:false)}
    @objc private func browseIcon(){browse(iconField,directories:false,files:true)}
    func save()throws {
        capture();draft.iconSize=Int(size.titleOfSelectedItem ?? "22") ?? 22;draft.showLabels=labels.state == .on
        try draft.validate()
        guard let commander else{return}
        guard commander.barConfiguration==baseline else{throw CommanderButtonBar.failure("Button bar changed in another editor. Reopen this window before applying.")}
        let catalog=try? ReferenceMenuCatalog.load()
        for item in draft.items where !item.separator && item.command.lowercased().hasPrefix("cm_") {
            guard CommanderButtonBar.nativeCommands.contains(item.command.lowercased()) || ReferenceCommandRouting.isSupported(catalog?.id(for:item.command)) else{throw CommanderButtonBar.failure("Unsupported internal command: "+item.command)}
        }
        if commander.remember {try draft.save()}
        commander.barConfiguration=draft;baseline=draft;commander.rebuildButtonBar();reload(select:editingRow)
        note.stringValue="Button bar saved."
    }
    @objc func apply(){do{try save()}catch{note.stringValue=error.localizedDescription}}
    @objc private func ok(){do{try save();close()}catch{note.stringValue=error.localizedDescription}}
    @objc private func cancel(){close()}
    func windowWillClose(_ notification:Notification){commander?.barEditor=nil}
}
