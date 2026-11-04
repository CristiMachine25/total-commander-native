import AppKit
@main struct ViewModeSettingsTests {
    static func main()throws {
        let app=NSApplication.shared;app.setActivationPolicy(.prohibited)
        var checks=0
        func check(_ value:Bool,_ reason:String){checks += 1;precondition(value,reason)}
        let context=CommanderViewContext(kind:.local,path:"/Pictures/2026",fileNames:["a.jpg","b.JPG","c.txt","note"])
        check(ViewModeSettings.pathMatches("/Pictures",pattern:"/Pictures/*",subdirectories:false),"Trailing wildcard includes parent")
        check(ViewModeSettings.pathMatches("/Pictures/2026/April",pattern:"/Pictures",subdirectories:true),"Subdirectories match")
        check(!ViewModeSettings.pathMatches("/PicturesElse",pattern:"/Pictures",subdirectories:true),"Path boundaries respected")
        check(ViewModeSettings.fileMatches("a.jpg",mask:"*.jpg *.png | backup*"),"Space mask list")
        check(!ViewModeSettings.fileMatches("backup.jpg",mask:"*.jpg | backup*"),"Exclusion mask")
        check(ViewModeSettings.fileMatches("README",mask:"*.*"),"DOS wildcard extensionless")
        var condition=CommanderViewCondition(kind:.fileMask,value:"*.jpg",fileMatch:.half)
        check(ViewModeSettings.matches(condition,context:context),"Half files jpg")
        condition.fileMatch = .all;check(!ViewModeSettings.matches(condition,context:context),"All files condition")
        condition.fileMatch = .none;check(!ViewModeSettings.matches(condition,context:context),"None files condition")
        condition.value="*.zip";check(ViewModeSettings.matches(condition,context:context),"No matching names")
        condition.fileMatch = .percent;condition.value="*.jpg";condition.minimumMatchPercent=51
        check(!ViewModeSettings.matches(condition,context:context),"Percentage threshold")
        condition.minimumMatchPercent=50;check(ViewModeSettings.matches(condition,context:context),"Exact percentage")
        condition.path="/Other/*";check(!ViewModeSettings.matches(condition,context:context),"File rule path constraint")
        let ftp=CommanderViewCondition(kind:.ftp),local=CommanderViewCondition(kind:.local)
        var rule=CommanderAutoSwitchRule(viewModeID:"photos",conditions:[ftp,local,CommanderViewCondition(kind:.path,value:"/Other",conjunction:.all)])
        rule.conditions[1].conjunction = .any
        check(!ViewModeSettings.matches(rule,context:context),"AND precedence: false OR true AND false")
        rule.conditions[2].value="/Pictures/*";check(ViewModeSettings.matches(rule,context:context),"Mixed expression")
        var disabled=rule;disabled.enabled=false
        check(ViewModeSettings.matchingModeID(rules:[disabled,rule],context:context)=="photos","First enabled match")
        check(!ViewModeSettings.matches(CommanderViewCondition(kind:.fileMask,value:"*",fileMatch:.all),context:.init(kind:.local,path:"/Empty",fileNames:[])),"Empty folder does not vacuously match all types")
        let commands=try ViewModeSettings.commands("-*cm_SrcShort,cm_SrcBySize|cm_SrcLong")
        check(commands.skipTab && commands.everyDirectory && commands.enter.count==2 && commands.leave==["cm_srclong"],"Auto-command modifiers and phases")
        do {_=try ViewModeSettings.commands("cm_Delete");check(false,"Unsafe automatic command rejected")}catch{check(true,"Unsafe automatic command rejected")}
        let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("view-modes-"+UUID().uuidString)
        try fm.createDirectory(at:root,withIntermediateDirectories:false);defer{try? fm.removeItem(at:root)}
        let pictures=root.appendingPathComponent("Pictures"),other=root.appendingPathComponent("Other")
        try fm.createDirectory(at:pictures,withIntermediateDirectories:false);try fm.createDirectory(at:other,withIntermediateDirectories:false)
        try Data("a".utf8).write(to:pictures.appendingPathComponent("a.jpg"));try Data("bbbb".utf8).write(to:pictures.appendingPathComponent("b.jpg"));try Data("xx".utf8).write(to:pictures.appendingPathComponent("c.txt"))
        let c=CommanderController(initial:root,remember:false),p=c.left
        var mode=CommanderViewMode(id:"photos",name:"Photos",columnsView:.brief,sortColumn:"ext",ascending:true,secondarySortColumns:["-size"],background:.init(red:0.9,green:0.95,blue:1))
        var config=c.runtimeConfig;config.viewModes=[mode];config.autoSwitchEnabled=true;config.autoSwitchRestoreDefault=true
        config.autoSwitchRules=[CommanderAutoSwitchRule(name:"Pictures",viewModeID:"photos",conditions:[CommanderViewCondition(kind:.path,value:pictures.path)])]
        try ViewModeSettings.validate(modes:config.viewModes,rules:config.autoSwitchRules,customColumnSets:[])
        c.applyConfiguration(config);check(p.currentNamedViewModeID==nil,"No initial match")
        c.navigate(pictures);check(p.viewMode == .brief && p.currentNamedViewModeID=="photos" && p.namedViewIsAutomatic,"Successful navigation applies matching mode")
        check(p.entries.map(\.name)==["b.jpg","a.jpg","c.txt"],"Primary extension and secondary descending size")
        check(p.configuration.background==mode.background,"Pane color override")
        check(c.right.currentNamedViewModeID==nil && c.right.configuration.background==config.background,"Other pane unaffected")
        c.navigate(other);check(p.viewMode == .full && p.currentNamedViewModeID==nil && p.configuration.background==config.background,"Leaving matching directory restores previous default")
        check(c.applyNamedViewMode(id:"photos"),"Manual mode selection succeeds")
        check(p.viewMode == .brief && !p.namedViewIsAutomatic,"Manual choice not automatic")
        check(c.applyNamedViewMode(id:"default") && p.viewMode == .full,"Manual default restores original baseline")
        mode.autoRunCommands="*cm_SrcBySize|cm_SrcByName";config.viewModes=[mode];c.applyConfiguration(config);c.navigate(pictures)
        check(p.sortColumn=="size","Enter command dispatches native sort")
        c.navigate(other);check(p.sortColumn=="name","Leave/default restores native sort")
        c.navigate(pictures);config.autoSwitchEnabled=false;c.applyConfiguration(config)
        check(!p.namedViewIsAutomatic && p.viewMode == .full,"Disable auto switching restores manual baseline")
        check(c.dispatchInternalCommand("cm_SrcViewMode1"),"Original named-mode command dispatches")
        check(p.currentNamedViewModeID=="photos","Original mode1 selects first named mode")
        check(c.dispatchInternalCommand("cm_SrcViewMode0") && p.currentNamedViewModeID==nil,"Original default command restores default")
        config.autoSwitchEnabled=true;c.applyConfiguration(config);c.navigate(pictures)
        p.setBriefMode(false);c.finishRestoringNamedViewModes()
        check(p.viewMode == .brief && p.currentNamedViewModeID=="photos","Automatic mode survives final startup layout restoration")
        c.navigate(other,pane:c.right);c.swapPaneTabs()
        let deadline=Date().addingTimeInterval(5)
        while c.busy,Date()<deadline {RunLoop.current.run(until:Date().addingTimeInterval(0.01))}
        check(!c.busy && c.right.currentNamedViewModeID=="photos" && c.left.currentNamedViewModeID==nil,"Pane swap reevaluates directory rules on both panes")
        c.navigate(pictures,pane:p)
        let width=p.tabControl.width(forSegment:0);p.decorateNamedViewTab();p.decorateNamedViewTab()
        check(p.tabControl.width(forSegment:0)==width,"Repeated tab decoration does not grow width")
        let firstColumn=CustomColumnDefinition(id:"first-size",title:"Size",expression:"[=tc.size]"),secondColumn=CustomColumnDefinition(id:"second-name",title:"Name",expression:"[=tc.name]")
        let firstSet=CustomColumnSet(id:"first",name:"First",columns:[firstColumn]),secondSet=CustomColumnSet(id:"second",name:"Second",columns:[secondColumn])
        var invalidSort=mode;invalidSort.customColumnSetID="first";invalidSort.sortColumn="custom.second-name"
        do {try ViewModeSettings.validate(modes:[invalidSort],rules:[],customColumnSets:[firstSet,secondSet]);check(false,"Cross-set sort rejected")}catch{check(true,"Cross-set sort rejected")}
        config.autoSwitchEnabled=false;config.customColumnSets=[firstSet,secondSet];c.applyConfiguration(config)
        check(c.dispatchInternalCommand("cm_SrcCustomView1") && p.configuration.activeCustomColumnSetID=="first","Custom column command selects set")
        c.applyConfiguration(config)
        check(p.configuration.activeCustomColumnSetID=="first","Configuration Apply preserves manual custom-column choice")
        c.fullView();check(p.configuration.activeCustomColumnSetID.isEmpty,"Full view clears custom columns")
        let selected=Set(p.entries.prefix(1).map(\.url));p.selectedOnly=selected
        var filtered=mode;filtered.id="filtered";filtered.name="Filtered";filtered.fileMask="*.jpg";config.viewModes=[filtered];c.applyConfiguration(config)
        c.recordManualViewChange(in:p);_=c.applyNamedViewMode(id:"filtered")
        check(p.selectedOnly==nil,"Mode filter overrides selected-only filter")
        _=c.applyNamedViewMode(id:"default");check(p.selectedOnly==selected,"Default restores selected-only filter")
        let persisted=try JSONDecoder().decode(CommanderViewMode.self,from:JSONEncoder().encode(mode));check(persisted==mode,"Named mode codable roundtrip")
        var broken=config.autoSwitchRules;broken[0].viewModeID="missing"
        do {try ViewModeSettings.validate(modes:[mode],rules:broken,customColumnSets:[]);check(false,"Dangling mode reference rejected")}catch{check(true,"Dangling mode reference rejected")}
        var bad=mode;bad.customColumnSetID="missing"
        do {try ViewModeSettings.validate(modes:[bad],rules:[],customColumnSets:[]);check(false,"Dangling column reference rejected")}catch{check(true,"Dangling column reference rejected")}
        print("PASS: \(checks) view-mode and automatic-switch assertions")
    }
}
