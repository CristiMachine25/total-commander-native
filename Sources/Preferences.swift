import AppKit
import UniformTypeIdentifiers

private var preferencesWindow:PreferencesController?
private struct ConfigurationPage {
    let title:String
    let missing:String
    static let all:[ConfigurationPage] = [
        .init(title:"Layout",missing:"Second button bar, drive-button bars, breadcrumb parts, and Windows theme controls."),
        .init(title:"Display",missing:"DOS 8.3 filenames, Windows system attributes, file comments and plugin tooltips."),
        .init(title:"Icons",missing:"Windows EXE/LNK extraction, shell overlays and per-resolution icon profiles."),
        .init(title:"Font",missing:"Per-resolution font profiles, dialog DPI scaling and separate main-window/dialog fonts."),
        .init(title:"Color",missing:"File-type color rules, inverted outline cursors and Windows control-border palettes."),
        .init(title:"Tabstops",missing:"Independent progress-dialog units."),
        .init(title:"Custom Columns",missing:"Windows content-plugin fields, per-filesystem-plugin column sets, and original dialog-unit sizing."),
        .init(title:"View Modes",missing:"Windows tab-icon files and plugin-dependent commands."),
        .init(title:"Auto Switch Mode",missing:"Windows drive-type detection and filesystem-plugin conditions."),
        .init(title:"Folder Tabs",missing:"Locked tabs allowing directory changes, remote tab locks, multiline tabs and remaining tab-order policies."),
        .init(title:"Thumbnails",missing:"Windows OLE/Lister-plugin providers, EXIF custom fields and a persistent thumbnail database."),
        .init(title:"Operation",missing:"Tray behavior, mouse-selection compatibility modes and file-comment formats."),
        .init(title:"Edit/View",missing:"Per-extension external viewer associations, Windows command-line placeholders, Lister plugins/encoding presets, fixed-column wrap length and automatic FTP re-upload without confirmation."),
        .init(title:"Confirmation",missing:"Separate read-only/hidden-file prompts, drag-and-drop policy and external-command hotkeys. Permanent deletion always requires confirmation."),
        .init(title:"Copy/Delete",missing:"Windows CopyFileEx modes, NTFS streams, operation filters and remote resume. These copy policies apply to local filesystem transfers."),
        .init(title:"Refresh",missing:"Remote FTP/archive filesystem notifications and Windows removable/network-drive notifications."),
        .init(title:"Quick Search",missing:"Letters-with-dialog mode, original search-dialog widgets and last-filter restoration."),
        .init(title:"History",missing:"History thinning, frequency ranking, icons/fonts and custom history storage paths."),
        .init(title:"FTP",missing:"Global proxy, connection pooling, server encoding and legacy firewall options. Per-connection FTP/TLS settings are in Net → FTP Connect."),
        .init(title:"Packer",missing:"External packer commands and non-ZIP write formats."),
        .init(title:"ZIP Packer",missing:"Encryption, multi-volume ZIP and external ZIP implementations. Compression settings apply to new ZIP creation."),
        .init(title:"Plugins",missing:"Windows WCX/WFX/WLX/WDX plugin loading on native macOS."),
        .init(title:"Language",missing:"Runtime language-pack selection and localized native dialogs."),
        .init(title:"Ignore List",missing:"Recursive copy/move/synchronize exclusion, absolute paths, FTP/plugin prefixes and tcignore.txt import/export. This control currently filters the visible list only."),
        .init(title:"Keybindings",missing:"External commands, alias chains, and OS-reserved shortcut interception.")
    ]
}

