import Foundation
import Darwin

@main struct ConfigurationFilesTests {
    static func main()throws {
        var count=0
        func check(_ condition:Bool,_ message:String)throws {guard condition else{throw ConfigurationFileError.invalid(message)};count+=1}
        func rejects(_ data:Data,_ message:String)throws {do{_=try ConfigurationFiles.importNative(data);throw NSError(domain:"TestFailure",code:1,userInfo:[NSLocalizedDescriptionKey:message])}catch let e as NSError{if e.domain=="TestFailure"{throw e};count+=1}}
        var configuration=CommanderConfiguration();configuration.sizeFormat = .gigabytes;configuration.fileFontBold=true;configuration.ignorePatterns="*.tmp\ncache";configuration.footerSizeFormat = .dynamicOneDecimal;configuration.visibleColumns=["name","size"];configuration.externalEditorPath="/Applications/TextEdit.app";configuration.externalEditorEnabled=true
        let data=try ConfigurationFiles.exportNative(configuration)
        try check(try ConfigurationFiles.importNative(data)==configuration,"All native settings round trip")
        try check(try ConfigurationFiles.importNative(ConfigurationFiles.exportNative(CommanderConfiguration()))==CommanderConfiguration(),"Default omitted optional field round trip")
        var display=configuration
        let column=CustomColumnDefinition(id:"size-column",title:"Size",expression:"[=tc.size.mbytes]",width:100,alignment:.right)
        display.customColumnSets=[CustomColumnSet(id:"media",name:"Media",columns:[column])];display.activeCustomColumnSetID="media"
        var mode=CommanderViewMode();mode.id="media-mode";mode.name="Media";mode.columnsView = .full;mode.customColumnSetID="media";mode.sortColumn="custom.size-column"
        var condition=CommanderViewCondition();condition.kind = .fileMask;condition.value="*.jpg";condition.fileMatch = .half
        var rule=CommanderAutoSwitchRule();rule.id="media-rule";rule.name="Images";rule.viewModeID=mode.id;rule.conditions=[condition]
        display.viewModes=[mode];display.autoSwitchRules=[rule];display.autoSwitchEnabled=true
        try check(try ConfigurationFiles.importNative(ConfigurationFiles.exportNative(display))==display,"Nested columns, modes and rules round trip")
        var invalidDisplay=try JSONSerialization.jsonObject(with:ConfigurationFiles.exportNative(display)) as! [String:Any]
        var invalidFields=invalidDisplay["configuration"] as! [String:Any];invalidFields["customColumnSets"]=[];invalidDisplay["configuration"]=invalidFields
        try rejects(JSONSerialization.data(withJSONObject:invalidDisplay),"Dangling custom-column reference rejected")
        let object=try JSONSerialization.jsonObject(with:data) as! [String:Any]
        func changed(_ action:(inout [String:Any])->Void)throws->Data {var copy=object;action(&copy);return try JSONSerialization.data(withJSONObject:copy)}
        try rejects(Data(),"Empty rejected")
        try rejects(Data(repeating:65,count:ConfigurationFiles.maximumBytes+1),"Oversized rejected")
        try rejects(Data("not json".utf8),"Malformed rejected")
        try rejects(Data(String(decoding:data,as:UTF8.self).replacingOccurrences(of:"\"version\" : 5",with:"\"version\" : 5, \"version\" : 5").utf8),"Duplicate JSON keys rejected")
        try rejects(changed{$0["version"]=6},"Future version rejected")
        try rejects(changed{$0["version"]=true},"Boolean version rejected")
        try rejects(changed{$0["format"]="other"},"Wrong format rejected")
        try rejects(changed{$0["extra"]=true},"Unknown envelope rejected")
        for mutation in 0..<6 {
            let bad=try changed {o in var c=o["configuration"] as! [String:Any]
                switch mutation {
                case 0:c.removeValue(forKey:"showButtonBar")
                case 1:c["sizeFormat"]="nonsense"
                case 2:c["fileFontSize"]=999
                case 3:c["showButtonBar"]=1
                case 4:c["newFutureSetting"]=true
                default:c["visibleColumns"]=["name","unknown"]
                };o["configuration"]=c
            }
            try rejects(bad,"Invalid field mutation \(mutation) rejected")
        }
        var base=CommanderConfiguration();base.background = .init(red:0.2,green:0.3,blue:0.4);base.externalEditorPath="keep.app";base.fileFontSize=13
        let styles:[CommanderConfiguration.SizeFormat]=[.bytes,.kilobytes,.dynamicGigabytes,.dynamicOneDecimalGigabytes,.dynamicMegabytes,.dynamicOneDecimalMegabytes,.dynamic,.dynamicOneDecimal,.dynamicTwoDecimalsGigabytes,.dynamicTwoDecimals]
        for (index,style) in styles.enumerated() {
            let r=try ConfigurationFiles.importINI(Data("[Configuration]\r\nSizeStyle=\(index)\r\nSizeFooter=\(index)\r\nSizeStyle1000=1".utf8),merging:base)
            try check(r.configuration.sizeFormat==style && r.configuration.footerSizeFormat==style && r.configuration.useDecimalUnits && r.imported.count==3,"Style \(index) maps exactly")
        }
        let ini="""
        ; source fixture
        [Layout]
        ButtonBar=0
        CmdLine=0
        CurDir=0
        DirectoryTabs=0
        DriveCombo=0
        KeyButtons=0
        StatusBar=0
        TabHeader=0
        [Configuration]
        ShowHiddenSystem=2
        ShowIcons=1
        DirTabLimit=48
        DirTabOptions=129
        QuickSearchMatchBeginning=0
        QuickSearchExactMatch=1
        Editor=C:\\unsafe.exe
        RedirectSection=other.ini
        Password=do-not-print-this
        [AllResolutions]
        FontName=Menlo
        FontSize=18
        FontWeight=700
        [Shortcuts]
        C+R=cm_delete
        """
        let r=try ConfigurationFiles.importINI(Data(ini.utf8),merging:base),c=r.configuration
        try check(!c.showButtonBar && !c.showCommandLine && !c.showCurrentDirectory && !c.showFolderTabs && !c.showDriveList && !c.showFunctionButtons && !c.showStatusBar && !c.showColumnHeaders,"Eight layout switches")
        try check(c.showHidden && c.iconMode == .standard,"Hidden and icons map")
        try check(c.tabTitleMaximum==48 && c.tabsAlwaysVisible && c.newTabBesideCurrent,"Supported tab flags map")
        try check(!c.quickSearchMatchBeginning && c.quickSearchMatchEnding,"Quicksearch flags map")
        try check(c.fileFontName=="Menlo" && c.fileFontSize==18 && c.fileFontBold,"AllResolutions font settings map")
        try check(c.background==base.background && c.externalEditorPath=="keep.app","Unspecified settings and commands preserved")
        try check(r.unsupported.count==4 && r.invalid.isEmpty,"Unsafe and unsupported entries reported")
        try check(!r.unsupported.joined().contains("do-not-print-this") && !r.unsupported.joined().contains("unsafe.exe"),"Report excludes raw values")
        let invalid=try ConfigurationFiles.importINI(Data("[Configuration]\nSizeStyle=99\nSizeStyle1000=no\nShowHiddenSystem=3\nDirTabLimit=1\n[AllResolutions]\nFontSize=8\nFontWeight=600".utf8),merging:base)
        try check(invalid.invalid.count==6 && invalid.configuration==base,"Invalid/unsupported values do not replace current settings")
        let duplicate=try ConfigurationFiles.importINI(Data("[CONFIGURATION]\nSizeStyle=2\nsizestyle=3".utf8),merging:base)
        try check(duplicate.invalid.count==1 && duplicate.configuration==base,"Case-insensitive duplicates rejected")
        let utf16=try ConfigurationFiles.importINI(ini.data(using:.utf16)!,merging:base)
        try check(utf16.configuration==r.configuration,"UTF16 BOM supported")
        let unknown=try ConfigurationFiles.importINI(Data("[1024x768 (10x20)]\nFontSize=18\n[Unknown]\nThing=1".utf8),merging:base)
        try check(unknown.unsupported.count==2 && unknown.configuration==base,"Resolution-specific and unknown sections not guessed")
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("configuration-files-"+UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        let file=root.appendingPathComponent("settings.json")
        try ConfigurationFiles.writeNative(configuration,to:file)
        try check(try ConfigurationFiles.readNative(from:file)==configuration,"Atomic export readable")
        try ConfigurationFiles.writeNative(base,to:file)
        try check(try ConfigurationFiles.readNative(from:file)==base,"Atomic replacement readable")
        let link=root.appendingPathComponent("link.json");try FileManager.default.createSymbolicLink(at:link,withDestinationURL:file)
        do{_=try ConfigurationFiles.readNative(from:link);throw NSError(domain:"TestFailure",code:1)}catch let e as NSError{if e.domain=="TestFailure"{throw e};count+=1}
        let fifo=root.appendingPathComponent("pipe");guard mkfifo(fifo.path,0o600)==0 else{throw ConfigurationFileError.invalid("FIFO fixture")}
        let huge=root.appendingPathComponent("huge");try Data(repeating:65,count:ConfigurationFiles.maximumBytes+1).write(to:huge)
        for rejected in [fifo,root,huge] {
            do{_=try ConfigurationFiles.readData(from:rejected);throw NSError(domain:"TestFailure",code:1)}catch let e as NSError{if e.domain=="TestFailure"{throw e};count+=1}
        }
        var version4=object;version4["version"]=4
        var v4Fields=version4["configuration"] as! [String:Any]
        for key in ConfigurationFiles.version5Keys {v4Fields.removeValue(forKey:key)}
        version4["configuration"]=v4Fields
        let migratedV4=try ConfigurationFiles.importNative(JSONSerialization.data(withJSONObject:version4))
        try check(migratedV4.directoryBrackets && !migratedV4.historySaveOnExit && migratedV4.sortMethod == .naturalAlphabetical,"Version 4 keeps baseline display and history defaults")
        var version3=object;version3["version"]=3
        var v3Fields=version3["configuration"] as! [String:Any]
        for key in ConfigurationFiles.version4Keys.union(ConfigurationFiles.version5Keys) {v3Fields.removeValue(forKey:key)}
        version3["configuration"]=v3Fields
        let migrated3=try ConfigurationFiles.importNative(JSONSerialization.data(withJSONObject:version3))
        try check(migrated3==configuration,"Version 3 migrates appearance and tab defaults without altering existing preferences")
        var version2=object;version2["version"]=2
        var previousFields=version2["configuration"] as! [String:Any]
        for key in ConfigurationFiles.version3Keys.union(ConfigurationFiles.version4Keys).union(ConfigurationFiles.version5Keys) {previousFields.removeValue(forKey:key)}
        version2["configuration"]=previousFields
        let migrated2=try ConfigurationFiles.importNative(JSONSerialization.data(withJSONObject:version2))
        try check(migrated2==configuration,"Version 2 migrates with empty display profiles and preserves existing settings")
        version2["configuration"]=[:]
        try rejects(JSONSerialization.data(withJSONObject:version2),"Version 2 missing existing settings rejected")
        var version1=object;version1["version"]=1
        var legacyFields=version1["configuration"] as! [String:Any]
        for key in ConfigurationFiles.version2Keys.union(ConfigurationFiles.version3Keys).union(ConfigurationFiles.version4Keys).union(ConfigurationFiles.version5Keys) {legacyFields.removeValue(forKey:key)}
        version1["configuration"]=legacyFields
        let migrated=try ConfigurationFiles.importNative(JSONSerialization.data(withJSONObject:version1))
        try check(migrated.sizeFormat == configuration.sizeFormat && migrated.copyVerifyAfterCopy==false && migrated.zipCompressionLevel==6,"Version 1 exports migrate with new defaults and retain existing fields")
        version1["configuration"]=[:]
        try rejects(JSONSerialization.data(withJSONObject:version1),"Version 1 still rejects missing original settings")
        let extendedINI=Data("[Configuration]\nUseTrash=0\nVerifyCopy=1\nCopyDirTimeStamp=0\nCopyBlockSize=512\nWatchDirs=59\nCustomSeparators=-:00\n[Packer]\nInternalZipRate=9\nVerifyZIP=0\nZipSetDateToNewest=1\n".utf8)
        let extended=try ConfigurationFiles.importINI(extendedINI,merging:CommanderConfiguration())
        try check(!extended.configuration.deleteToTrash && extended.configuration.copyVerifyAfterCopy && !extended.configuration.copyPreserveDirectoryDates && extended.configuration.copyBufferSizeKB==512,"Original copy/delete INI keys map to working policies")
        try check(extended.configuration.autoRefreshEnabled && extended.configuration.autoRefreshMetadata && extended.configuration.autoRefreshOnlyForeground && extended.configuration.autoRefreshUpdateHeader,"Supported WatchDirs flags map independently")
        try check(extended.configuration.zipCompressionLevel==9 && !extended.configuration.zipVerifyAfterPacking && extended.configuration.archiveSetDateToNewest,"Original packer keys map to ZIP policy")
        try check(extended.configuration.dateSeparator=="-" && extended.configuration.timeSeparator==":" && extended.invalid.isEmpty && extended.unsupported.isEmpty,"Custom date/time separators import without guessing numeric formatting")
        var expanded=configuration;expanded.copyVerifyAfterCopy=true;expanded.copyDefaultCollision="rename";expanded.autoRefreshEnabled=true;expanded.ftpOpenPanel=3;expanded.zipCompressionLevel=0;expanded.customShortcuts="Ctrl+Shift+C=cm_CopyFullNamesToClip";expanded.commandAliases="full=cm_SrcLong"
        try check(try ConfigurationFiles.importNative(ConfigurationFiles.exportNative(expanded))==expanded,"Expanded settings roundtrip strictly")
        try rejects(changed{o in var fields=o["configuration"] as! [String:Any];fields["copyBufferSizeKB"]=1;o["configuration"]=fields},"Copy buffer bounds enforced on JSON import")
        try rejects(changed{o in var fields=o["configuration"] as! [String:Any];fields["zipCompressionLevel"]=10;o["configuration"]=fields},"ZIP compression bounds enforced on import")
        try rejects(changed{o in var fields=o["configuration"] as! [String:Any];fields["customShortcuts"]="bad-binding";o["configuration"]=fields},"Invalid hotkey syntax cannot enter through JSON")
        var policies=configuration;policies.directoryBrackets=false;policies.directoryTrailingSlash=true;policies.showDirectoryCount=true;policies.directoriesAlwaysByName=true;policies.sortMethod = .naturalCharacterCode;policies.briefColumnWidthLimit=180;policies.historySaveOnExit=true;policies.historyMaximumShown=12;policies.historyShowIcons=true
        try check(try ConfigurationFiles.importNative(ConfigurationFiles.exportNative(policies))==policies,"New display/history settings round trip without loss")
        for (key,value) in [("briefColumnWidthLimit",1201),("historyMaximumShown",0)] {try rejects(changed{o in var fields=o["configuration"] as! [String:Any];fields[key]=value;o["configuration"]=fields},"New numeric bounds enforced: \(key)")}
        try rejects(changed{o in var fields=o["configuration"] as! [String:Any];fields["sortMethod"]="unknown";o["configuration"]=fields},"Unknown sort method rejected")
        let policyINI=try ConfigurationFiles.importINI(Data("[Configuration]\nDirBrackets=3\nDirsInFooter=1\nSortDirsByName=1\nSaveHistory=1\nHistoryIcons=1\n".utf8),merging:CommanderConfiguration())
        try check(policyINI.configuration.directoryBrackets && policyINI.configuration.directoryTrailingSlash && policyINI.configuration.showDirectoryCount && policyINI.configuration.directoriesAlwaysByName && policyINI.configuration.historySaveOnExit && policyINI.configuration.historyShowIcons,"Original display/history INI keys map to policies")
        try check(policyINI.unsupported.count==1 && policyINI.invalid.isEmpty,"Native separator adaptation explicitly reported")
        print("Configuration file tests passed: \(count) assertions")
    }
}
