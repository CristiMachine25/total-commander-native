import Foundation

@main struct ConfigurationTests {
    static var checks=0
    static func check(_ value:@autoclosure ()throws->Bool,_ message:String)throws{checks += 1;if try !value(){throw NSError(domain:"ConfigurationTests",code:checks,userInfo:[NSLocalizedDescriptionKey:message])}}
    static func main()throws{
        let suite="configuration-tests-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
        defer{defaults.removePersistentDomain(forName:suite)}
        var config=CommanderConfiguration.load(defaults:defaults)
        try check(config.sizeFormat == .bytes && !config.tabsAlwaysVisible && config.iconSize==16,"Native baseline and source-documented bytes/single-tab defaults")
        defaults.set(18,forKey:"fileFontSize");defaults.set(29,forKey:"fileRowHeight");defaults.set(true,forKey:"showHidden");defaults.set("/Applications/TextEdit.app",forKey:"externalEditor")
        config=CommanderConfiguration.load(defaults:defaults)
        try check(config.fileFontSize==18 && config.rowHeight==29 && config.showHidden && config.externalEditorEnabled && config.externalEditorPath=="/Applications/TextEdit.app","Legacy four-field settings migrate without losing values")
        config.showButtonBar=false;config.verticalArrangement=true;config.iconMode = .none;config.fileFontBold=true;config.foreground = .init(red:0.1,green:0.2,blue:0.3)
        config.visibleColumns=["name","size"];config.columnWidths["size"]=140;config.sizeFormat = .gigabytes;config.dateOrder = .yearFirst
        config.newTabBesideCurrent=true;config.saveOnExit=false;config.singleClickOpen=true;config.historyLimit=42;config.thumbnailSize=192
        config.footerSizeFormat = .dynamicOneDecimal;config.ignoreListEnabled=true;config.ignorePatterns="*.bak;*.tmp";config.quickSearchMode = .alt;config.quickSearchMatchBeginning=false;config.quickSearchMatchEnding=true
        config.externalViewerEnabled=true;config.externalViewerPath="/Applications/Preview.app";config.viewerFontName="Helvetica";config.viewerFontSize=18;config.viewerWordWrap=true
        try config.save(defaults:defaults)
        try check(CommanderConfiguration.load(defaults:defaults)==config.normalized(),"All typed settings survive durable UserDefaults JSON roundtrip")
        defaults.set(9,forKey:"fileFontSize")
        try check(CommanderConfiguration.load(defaults:defaults).fileFontSize==18,"Typed schema takes precedence over stale legacy keys")
        config.externalEditorEnabled=false;try config.save(defaults:defaults)
        try check(defaults.string(forKey:"externalEditor")=="" && CommanderConfiguration.load(defaults:defaults).externalEditorPath=="/Applications/TextEdit.app","Disabling editor clears active legacy launch path without forgetting configured app")
        defaults.set(Data(#"{"showHidden":true,"sizeFormat":"future-format","fileFontSize":"bad","thumbnailSize":160}"#.utf8),forKey:CommanderConfiguration.defaultsKey)
        let partial=CommanderConfiguration.load(defaults:defaults)
        try check(partial.showHidden && partial.sizeFormat == .bytes && partial.fileFontSize==13 && partial.thumbnailSize==160,"Partial/invalid typed fields recover individually without dropping valid settings")
        defaults.set(Data("not json".utf8),forKey:CommanderConfiguration.defaultsKey)
        try check(CommanderConfiguration.load(defaults:defaults).fileFontSize==18,"Malformed schema safely recovers legacy values")
        var invalid=CommanderConfiguration();invalid.fileFontSize = .infinity;invalid.rowHeight = -100;invalid.iconSize=999;invalid.thumbnailSize=0;invalid.historyLimit=1000;invalid.tabTitleMaximum=0
        invalid.visibleColumns=["../fake","size","size"];invalid.columnWidths=["size":99999,"date":Double.nan];invalid.foreground = .init(red:-1,green:2,blue:.nan)
        let safe=invalid.normalized()
        try check(safe.fileFontSize==13 && safe.rowHeight==16 && safe.iconSize==48 && safe.thumbnailSize==64 && safe.historyLimit==200 && safe.tabTitleMaximum==8,"Numeric constraints reject NaN/infinity and clamp imported invalid ranges")
        try check(safe.visibleColumns==["name","size"] && safe.columnWidths["size"]==1200 && safe.columnWidths["date"]==80 && safe.columnWidths.count==5,"Column model retains mandatory name, drops unknown keys and bounds widths")
        try check(safe.foreground==ConfigurationColor(red:0,green:1,blue:0),"Color components normalized to finite RGB range")
        let locale=Locale(identifier:"en_US_POSIX")
        var format=CommanderConfiguration()
        try check(format.sizeString(1_048_576,locale:locale)=="1,048,576" && format.sizeString(-1,locale:locale)=="0","Bytes retain exact integral counts and invalid negative sizes do not display negative")
        format.sizeFormat = .kilobytes
        try check(format.sizeString(1024,locale:locale)=="1 k","Fixed kbytes uses original binary1024 convention")
        format.sizeFormat = .megabytes
        try check(format.sizeString(1_572_864,locale:locale)=="1.5 MB","Fixed native MB choice shows fractional megabytes")
        format.sizeFormat = .gigabytes
        try check(format.sizeString(1_610_612_736,locale:locale)=="1.5 GB","Fixed native GB choice shows fractional gigabytes")
        format.sizeFormat = .dynamic
        try check(format.sizeString(1023,locale:locale)=="1,023" && format.sizeString(1024,locale:locale)=="1 k","Dynamic units switch at actual1024 boundary")
        try check(format.sizeString(1_048_576,locale:locale)=="1 M" && format.sizeString(1_073_741_824,locale:locale)=="1 G" && format.sizeString(1_099_511_627_776,locale:locale)=="1 T","Dynamic M/G/T binary boundaries")
        format.sizeFormat = .dynamicOneDecimal
        try check(format.sizeString(1_572_864,locale:locale)=="1.5 M","Original one-decimal dynamic format")
        format.sizeFormat = .dynamicTwoDecimals
        try check(format.sizeString(1_310_720,locale:locale)=="1.25 M","Original two-decimal dynamic format")
        format.sizeFormat = .dynamicGigabytes
        try check(format.sizeString(1_099_511_627_776,locale:locale)=="1,024 G","Original k/M/G variant caps units at G")
        format.sizeFormat = .dynamicMegabytes
        try check(format.sizeString(1_073_741_824,locale:locale)=="1,024 M","Original k/M variant caps units at M")
        format.sizeFormat = .dynamicOneDecimalMegabytes
        try check(format.sizeString(1_572_864,locale:locale)=="1.5 M","One-decimal maxM variant")
        format.sizeFormat = .dynamicTwoDecimalsGigabytes
        try check(format.sizeString(1_342_177_280,locale:locale)=="1.25 G","Two-decimal maxG variant")
        format.useDecimalUnits=true;format.sizeFormat = .dynamicOneDecimal
        try check(format.sizeString(1_500_000,locale:locale)=="1.5 M","Original SizeStyle1000 override uses decimal units")
        try check(format.sizeString(1_500_000,locale:Locale(identifier:"de_DE"))=="1,5 M","Size formatter respects locale decimal separator")
        let date=Date(timeIntervalSince1970:1_704_164_645),zone=TimeZone(secondsFromGMT:0)!
        format.dateOrder = .yearFirst;format.showCentury=true;format.showSeconds=true
        try check(format.dateString(date,locale:locale,timeZone:zone)=="2024-01-02 03:04:05","ISO date ordering with seconds and century")
        format.dateOrder = .dayFirst;format.showCentury=false;format.showSeconds=false
        try check(format.dateString(date,locale:locale,timeZone:zone)=="02.01.24 03:04","Day-first short-year formatting without seconds")
        format.dateOrder = .monthFirst;format.showCentury=true
        try check(format.dateString(date,locale:locale,timeZone:zone)=="01/02/2024 03:04","Month-first explicit date format")
        format.sizeFormat = .bytes;format.footerSizeFormat = .megabytes;format.useDecimalUnits=false
        try check(format.sizeString(1_048_576,locale:locale)=="1,048,576" && format.footerSizeString(1_048_576,locale:locale)=="1 MB","Header/footer units can differ from file list")
        format.footerSizeFormat=nil
        try check(format.footerSizeString(1_048_576,locale:locale)==format.sizeString(1_048_576,locale:locale),"Default header/footer follows current file size style")
        try check(CommanderConfiguration().quickSearchMode == .disabled && !CommanderConfiguration().ignoreListEnabled,"Native quicksearch and ignore defaults preserve prior commandline/list behavior")
        for mode in CommanderConfiguration.QuickSearchMode.allCases {format.quickSearchMode=mode;try format.save(defaults:defaults);try check(CommanderConfiguration.load(defaults:defaults).quickSearchMode==mode,"Quicksearch invocation mode persists: "+mode.rawValue)}
        for value in CommanderConfiguration.SizeFormat.allCases {format.sizeFormat=value;try format.save(defaults:defaults);try check(CommanderConfiguration.load(defaults:defaults).sizeFormat==value,"Persist each supported size variant: "+value.rawValue)}
        print("PASS: \(checks) configuration assertions")
    }
}