final class PreferencesController:NSWindowController,NSWindowDelegate,NSTableViewDataSource,NSTableViewDelegate {
    private weak var commander:CommanderController?
    private var draft:CommanderConfiguration
    private var baseline:CommanderConfiguration
    private let categories=NSTableView(),page=NSStackView(),scroller=NSScrollView()
    private let heading=NSTextField(labelWithString:""),note=NSTextField(wrappingLabelWithString:"")
    private var readers:[()throws->Void]=[]
    private struct CachedPage {let views:[NSView];let readers:[()throws->Void]}
    private var cachedPages:[Int:CachedPage]=[:]
    private var currentPage=0,changingSelection=false
    init(_ commander:CommanderController) {
        self.commander=commander;baseline=commander.runtimeConfig;draft=commander.runtimeConfig;draft.showHidden=commander.showHidden
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:920,height:650),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.title="Configuration";window.isReleasedWhenClosed=false;window.minSize=NSSize(width:820,height:540);window.appearance=AppearanceSettings.appearance(commander.runtimeConfig.appearanceMode)
        super.init(window:window);window.delegate=self
        let column=NSTableColumn(identifier:.init("category"));column.title="Category";column.width=175;categories.addTableColumn(column)
        categories.headerView=nil;categories.dataSource=self;categories.delegate=self;categories.rowHeight=27;categories.allowsEmptySelection=false
        let navigation=NSScrollView();navigation.documentView=categories;navigation.hasVerticalScroller=true;navigation.borderType = .bezelBorder
        heading.font = .systemFont(ofSize:17,weight:.semibold)
        page.orientation = .vertical;page.alignment = .leading;page.spacing=12;page.edgeInsets=NSEdgeInsets(top:8,left:4,bottom:12,right:12)
        scroller.documentView=page;scroller.hasVerticalScroller=true;scroller.autohidesScrollers=true;scroller.drawsBackground=false
        page.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([page.widthAnchor.constraint(equalTo:scroller.contentView.widthAnchor),page.heightAnchor.constraint(greaterThanOrEqualTo:scroller.contentView.heightAnchor)])
        note.font = .systemFont(ofSize:11);note.textColor = .secondaryLabelColor
        let right=NSStackView(views:[heading,scroller,note]);right.orientation = .vertical;right.alignment = .leading;right.spacing=12
        let content=NSStackView(views:[navigation,right]);content.orientation = .horizontal;content.alignment = .top;content.spacing=18
        let restore=NSButton(title:"Restore defaults",target:self,action:#selector(restoreDefaults))
        let cancel=NSButton(title:"Cancel",target:self,action:#selector(dismiss));cancel.keyEquivalent="\u{1b}"
        let applyButton=NSButton(title:"Apply",target:self,action:#selector(applyWithoutClosing))
        let okay=NSButton(title:"OK",target:self,action:#selector(apply));okay.keyEquivalent="\r"
        let buttons=NSStackView(views:[restore,NSView(),cancel,applyButton,okay]);buttons.orientation = .horizontal;buttons.spacing=10
        let root=NSStackView(views:[content,buttons]);root.orientation = .vertical;root.alignment = .leading;root.spacing=16
        window.contentView!.addSubview(root);root.translatesAutoresizingMaskIntoConstraints=false
        for view in [content,buttons,right,heading,scroller,note,navigation]{view.translatesAutoresizingMaskIntoConstraints=false}
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor,constant:18),root.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor,constant:-18),root.topAnchor.constraint(equalTo:window.contentView!.topAnchor,constant:18),root.bottomAnchor.constraint(equalTo:window.contentView!.bottomAnchor,constant:-18),content.widthAnchor.constraint(equalTo:root.widthAnchor),buttons.widthAnchor.constraint(equalTo:root.widthAnchor),navigation.widthAnchor.constraint(equalToConstant:180),navigation.heightAnchor.constraint(equalTo:content.heightAnchor),right.heightAnchor.constraint(equalTo:content.heightAnchor),scroller.widthAnchor.constraint(equalTo:right.widthAnchor),note.widthAnchor.constraint(equalTo:right.widthAnchor),content.heightAnchor.constraint(greaterThanOrEqualToConstant:420)])
        categories.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false);showPage(0)
    }
    required init?(coder:NSCoder){fatalError("init(coder:) is not supported")}
    func windowWillClose(_ notification:Notification){if preferencesWindow === self{preferencesWindow=nil}}
    func numberOfRows(in tableView:NSTableView)->Int{ConfigurationPage.all.count}
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView?{NSTextField(labelWithString:ConfigurationPage.all[row].title)}
    func tableViewSelectionDidChange(_ notification:Notification){
        guard !changingSelection,categories.selectedRow>=0,categories.selectedRow != currentPage else{return}
        do{try collect();showPage(categories.selectedRow)}catch{show(error);changingSelection=true;categories.selectRowIndexes(IndexSet(integer:currentPage),byExtendingSelection:false);changingSelection=false}
    }
    private func collect()throws{for read in readers{try read()}}
    private func failure(_ message:String)->NSError{NSError(domain:"Configuration",code:1,userInfo:[NSLocalizedDescriptionKey:message])}
    private func show(_ error:Error){guard let window else{return};NSAlert(error:error).beginSheetModal(for:window)}
    private func row(_ label:String,_ control:NSView){
        let title=NSTextField(wrappingLabelWithString:label);title.font = .systemFont(ofSize:12)
        let stack=NSStackView(views:[title,control]);stack.orientation = .horizontal;stack.spacing=12;stack.alignment = .centerY
        title.widthAnchor.constraint(equalToConstant:235).isActive=true;control.widthAnchor.constraint(greaterThanOrEqualToConstant:110).isActive=true
        page.addArrangedSubview(stack)
    }
    private func checkbox(_ title:String,_ key:WritableKeyPath<CommanderConfiguration,Bool>){
        let control=NSButton(checkboxWithTitle:title,target:nil,action:nil);control.state=draft[keyPath:key] ? .on : .off;page.addArrangedSubview(control)
        readers.append{[weak self,weak control] in guard let self,let control else{return};self.draft[keyPath:key]=control.state == .on}
    }
    private func number(_ title:String,_ key:WritableKeyPath<CommanderConfiguration,Double>,_ range:ClosedRange<Double>){
        let control=NSTextField(string:String(format:"%g",draft[keyPath:key]));row(title,control)
        readers.append{[weak self,weak control] in guard let self,let control else{return};guard let value=Double(control.stringValue),value.isFinite,range.contains(value) else{throw self.failure("\(title) must be between \(range.lowerBound) and \(range.upperBound).")};self.draft[keyPath:key]=value}
    }
    private func integer(_ title:String,_ key:WritableKeyPath<CommanderConfiguration,Int>,_ range:ClosedRange<Int>){
        let control=NSTextField(string:String(draft[keyPath:key]));row(title,control)
        readers.append{[weak self,weak control] in guard let self,let control else{return};guard let value=Int(control.stringValue),range.contains(value) else{throw self.failure("\(title) must be between \(range.lowerBound) and \(range.upperBound).")};self.draft[keyPath:key]=value}
    }
    private func text(_ title:String,_ key:WritableKeyPath<CommanderConfiguration,String>){
        let control=NSTextField(string:draft[keyPath:key]);row(title,control)
        readers.append{[weak self,weak control] in guard let self,let control else{return};self.draft[keyPath:key]=control.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)}
    }
    private func choice<Value:Equatable>(_ title:String,_ key:WritableKeyPath<CommanderConfiguration,Value>,_ values:[(String,Value)]){
        let control=NSPopUpButton();control.addItems(withTitles:values.map(\.0));control.selectItem(at:values.firstIndex{$0.1==draft[keyPath:key]} ?? 0);row(title,control)
        readers.append{[weak self,weak control] in guard let self,let control,values.indices.contains(control.indexOfSelectedItem) else{return};self.draft[keyPath:key]=values[control.indexOfSelectedItem].1}
    }
    private func color(_ title:String,_ key:WritableKeyPath<CommanderConfiguration,ConfigurationColor>){
        let control=NSColorWell();control.color=draft[keyPath:key].nsColor;row(title,control)
        readers.append{[weak self,weak control] in guard let self,let control else{return};self.draft[keyPath:key]=ConfigurationColor(control.color)}
    }
    private func application(_ title:String,_ key:WritableKeyPath<CommanderConfiguration,String>){
        text(title,key)
        let button=NSButton(title:"Browse…",target:nil,action:nil)
        let field=(page.arrangedSubviews.last as? NSStackView)?.arrangedSubviews.last as? NSTextField
        let target=ConfigurationBrowseTarget(field:field);button.target=target;button.action=#selector(ConfigurationBrowseTarget.browse)
        objc_setAssociatedObject(button,&configurationBrowseKey,target,.OBJC_ASSOCIATION_RETAIN_NONATOMIC);page.addArrangedSubview(button)
    }
    private func showPage(_ index:Int){
        if !page.arrangedSubviews.isEmpty && !(6...8).contains(currentPage) {cachedPages[currentPage]=CachedPage(views:page.arrangedSubviews,readers:readers)}
        currentPage=index;readers.removeAll();for view in page.arrangedSubviews{page.removeArrangedSubview(view);view.removeFromSuperview()}
        let descriptor=ConfigurationPage.all[index];heading.stringValue=descriptor.title
        note.stringValue="Not yet implemented on this page: "+descriptor.missing
        if let cached=cachedPages[index] {
            for view in cached.views{page.addArrangedSubview(view)};readers=cached.readers
            scroller.contentView.scroll(to:.zero);scroller.reflectScrolledClipView(scroller.contentView)
            return
        }
        switch descriptor.title {
        case "Layout":
            checkbox("Show button bar",\.showButtonBar);checkbox("Show drive buttons above each panel",\.showDriveButtons);checkbox("Show drive combobox",\.showDriveList);checkbox("Show folder tabs",\.showFolderTabs);checkbox("Show current directory",\.showCurrentDirectory);checkbox("Show tabstop header",\.showColumnHeaders);checkbox("Show status bar",\.showStatusBar);checkbox("Show command line",\.showCommandLine);checkbox("Show function key buttons",\.showFunctionButtons);checkbox("Vertical arrangement (panels above/below)",\.verticalArrangement)
        case "Display":
            checkbox("Show hidden files",\.showHidden)
            checkbox("Show square brackets around directories",\.directoryBrackets)
            checkbox("Append / to directory names (macOS)",\.directoryTrailingSlash)
            checkbox("Directories before files",\.directoriesFirst)
            checkbox("Sort grouped directories by name",\.directoriesAlwaysByName)
            choice("Sorting method",\.sortMethod,[("Natural alphabetical",.naturalAlphabetical),("Alphabetical",.alphabetical),("Character code",.characterCode),("Natural character code",.naturalCharacterCode)])
            checkbox("Case-sensitive name sorting (native override)",\.caseSensitiveSort)
        case "Icons":choice("Show icons to the left of the filename",\.iconMode,[("All associated (macOS)",.system),("Only standard icons",.standard),("No icons",.none)]);integer("Icon size",\.iconSize,12...48)
        case "Font":text("File list font",\.fileFontName);number("Font size",\.fileFontSize,9...36);checkbox("Bold",\.fileFontBold);number("File row height",\.rowHeight,16...64)
        case "Color":
            choice("Appearance",\.appearanceMode,[("Normal",.light),("Dark",.dark),("Follow macOS",.system)])
            color("Dark font color",\.darkPalette.foreground);color("Dark background",\.darkPalette.background);color("Dark mark color",\.darkPalette.markedForeground);color("Dark cursor color",\.darkPalette.selectionBackground);color("Dark cursor font",\.darkPalette.selectionForeground);color("Dark alternate background",\.darkPalette.alternatingBackground)
            color("Font color",\.foreground);color("Background",\.background);color("Mark color",\.markedForeground);color("Cursor color",\.selectionBackground);color("Cursor font",\.selectionForeground);checkbox("Use alternating row backgrounds",\.alternatingRowBackground);color("Alternate row background",\.alternatingBackground)
        case "Tabstops":
            checkbox("Show directory count in footer",\.showDirectoryCount)
            integer("Brief column width limit (0 = automatic)",\.briefColumnWidthLimit,0...1200)
            choice("Show file extensions",\.extensionStyle,[("Aligned (with TAB)",.aligned),("Directly after filename",.afterName)])
            for (key,title) in [("name","Name"),("ext","Extension"),("size","Size"),("date","Date/time"),("attr","Attributes")]{
                let width=NSTextField(string:String(Int(draft.columnWidths[key] ?? 80)));row(title+" column width",width)
                readers.append{[weak self,weak width] in guard let self,let width else{return};guard let value=Double(width.stringValue),(32...1200).contains(value) else{throw self.failure("Column widths must be between 32 and 1,200 points.")};self.draft.columnWidths[key]=value}
                if key != "name"{let visible=NSButton(checkboxWithTitle:"Show "+title.lowercased()+" column",target:nil,action:nil);visible.state=draft.visibleColumns.contains(key) ? .on : .off;page.addArrangedSubview(visible);readers.append{[weak self,weak visible] in guard let self,let visible else{return};self.draft.visibleColumns.removeAll{$0==key};if visible.state == .on{self.draft.visibleColumns.append(key)}}}
            }
            choice("Size display",\.sizeFormat,[("bytes",.bytes),("kbytes",.kilobytes),("dynamic (x k/M/G)",.dynamicGigabytes),("dynamic (x.x k/M/G)",.dynamicOneDecimalGigabytes),("dynamic (x k/M)",.dynamicMegabytes),("dynamic (x.x k/M)",.dynamicOneDecimalMegabytes),("dynamic (x k/M/G/T)",.dynamic),("dynamic (x.x k/M/G/T)",.dynamicOneDecimal),("dynamic (x.xx k/M/G)",.dynamicTwoDecimalsGigabytes),("dynamic (x.xx k/M/G/T)",.dynamicTwoDecimals),("Fixed MB (native addition)",.megabytes),("Fixed GB (native addition)",.gigabytes)])
            choice("Header/footer size display",\.footerSizeFormat,[("Same as file list",nil),("bytes",.bytes),("kbytes",.kilobytes),("dynamic (x k/M/G)",.dynamicGigabytes),("dynamic (x.x k/M/G)",.dynamicOneDecimalGigabytes),("dynamic (x k/M)",.dynamicMegabytes),("dynamic (x.x k/M)",.dynamicOneDecimalMegabytes),("dynamic (x k/M/G/T)",.dynamic),("dynamic (x.x k/M/G/T)",.dynamicOneDecimal),("dynamic (x.xx k/M/G)",.dynamicTwoDecimalsGigabytes),("dynamic (x.xx k/M/G/T)",.dynamicTwoDecimals),("Fixed MB (native addition)",.megabytes),("Fixed GB (native addition)",.gigabytes)])
            checkbox("Use 1000-byte units (SizeStyle1000)",\.useDecimalUnits)
            choice("Date format",\.dateOrder,[("System locale",.system),("Day first",.dayFirst),("Month first",.monthFirst),("Year first (ISO)",.yearFirst)])
            checkbox("Show century in date",\.showCentury);checkbox("Show seconds",\.showSeconds)
            text("Date separator (blank = default)",\.dateSeparator);text("Time separator (blank = default)",\.timeSeparator);checkbox("Use 12-hour time",\.use12HourTime)
        case "Custom Columns":
            let editor=DisplaySettingsEditors.columns(draft.customColumnSets)
            editor.mayDelete={ [weak self] set in
                guard let self else{return}
                guard !self.draft.viewModes.contains(where:{$0.customColumnSetID==set.id}) else{throw self.failure("This column set is used by a view mode. Change that mode first.")}
                if self.draft.activeCustomColumnSetID==set.id {self.draft.activeCustomColumnSetID=""}
            }
            page.addArrangedSubview(editor)
            let activate=NSButton(checkboxWithTitle:"Use the selected set as the default columns",target:nil,action:nil)
            activate.state=draft.activeCustomColumnSetID.isEmpty ? .off:.on;page.addArrangedSubview(activate)
            if let index=draft.customColumnSets.firstIndex(where:{$0.id==draft.activeCustomColumnSetID}) {editor.selectItem(at:index)}
            readers.append{[weak self,weak editor,weak activate] in
                guard let self,let editor,let activate else{return};let sets=try editor.values();self.draft.customColumnSets=sets
                self.draft.activeCustomColumnSetID=activate.state == .on && sets.indices.contains(editor.picker.indexOfSelectedItem) ? sets[editor.picker.indexOfSelectedItem].id:""
            }
        case "View Modes":
            let editor=DisplaySettingsEditors.modes(draft.viewModes,sets:{[weak self] in self?.draft.customColumnSets ?? []})
            editor.mayDelete={ [weak self] mode in guard let self else{return};guard !self.draft.autoSwitchRules.contains(where:{$0.viewModeID==mode.id}) else{throw self.failure("This view mode is used by an automatic switching rule. Change or delete that rule first.")}}
            page.addArrangedSubview(editor)
            readers.append{[weak self,weak editor] in guard let self,let editor else{return};self.draft.viewModes=try editor.values()}
        case "Auto Switch Mode":
            checkbox("Automatically switch view mode on directory change",\.autoSwitchEnabled)
            checkbox("Restore default mode when no rule matches",\.autoSwitchRestoreDefault)
            page.addArrangedSubview(NSTextField(wrappingLabelWithString:"Rules are tested from top to bottom. The first matching rule wins. File conditions inspect only the current directory; no recursive scans are performed."))
            let editor=DisplaySettingsEditors.rules(draft.autoSwitchRules,modes:{[weak self] in self?.draft.viewModes ?? []})
            page.addArrangedSubview(editor)
            readers.append{[weak self,weak editor] in guard let self,let editor else{return};self.draft.autoSwitchRules=try editor.values()}
        case "Folder Tabs":checkbox("Show tab header also when there is only one tab",\.tabsAlwaysVisible);integer("Limit tab length to characters",\.tabTitleMaximum,8...100);checkbox("Open new tabs near current tab",\.newTabBesideCurrent);checkbox("Close tab on double-click",\.tabsCloseOnDoubleClick);checkbox("Confirm closing all other tabs",\.confirmCloseAllTabs);checkbox("Show asterisk on locked tabs",\.tabsShowLockAsterisk);checkbox("Remember view settings separately for each tab",\.tabsRememberViewSettings);checkbox("Remember displayed file types separately for each tab",\.tabsRememberFileFilters)
        case "Thumbnails":integer("Thumbnail size (pixels)",\.thumbnailSize,64...256)
        case "Operation":checkbox("Save directory/tabs on exit",\.saveOnExit);checkbox("Open files/directories with a single click",\.singleClickOpen);checkbox("Select directories with Select All",\.selectionIncludesDirectories)
        case "Edit/View":checkbox("Use external viewer for F3",\.externalViewerEnabled);application("External viewer application",\.externalViewerPath);checkbox("Use external editor for F4",\.externalEditorEnabled);application("External editor application",\.externalEditorPath);text("Internal viewer font",\.viewerFontName);number("Internal viewer font size",\.viewerFontSize,9...36);checkbox("Wrap internal viewer text to window",\.viewerWordWrap)
        case "Confirmation":
            checkbox("Confirm local copy/move destination",\.confirmCopyMove)
            checkbox("Confirm replacement of existing local files",\.confirmOverwrite)
            checkbox("Confirm moving local files to Trash",\.confirmDelete)
        case "Keybindings":
            let editor=KeybindingsEditor(shortcuts:draft.customShortcuts,aliases:draft.commandAliases)
            page.addArrangedSubview(editor)
            readers.append{[weak self,weak editor] in guard let self,let editor else{return};self.draft.customShortcuts=try editor.serializedBindings();self.draft.commandAliases=editor.aliasField.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)}
        case "Copy/Delete":
            choice("Existing local destination",\.copyDefaultCollision,[("Ask", "ask"),("Skip existing", "skip"),("Replace existing", "replace"),("Keep both (rename)", "rename")])
            checkbox("Preserve file timestamps",\.copyPreserveFileDates)
            checkbox("Preserve directory timestamps",\.copyPreserveDirectoryDates)
            checkbox("Preserve permissions",\.copyPreservePermissions)
            checkbox("Verify copied file data before committing",\.copyVerifyAfterCopy)
            integer("Copy buffer size (KiB)",\.copyBufferSizeKB,64...16384)
            checkbox("Delete local files to Trash",\.deleteToTrash)
        case "Refresh":
            checkbox("Refresh local panes when app becomes active",\.refreshOnActivate)
            checkbox("Automatically refresh changed local folders",\.autoRefreshEnabled)
            checkbox("Also detect size/date changes",\.autoRefreshMetadata)
            checkbox("Only while this app is in the foreground",\.autoRefreshOnlyForeground)
            checkbox("Update free-space header during automatic refresh",\.autoRefreshUpdateHeader)
            text("Excluded local paths (separated by ;)",\.autoRefreshExcludedPaths)
        case "FTP":
            checkbox("Passive mode for new connections",\.ftpPassiveMode)
            integer("Connect timeout (seconds)",\.ftpConnectTimeout,1...300)
            integer("Transfer timeout (seconds)",\.ftpTransferTimeout,1...86400)
            choice("Open connection in",\.ftpOpenPanel,[("Active pane",0),("Left pane",1),("Right pane",2),("Other pane",3)])
        case "Packer":
            checkbox("Open archives like directories",\.browseArchivesAsDirectories)
            checkbox("Set new ZIP date to newest source file",\.archiveSetDateToNewest)
        case "ZIP Packer":
            choice("ZIP compression level",\.zipCompressionLevel,[("0 — Store",0),("1 — Fastest",1),("2",2),("3",3),("4",4),("5",5),("6 — Normal",6),("7",7),("8",8),("9 — Maximum",9)])
            checkbox("Verify ZIP after packing",\.zipVerifyAfterPacking)
        case "Quick Search":choice("Quick search in current directory",\.quickSearchMode,[("Disabled",.disabled),("Letter only",.letters),("ALT + Letters",.alt),("CTRL + ALT + Letters",.ctrlAlt)]);checkbox("Beginning: name must start with typed characters",\.quickSearchMatchBeginning);checkbox("Ending: exact name before typed dot",\.quickSearchMatchEnding)
        case "Ignore List":checkbox("Enable ignore list — display filtering only",\.ignoreListEnabled);text("Name patterns (separated by ;)",\.ignorePatterns)
        case "History":
            integer("Maximum directory history items",\.historyLimit,1...200)
            integer("Maximum history entries shown",\.historyMaximumShown,1...200)
            checkbox("Save directory history on exit",\.historySaveOnExit)
            checkbox("Show icons in directory history",\.historyShowIcons)
            let actions=NSStackView(views:[NSButton(title:"Save history now",target:self,action:#selector(saveHistoryNow)),NSButton(title:"Delete saved history",target:self,action:#selector(deleteHistoryNow))]);actions.spacing=8;page.addArrangedSubview(actions)
            page.addArrangedSubview(NSTextField(wrappingLabelWithString:"Save and Delete act immediately on saved local directory history using your applied settings. Current navigation history is kept."))
        default:let text=NSTextField(wrappingLabelWithString:"The original category is listed here for reference. Its settings are not implemented yet; there are no inactive controls that appear to save working options.");page.addArrangedSubview(text);text.widthAnchor.constraint(equalTo:page.widthAnchor,constant:-24).isActive=true
        }
        scroller.contentView.scroll(to:.zero);scroller.reflectScrolledClipView(scroller.contentView)
    }
    func selectPage(index:Int) {guard ConfigurationPage.all.indices.contains(index) else{return};categories.selectRowIndexes(IndexSet(integer:index),byExtendingSelection:false)}
    @objc private func restoreDefaults(){
        draft=CommanderConfiguration();cachedPages.removeAll();readers.removeAll()
        for view in page.arrangedSubviews{page.removeArrangedSubview(view);view.removeFromSuperview()}
        showPage(currentPage)
    }
    @objc private func dismiss(){close()}
    /// Shared by the buttons and nonmodal regression tests. A second settings
    /// editor must not overwrite changes applied since this dialog was opened.
    func applyDraft()throws {
            guard let commander else{throw failure("The file-manager window is no longer available.")}
            guard commander.runtimeConfig==baseline else{throw failure("Settings changed while this dialog was open. Close and reopen it to avoid overwriting newer changes.")}
            try collect()
            guard draft.dateSeparator.count<=3,draft.timeSeparator.count<=3,!draft.dateSeparator.contains(where:{$0.isNewline}),!draft.timeSeparator.contains(where:{$0.isNewline}) else{throw failure("Date/time separators must contain at most three characters and no line breaks.")}
            for path in draft.autoRefreshExcludedPaths.split(separator:";").map({$0.trimmingCharacters(in:.whitespacesAndNewlines)}) where !path.isEmpty {
                guard path.hasPrefix("/") || path.hasPrefix("~/") else{throw failure("Refresh exclusions must be absolute local folder paths, separated by semicolons.")}
            }
            try ShortcutSettings.validate(shortcuts:draft.customShortcuts,aliases:draft.commandAliases)
            try CustomColumnSettings.validate(sets:draft.customColumnSets,activeID:draft.activeCustomColumnSetID)
            try ViewModeSettings.validate(modes:draft.viewModes,rules:draft.autoSwitchRules,customColumnSets:draft.customColumnSets)
            draft=draft.normalized()
            for (enabled,path,title) in [(draft.externalViewerEnabled,draft.externalViewerPath,"Viewer"),(draft.externalEditorEnabled,draft.externalEditorPath,"Editor")] where enabled {
                var directory:ObjCBool=false
                guard path.hasPrefix("/"),URL(fileURLWithPath:path).pathExtension.lowercased()=="app",FileManager.default.fileExists(atPath:path,isDirectory:&directory),directory.boolValue else{throw failure("\(title): choose an existing macOS .app application.")}
            }
            guard draft.fileFontName == "Tahoma" || NSFont(name:draft.fileFontName,size:draft.fileFontSize) != nil else{throw failure("The file list font is not installed. Enter its macOS font name.")}
            guard NSFont(name:draft.viewerFontName,size:draft.viewerFontSize) != nil else{throw failure("The internal viewer font is not installed.")}
            if commander.remember {try draft.save()};commander.applyConfiguration(draft);baseline=commander.runtimeConfig
    }
    @objc private func saveHistoryNow(){commander?.saveDirectoryHistoryNow()}
    @objc private func deleteHistoryNow(){commander?.clearDirectoryHistoryNow()}
    private func save()->Bool {
        do {try applyDraft();return true}catch{show(error);return false}
    }
    @objc private func applyWithoutClosing(){if save(){showPage(currentPage)}}
    @objc private func apply(){if save(){close()}}
}
private var configurationBrowseKey:UInt8=0
private final class ConfigurationBrowseTarget:NSObject {
    weak var field:NSTextField?
    init(field:NSTextField?){self.field=field}
    @objc func browse(){let panel=NSOpenPanel();panel.canChooseFiles=true;panel.canChooseDirectories=false;panel.allowedContentTypes=[.applicationBundle];panel.treatsFilePackagesAsDirectories=false;panel.allowsMultipleSelection=false;panel.directoryURL=URL(fileURLWithPath:"/Applications");if panel.runModal() == .OK,let url=panel.url{field?.stringValue=url.path}}
}
extension CommanderController {
    @objc func configuration(){if let existing=preferencesWindow{existing.showWindow(nil);existing.window?.makeKeyAndOrderFront(nil);return};preferencesWindow=PreferencesController(self);preferencesWindow?.window?.center();preferencesWindow?.showWindow(nil)}
    func openPreferences(page:Int) {configuration();preferencesWindow?.selectPage(index:page)}
    func applyAppearancePreferences(){applyConfiguration(remember ? CommanderConfiguration.load() : runtimeConfig)}
}

func refreshPreferencesAppearance(_ mode:CommanderAppearanceMode){preferencesWindow?.window?.appearance=AppearanceSettings.appearance(mode)}
