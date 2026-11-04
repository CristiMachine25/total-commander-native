import AppKit
import ObjectiveC

private final class NamedViewState:NSObject {
    struct Snapshot {
        var configuration:CommanderConfiguration
        var columns:PaneViewMode
        var sort:String
        var ascending:Bool
        var mask:String
        var programs:Bool
        var selectedOnly:Set<URL>?
        var locationIdentity:String
        var secondary:[String]
    }
    var baseline:Snapshot?
    var defaultBaseline:Snapshot?
    var manualModeID:String?
    var currentMode:CommanderViewMode?
    var automatic=false
    var secondary:[String]=[]
}
private var namedViewStateKey:UInt8=0
extension Pane {
    fileprivate var namedViewState:NamedViewState {
        if let state=objc_getAssociatedObject(self,&namedViewStateKey) as? NamedViewState{return state}
        let state=NamedViewState();objc_setAssociatedObject(self,&namedViewStateKey,state,.OBJC_ASSOCIATION_RETAIN_NONATOMIC);return state
    }
    var currentNamedViewModeID:String? {namedViewState.currentMode?.id}
    var namedViewIsAutomatic:Bool {namedViewState.automatic}
    fileprivate func captureNamedViewBaseline() {
        namedViewState.baseline = .init(configuration:configuration,columns:viewMode,sort:sortColumn,ascending:ascending,mask:fileMask,programs:showProgramsOnly,selectedOnly:selectedOnly,locationIdentity:location.identity,secondary:namedViewState.secondary)
    }
    fileprivate func restoreNamedViewBaseline() {
        guard let snapshot=namedViewState.baseline else{return}
        applyConfiguration(snapshot.configuration);sortColumn=snapshot.sort;ascending=snapshot.ascending;fileMask=snapshot.mask;showProgramsOnly=snapshot.programs;selectedOnly=snapshot.locationIdentity==location.identity ? snapshot.selectedOnly:nil;namedViewState.secondary=snapshot.secondary
        setNamedColumns(snapshot.columns)
        applyListing(refreshListedEntries,location:location)
    }
    fileprivate func setNamedColumns(_ mode:PaneViewMode) {
        let remember=remembersViewMode;remembersViewMode=false;defer{remembersViewMode=remember}
        switch mode {case .full:setBriefMode(false);case .brief:setBriefMode(true);case .thumbnails:if !setThumbnailMode(){setBriefMode(false)};case .tree:setTreeMode(root:location)}
    }
    fileprivate func installNamedViewMode(_ mode:CommanderViewMode) {
        var config=configuration
        if let id=mode.customColumnSetID {config.activeCustomColumnSetID=id}
        if let value=mode.directoriesFirst {config.directoriesFirst=value}
        if let color=mode.background {config.background=color}
        if let color=mode.foreground {config.foreground=color}
        if let color=mode.alternatingBackground {config.alternatingBackground=color;config.alternatingRowBackground=true}
        namedViewState.secondary=mode.secondarySortColumns
        applyConfiguration(config)
        if mode.sortColumn != "unchanged" {sortColumn=mode.sortColumn}
        if let value=mode.ascending {ascending=value}
        if let mask=mode.fileMask {fileMask=mask;showProgramsOnly=false;selectedOnly=nil}
        switch mode.columnsView {case .unchanged:break;case .full:setNamedColumns(.full);case .brief:setNamedColumns(.brief);case .thumbnails:setNamedColumns(.thumbnails)}
        if let id=mode.customColumnSetID,!id.isEmpty {setNamedColumns(.full)}
        applyListing(refreshListedEntries,location:location)
        namedViewState.currentMode=mode;decorateNamedViewTab()
    }
    func decorateNamedViewTab() {
        // The standard segmented control has no per-segment background API; render
        // a small native color swatch with optional SF symbol inside the tab instead.
        for index in 0..<tabControl.segmentCount {tabControl.setImage(nil,forSegment:index)}
        guard tabControl.segmentCount>selectedTab,let mode=namedViewState.currentMode,mode.tabColor != nil || !mode.tabIcon.isEmpty else{return}
        let symbol=mode.tabIcon.isEmpty ? nil:NSImage(systemSymbolName:mode.tabIcon,accessibilityDescription:mode.name)
        let image=NSImage(size:NSSize(width:16,height:16),flipped:false){rect in
            if let color=mode.tabColor {color.nsColor.setFill();NSBezierPath(roundedRect:rect.insetBy(dx:1,dy:1),xRadius:3,yRadius:3).fill()}
            symbol?.draw(in:rect.insetBy(dx:2,dy:2));return true
        }
        tabControl.setImage(image,forSegment:selectedTab);let label=tabControl.label(forSegment:selectedTab) ?? ""
        tabControl.setWidth(max(40,(label as NSString).size(withAttributes:[.font:tabControl.font ?? NSFont.systemFont(ofSize:12)]).width+24)+18,forSegment:selectedTab)
    }
    func sortNamedViewEntriesIfNeeded()->Bool {
        let secondary=namedViewState.secondary
        guard !secondary.isEmpty,sortColumn != "unsorted" else{return false}
        func compare(_ a:FileEntry,_ b:FileEntry,key:String)->ComparisonResult {
            if key.hasPrefix("custom."),let result=compareCustomColumn(key,a,b){return result}
            switch key {
            case "size":return a.size==b.size ? .orderedSame:(a.size<b.size ? .orderedAscending:.orderedDescending)
            case "date":return (a.modified ?? .distantPast).compare(b.modified ?? .distantPast)
            case "ext":let x=(a.name as NSString).pathExtension,y=(b.name as NSString).pathExtension;return configuration.caseSensitiveSort ? x.compare(y):x.localizedStandardCompare(y)
            default:return configuration.caseSensitiveSort ? a.name.compare(b.name):a.name.localizedStandardCompare(b.name)
            }
        }
        entries=entries.enumerated().sorted { left,right in
            let a=left.element,b=right.element
            if configuration.directoriesFirst,a.isDirectory != b.isDirectory{return a.isDirectory}
            let keys=[(sortColumn,ascending)]+secondary.map{($0.hasPrefix("-") ? String($0.dropFirst()):$0,!$0.hasPrefix("-"))}
            for (key,forward) in keys {let value=compare(a,b,key:key);if value != .orderedSame{return forward ? value == .orderedAscending:value == .orderedDescending}}
            return left.offset<right.offset
        }.map(\.element)
        return true
    }
}
private final class ViewModeMenuAction:NSObject {
    let action:()->Void
    init(_ action:@escaping ()->Void){self.action=action}
    @objc func invoke(){action()}
}
extension CommanderController {
    func viewContext(_ pane:Pane)->CommanderViewContext {
        let kind:CommanderViewContext.Kind
        switch pane.location {case .local:kind = .local;case .archive:kind = .archive;case .ftp:kind = .ftp}
        return .init(kind:kind,path:pane.location.displayPath,fileNames:pane.refreshListedEntries.filter{!$0.isDirectory}.map(\.name))
    }
    func applyAutomaticViewMode(to pane:Pane,directoryChanged:Bool=true,tabSwitch:Bool=false) {
        let state=pane.namedViewState
        guard runtimeConfig.autoSwitchEnabled else {
            if state.automatic {pane.restoreNamedViewBaseline();state.automatic=false;state.currentMode=state.manualModeID.flatMap{id in runtimeConfig.viewModes.first{$0.id==id}};pane.updateTabs()}
            return
        }
        let id=ViewModeSettings.matchingModeID(rules:runtimeConfig.autoSwitchRules,context:viewContext(pane))
        let mode=id.flatMap{id in runtimeConfig.viewModes.first{$0.id==id}} ?? (runtimeConfig.autoSwitchRestoreDefault ? runtimeConfig.viewModes.first{$0.id=="default"}:nil)
        if let mode {
            if !state.automatic {pane.captureNamedViewBaseline()}
            transitionViewMode(mode,pane:pane,automatic:true,directoryChanged:directoryChanged,tabSwitch:tabSwitch)
        } else if state.automatic,runtimeConfig.autoSwitchRestoreDefault {
            runModeCommands(state.currentMode,pane:pane,entering:false,directoryChanged:directoryChanged,tabSwitch:tabSwitch)
            pane.restoreNamedViewBaseline();state.automatic=false
            state.currentMode=state.manualModeID.flatMap{id in runtimeConfig.viewModes.first{$0.id==id}};pane.updateTabs()
        }
    }
    private func transitionViewMode(_ mode:CommanderViewMode,pane:Pane,automatic:Bool,directoryChanged:Bool,tabSwitch:Bool) {
        let state=pane.namedViewState,changed=state.currentMode?.id != mode.id
        if changed {runModeCommands(state.currentMode,pane:pane,entering:false,directoryChanged:directoryChanged,tabSwitch:tabSwitch)}
        // Rebuild from the original manual baseline, not the previous automatic
        // mode's overrides. Re-evaluating the same mode must not accumulate state.
        if state.automatic {pane.restoreNamedViewBaseline()}
        pane.installNamedViewMode(mode);state.automatic=automatic
        if changed || (directoryChanged && ((try? ViewModeSettings.commands(mode.autoRunCommands).everyDirectory) ?? false)) {runModeCommands(mode,pane:pane,entering:true,directoryChanged:directoryChanged,tabSwitch:tabSwitch)}
    }
    @discardableResult func applyNamedViewMode(id:String,pane:Pane?=nil)->Bool {
        guard !busy else{return false};let pane=pane ?? activePane
        guard !pane.isLoading else{return false}
        let state=pane.namedViewState
        if id.isEmpty || (id=="default" && !runtimeConfig.viewModes.contains{$0.id=="default"}) {
            runModeCommands(state.currentMode,pane:pane,entering:false,directoryChanged:false,tabSwitch:false)
            if let original=state.defaultBaseline {state.baseline=original}
            pane.restoreNamedViewBaseline();state.currentMode=nil;state.manualModeID=nil;state.automatic=false;state.baseline=nil;state.defaultBaseline=nil;pane.updateTabs();if remember && runtimeConfig.saveOnExit {saveNamedViewChoices()};return true
        }
        guard let mode=runtimeConfig.viewModes.first(where:{$0.id==id}) else{return false}
        if state.baseline==nil {pane.captureNamedViewBaseline()}
        if state.defaultBaseline==nil {state.defaultBaseline=state.baseline}
        transitionViewMode(mode,pane:pane,automatic:false,directoryChanged:false,tabSwitch:false)
        state.manualModeID=id;pane.captureNamedViewBaseline();if remember && runtimeConfig.saveOnExit {saveNamedViewChoices()};return true
    }
    func recordManualViewChange(in pane:Pane) {
        let state=pane.namedViewState;state.automatic=false;state.currentMode=nil;state.manualModeID=nil
        pane.captureNamedViewBaseline();state.defaultBaseline=state.baseline;pane.updateTabs()
        if remember && runtimeConfig.saveOnExit {saveNamedViewChoices()}
    }
    func saveNamedViewChoices() {
        guard remember else{return}
        for (name,pane) in [("left",left),("right",right)] {
            let state=pane.namedViewState
            UserDefaults.standard.set(state.manualModeID,forKey:"viewMode.manual."+name)
            UserDefaults.standard.set((state.automatic ? state.baseline?.configuration.activeCustomColumnSetID:pane.configuration.activeCustomColumnSetID) ?? "",forKey:"viewMode.custom."+name)
        }
    }
    func finishRestoringNamedViewModes() {
        let savedModes=Dictionary(uniqueKeysWithValues:["left","right"].map{($0,UserDefaults.standard.string(forKey:"viewMode.manual."+$0))})
        let savedColumns=Dictionary(uniqueKeysWithValues:["left","right"].map{($0,UserDefaults.standard.string(forKey:"viewMode.custom."+$0))})
        for (name,pane) in [("left",left),("right",right)] {
            let state=pane.namedViewState
            // Appearance is applied before legacy per-pane layout restoration.
            // Clear any early auto override, then establish the real startup baseline.
            state.baseline=nil;state.defaultBaseline=nil;state.currentMode=nil;state.manualModeID=nil;state.automatic=false;state.secondary=[]
            var config=runtimeConfig
            if remember,let custom=savedColumns[name] ?? nil,custom.isEmpty || config.customColumnSets.contains(where:{$0.id==custom}) {config.activeCustomColumnSetID=custom}
            pane.applyConfiguration(config)
            if remember,let id=savedModes[name] ?? nil,runtimeConfig.viewModes.contains(where:{$0.id==id}) {_=applyNamedViewMode(id:id,pane:pane)}
            applyAutomaticViewMode(to:pane,directoryChanged:false)
        }
    }
    func reconfigureNamedViewModes() {
        for pane in [left,right] {
            let state=pane.namedViewState
            if var baseline=state.baseline {
                let customID=baseline.configuration.activeCustomColumnSetID
                baseline.configuration=runtimeConfig
                if runtimeConfig.customColumnSets.contains(where:{$0.id==customID}) {baseline.configuration.activeCustomColumnSetID=customID}
                state.baseline=baseline
            }
            if var baseline=state.defaultBaseline {baseline.configuration=runtimeConfig;state.defaultBaseline=baseline}
            if let manual=state.manualModeID,let mode=runtimeConfig.viewModes.first(where:{$0.id==manual}) {pane.installNamedViewMode(mode);pane.captureNamedViewBaseline()}
            else if state.manualModeID != nil {state.manualModeID=nil;state.currentMode=nil;state.baseline=nil;state.automatic=false}
            if state.manualModeID==nil,!state.automatic,let baseline=state.baseline {
                var effective=pane.configuration;effective.activeCustomColumnSetID=baseline.configuration.activeCustomColumnSetID;pane.applyConfiguration(effective)
            }
            applyAutomaticViewMode(to:pane,directoryChanged:false)
        }
    }
    func showViewModeMenu() {
        let menu=NSMenu();menu.autoenablesItems=false
        func add(_ title:String,_ id:String) {
            let target=ViewModeMenuAction{[weak self] in _=self?.applyNamedViewMode(id:id)}
            let item=NSMenuItem(title:title,action:#selector(ViewModeMenuAction.invoke),keyEquivalent:"");item.target=target;item.representedObject=target;item.state=activePane.currentNamedViewModeID==id ? .on:.off;menu.addItem(item)
        }
        add("<Default>","default")
        for mode in runtimeConfig.viewModes where mode.id != "default" {add(mode.name,mode.id)}
        menu.popUp(positioning:nil,at:NSPoint(x:8,y:activePane.view.bounds.height-30),in:activePane.view)
    }
    private func runModeCommands(_ mode:CommanderViewMode?,pane:Pane,entering:Bool,directoryChanged:Bool,tabSwitch:Bool) {
        guard let mode,let parsed=try? ViewModeSettings.commands(mode.autoRunCommands),!(tabSwitch && parsed.skipTab) else{return}
        for command in entering ? parsed.enter:parsed.leave {
            switch command {
            case "cm_srclong":pane.setNamedColumns(.full)
            case "cm_srcshort":pane.setNamedColumns(.brief)
            case "cm_srcthumbs":pane.setNamedColumns(.thumbnails)
            case "cm_srcbyname":pane.sortColumn="name";pane.ascending=true
            case "cm_srcbyext":pane.sortColumn="ext";pane.ascending=true
            case "cm_srcbysize":pane.sortColumn="size";pane.ascending=true
            case "cm_srcbydatetime":pane.sortColumn="date";pane.ascending=true
            case "cm_srcunsorted":pane.sortColumn="unsorted"
            case "cm_srcnegorder":pane.ascending.toggle()
            case "cm_srcallfiles":pane.fileMask="";pane.showProgramsOnly=false;pane.selectedOnly=nil
            case "cm_srcexecs":pane.fileMask="";pane.showProgramsOnly=true;pane.selectedOnly=nil
            case "cm_50percent":splitView.setPosition((splitView.isVertical ? splitView.bounds.width:splitView.bounds.height)/2,ofDividerAt:0)
            case "cm_100percent":let length=splitView.isVertical ? splitView.bounds.width:splitView.bounds.height;splitView.setPosition(pane === left ? length:0,ofDividerAt:0)
            default:break
            }
        }
        pane.applyListing(pane.refreshListedEntries,location:pane.location)
    }
}
