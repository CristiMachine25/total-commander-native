import Foundation
@main struct OriginalDisplayINITests {
    static func main()throws {
        var checks=0
        func check(_ value:Bool,_ label:String){precondition(value,label);checks += 1}
        let nativeSet=CustomColumnSet(id:"native",name:"Existing",columns:[.init(id:"native.size",title:"Size",expression:"[=tc.size]")])
        var base=CommanderConfiguration();base.customColumnSets=[nativeSet];base.activeCustomColumnSetID="native"
        let fixture="""
        [CustomFields]
        Titles=Size and date
        Widths1=80,30,-80,120
        Headers1=Bytes\\nModified
        Contents1=[=tc.size.bytes]\\n[=tc.writedate.Y-M-D]
        Options1=1000|1|96
        AutoLoad=0
        [ViewModes]
        0_name=<Default>
        0_options=1|0|0||-1|-1|-1|-1|-1
        1_name=Archive detail
        1_options=6|100|1|-2,1|255|16777215|15790320|0|2105376
        1_icon=shell32.dll,1
        1_commands=cm_SrcLong
        [ViewModeSwitch]
        Enabled=1
        0_rules=A||F
        0_mode=1
        1_rules=L|&+/tmp/ImportDemo/*
        1_mode=1
        """
        func run(_ text:String,_ config:CommanderConfiguration?=nil)throws->ConfigurationImportReport {try ConfigurationFiles.importINI(Data(text.utf8),merging:config ?? base)}
        let imported=try run(fixture),config=imported.configuration
        check(imported.invalid.isEmpty,"Valid fixture imported")
        check(config.customColumnSets.count==2 && config.customColumnSets[0]==nativeSet,"Native sets preserved")
        check(config.activeCustomColumnSetID=="native","Active pane selection retained")
        let custom=config.customColumnSets[1]
        check(custom.id=="ini.custom.1" && custom.name=="Size and date","Stable original set identity")
        check(custom.columns.count==2 && custom.columns[0].alignment == .right,"Signed widths and fields")
        check(custom.columns[1].expression=="[=tc.writedate.Y-M-D]","Original literal newline delimiter")
        check(custom.adjustNameWidth && custom.horizontalScroll,"Sizing flags")
        let mode=config.viewModes[1]
        check(mode.customColumnSetID==custom.id && mode.sortColumn=="custom.ini.column.1.1","Custom references preserved")
        check(mode.ascending==false && mode.secondarySortColumns==["-ext","name"],"Reversed and secondary sort")
        check(mode.tabColor==ConfigurationColor(red:1,green:0,blue:0),"Windows COLORREF red")
        check(mode.background == .white && mode.darkBackground == .black,"Normal and dark colors")
        check(config.viewModes[0].id=="default" && config.viewModes[0].columnsView == .full,"Original default mode")
        check(mode.tabIcon.isEmpty && imported.unsupported.contains{$0.contains("Windows icon")},"DLL icon reported, never opened")
        check(config.autoSwitchRules.count==2 && config.autoSwitchEnabled,"Rules and enabled flag")
        check(config.autoSwitchRules[0].conditions[1].conjunction == .any,"OR connector")
        check(config.autoSwitchRules[1].conditions[1].conjunction == .all,"AND connector")
        check(ViewModeSettings.matchingModeID(rules:config.autoSwitchRules,context:.init(kind:.archive,path:"a.zip!/",fileNames:[]))==mode.id,"Imported archive rule runs")
        check(ViewModeSettings.matchingModeID(rules:config.autoSwitchRules,context:.init(kind:.local,path:"/tmp/ImportDemo/child",fileNames:[]))==mode.id,"Native path translation runs")
        check(try run(fixture,config).configuration==config,"Reimport is idempotent")
        for broken in [fixture.replacingOccurrences(of:"Headers1=Bytes\\nModified",with:"Headers1=Only"),fixture.replacingOccurrences(of:"0_mode=1",with:"0_mode=99"),fixture+"\n[ViewModes]\n1_name=Duplicate",fixture.replacingOccurrences(of:"[=tc.size.bytes]",with:"[=plugin.secret]"),fixture.replacingOccurrences(of:"+/tmp/ImportDemo/*",with:"+C:\\Secret\\*"),fixture.replacingOccurrences(of:"1_options=6|100",with:"1_options=6|120"),fixture.replacingOccurrences(of:"1_commands=cm_SrcLong",with:"1_commands=em_ShellCommand"),fixture.replacingOccurrences(of:"Options1=1000|1|96",with:"Options1=oops|1|96"),fixture.replacingOccurrences(of:"Widths1=80,30,-80,120",with:"Widths1=80,30,0,120")] {
            let bad=try run(broken);check(!bad.invalid.isEmpty && bad.configuration==base && bad.imported.isEmpty,"Invalid linked group preserves all native profiles")
        }
        let partial=try run("[Configuration]\nSizeStyle=1\n"+fixture.replacingOccurrences(of:"0_mode=1",with:"0_mode=99"))
        check(partial.configuration.sizeFormat == .kilobytes && partial.configuration.customColumnSets==base.customColumnSets,"Unrelated scalar import independent of linked rollback")
        let unsupported=try run("[CustomFields_Plugin]\nTitles=Registry\n[AutoSwitchMode]\nEnabled=1")
        check(unsupported.configuration==base && unsupported.unsupported.count==2,"Unsupported sections reported")
        let missing=try run("[ViewModeSwitch]\n0_rules=A\n0_mode=1")
        check(!missing.invalid.isEmpty && missing.configuration==base,"Missing external mode rejected")
        let redirected=try run("[CustomFields]\nRedirectSection=/tmp/other.ini")
        check(!redirected.invalid.isEmpty && redirected.configuration==base,"Redirect not followed")
        let malformed=try run(fixture+"\n[Broken section\n1_name=Orphan")
        check(!malformed.invalid.isEmpty && malformed.configuration==base,"Malformed syntax rolls back linked profiles")
        let smallerRules=try run("[ViewModeSwitch]\nEnabled=1\n0_rules=F\n0_mode=1",config)
        check(smallerRules.invalid.isEmpty && smallerRules.configuration.autoSwitchRules.count==1,"Shrinking rule section removes prior imported rules")
        check(ViewModeSettings.matchingModeID(rules:smallerRules.configuration.autoSwitchRules,context:.init(kind:.local,path:"/tmp/ImportDemo/child",fileNames:[]))==nil,"Removed rule no longer matches")
        check(smallerRules.configuration.customColumnSets==config.customColumnSets && smallerRules.configuration.viewModes==config.viewModes,"Absent sections retained")
        let extra=fixture.replacingOccurrences(of:"Titles=Size and date",with:"Titles=Size and date|Extra").replacingOccurrences(of:"AutoLoad=0",with:"AutoLoad=0\nWidths2=80,30,80\nHeaders2=Name\nContents2=[=tc.name]\nOptions2=-1|0|96").replacingOccurrences(of:"[ViewModeSwitch]",with:"2_name=Extra mode\n2_options=1|0|0||-1|-1|-1\n[ViewModeSwitch]")
        let larger=try run(extra).configuration
        check(larger.customColumnSets.count==3 && larger.viewModes.count==3,"Expanded fixture imports")
        let shrunk=try run(fixture,larger)
        check(shrunk.invalid.isEmpty && shrunk.configuration==config,"Shrinking linked sets and modes removes old imported namespace")
        var referenced=larger
        var nativeRule=CommanderAutoSwitchRule();nativeRule.id="native.rule";nativeRule.name="Native dependent";nativeRule.viewModeID="ini.mode.2";nativeRule.conditions=[.init(kind:.ftp)]
        referenced.autoSwitchRules.append(nativeRule)
        let rejected=try run(fixture,referenced)
        check(!rejected.invalid.isEmpty && rejected.configuration==referenced,"Native cross-reference prevents destructive namespace shrink")
        let clearedRules=try run("[ViewModeSwitch]\nEnabled=0",config)
        check(clearedRules.invalid.isEmpty && clearedRules.configuration.autoSwitchRules.isEmpty && !clearedRules.configuration.autoSwitchEnabled,"Empty rule section clears prior imported rules")
        var orphanFree=config;orphanFree.autoSwitchRules=[];orphanFree.viewModes=[]
        let clearedSets=try run("[CustomFields]\nTitles=",orphanFree)
        check(clearedSets.invalid.isEmpty && clearedSets.configuration.customColumnSets==base.customColumnSets,"Empty titles clears only imported custom sets")
        let emptyModeSection=OriginalDisplayINI.importEntries([],duplicates:[],merging:clearedRules.configuration,sections:["viewmodes"])
        check(emptyModeSection.invalid.isEmpty && emptyModeSection.configuration.viewModes.map(\.id)==["default"],"Empty mode section removes imported namespace but preserves shared default")
        check(imported.unsupported.contains{$0.contains("drive-letter and UNC")},"Local provider semantic translation reported")
        let redirectedModes=try run("[ViewModes]\nRedirectSection=/tmp/do-not-read.ini",config)
        check(!redirectedModes.invalid.isEmpty && redirectedModes.configuration==config,"Redirect cannot erase imported modes")
        let emptyThroughParser=try run("[ViewModes]\n[ViewModeSwitch]\nEnabled=0",config)
        check(emptyThroughParser.invalid.isEmpty && emptyThroughParser.configuration.viewModes.map(\.id)==["default"] && emptyThroughParser.configuration.autoSwitchRules.isEmpty,"Empty section presence reaches profile transaction")
        print("PASS: \(checks) original display INI assertions")
    }
}
