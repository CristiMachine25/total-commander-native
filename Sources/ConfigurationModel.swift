import Foundation
import AppKit

struct ConfigurationColor:Codable,Equatable {
    var red:Double,green:Double,blue:Double
    static let black=ConfigurationColor(red:0,green:0,blue:0)
    static let white=ConfigurationColor(red:1,green:1,blue:1)
    var normalized:ConfigurationColor {func clamp(_ x:Double)->Double{x.isFinite ? min(1,max(0,x)) : 0};return .init(red:clamp(red),green:clamp(green),blue:clamp(blue))}
    var nsColor:NSColor {let c=normalized;return NSColor(srgbRed:c.red,green:c.green,blue:c.blue,alpha:1)}
    init(red:Double,green:Double,blue:Double){self.red=red;self.green=green;self.blue=blue}
    init(_ color:NSColor){let c=color.usingColorSpace(.sRGB) ?? .black;red=c.redComponent;green=c.greenComponent;blue=c.blueComponent}
}

/// Native settings schema. Original option meanings are sourced in configuration-coverage.md.
/// This is not a wincmd.ini decoder: unsupported original options are never silently imported.
struct CommanderConfiguration:Codable,Equatable {
    static let defaultsKey="commander.configuration.v1"
    enum QuickSearchMode:String,Codable,CaseIterable {case disabled,letters,alt,ctrlAlt}
    enum IconMode:String,Codable,CaseIterable {case system,standard,none}
    enum ExtensionStyle:String,Codable,CaseIterable {case aligned,afterName}
    enum SizeFormat:String,Codable,CaseIterable {case bytes,kilobytes,megabytes,gigabytes,dynamic,dynamicOneDecimal,dynamicTwoDecimals,dynamicGigabytes,dynamicOneDecimalGigabytes,dynamicTwoDecimalsGigabytes,dynamicMegabytes,dynamicOneDecimalMegabytes}
    enum DateOrder:String,Codable,CaseIterable {case system,dayFirst,monthFirst,yearFirst}
    var showButtonBar:Bool = true
    var showDriveList:Bool = true
    var showFolderTabs:Bool = true
    var showCurrentDirectory:Bool = true
    var showColumnHeaders:Bool = true
    var showStatusBar:Bool = true
    var showCommandLine:Bool = true
    var showFunctionButtons:Bool = true
    var verticalArrangement:Bool = false
    var showHidden:Bool = false
    var directoriesFirst:Bool = true
    var caseSensitiveSort:Bool = false
    var iconMode:IconMode = .system
    var iconSize:Int = 16
    var fileFontName:String = "Tahoma"
    var fileFontSize:Double = 13
    var fileFontBold:Bool = false
    var rowHeight:Double = 21
    var foreground:ConfigurationColor = .black
    var background:ConfigurationColor = .white
    var markedForeground:ConfigurationColor = ConfigurationColor(red:0.8,green:0,blue:0)
    var selectionBackground:ConfigurationColor = ConfigurationColor(red:0,green:0,blue:0.5)
    var selectionForeground:ConfigurationColor = .white
    var visibleColumns:[String] = ["name","ext","size","date","attr"]
    var columnWidths:[String:Double] = ["name":225,"ext":50,"size":80,"date":130,"attr":40]
    var extensionStyle:ExtensionStyle = .aligned
    var sizeFormat:SizeFormat = .bytes
    var useDecimalUnits:Bool = false
    var footerSizeFormat:SizeFormat? = nil
    var ignoreListEnabled:Bool = false
    var ignorePatterns:String = ""
    var quickSearchMode:QuickSearchMode = .disabled
    var quickSearchMatchBeginning:Bool = true
    var quickSearchMatchEnding:Bool = false
    var dateOrder:DateOrder = .system
    var showSeconds:Bool = true
    var showCentury:Bool = true
    var tabsAlwaysVisible:Bool = false
    var tabTitleMaximum:Int = 32
    var newTabBesideCurrent:Bool = false
    var saveOnExit:Bool = true
    var singleClickOpen:Bool = false
    var selectionIncludesDirectories:Bool = true
    var historyLimit:Int = 100
    var externalEditorEnabled:Bool = false
    var externalEditorPath:String = ""
    var externalViewerEnabled:Bool = false
    var externalViewerPath:String = ""
    var thumbnailSize:Int = 128
    var viewerWordWrap:Bool = false
    var viewerFontName:String = "Menlo"
    var viewerFontSize:Double = 12
    var copyPreserveDirectoryDates:Bool = true
    var copyPreserveFileDates:Bool = true
    var copyPreservePermissions:Bool = true
    var copyVerifyAfterCopy:Bool = false
    var copyBufferSizeKB:Int = 1024
    var copyDefaultCollision:String = "ask"
    var confirmCopyMove:Bool = true
    var confirmOverwrite:Bool = true
    var deleteToTrash:Bool = true
    var confirmDelete:Bool = true
    var refreshOnActivate:Bool = true
    var autoRefreshEnabled:Bool = false
    var autoRefreshMetadata:Bool = true
    var autoRefreshOnlyForeground:Bool = true
    var autoRefreshExcludedPaths:String = ""
    var autoRefreshUpdateHeader:Bool = true
    var dateSeparator:String = ""
    var timeSeparator:String = ""
    var use12HourTime:Bool = false
    var zipCompressionLevel:Int = 6
    var zipVerifyAfterPacking:Bool = true
    var archiveSetDateToNewest:Bool = false
    var browseArchivesAsDirectories:Bool = true
    var ftpPassiveMode:Bool = true
    var ftpConnectTimeout:Int = 15
    var ftpTransferTimeout:Int = 600
    var ftpOpenPanel:Int = 0
    var alternatingRowBackground:Bool = false
    var alternatingBackground:ConfigurationColor = .init(red:0.96,green:0.96,blue:0.96)
    var customShortcuts:String = ""
    var commandAliases:String = ""
    var tabsCloseOnDoubleClick:Bool = false
    var confirmCloseAllTabs:Bool = true
    var tabsShowLockAsterisk:Bool = true
    var customColumnSets:[CustomColumnSet] = []
    var activeCustomColumnSetID:String = ""
    var viewModes:[CommanderViewMode] = []
    var autoSwitchRules:[CommanderAutoSwitchRule] = []
    var autoSwitchEnabled:Bool = false
    var autoSwitchRestoreDefault:Bool = true
    var directoryBrackets:Bool = true
    var directoryTrailingSlash:Bool = false
    var showDirectoryCount:Bool = false
    var directoriesAlwaysByName:Bool = false
    var briefColumnWidthLimit:Int = 0
    var sortMethod:CommanderSortMethod = .naturalAlphabetical
    var historySaveOnExit:Bool = false
    var historyMaximumShown:Int = 100
    var historyShowIcons:Bool = false
    var tabsRememberViewSettings:Bool = true
    var tabsRememberFileFilters:Bool = true
    var appearanceMode:CommanderAppearanceMode = .light
    var darkPalette:CommanderDarkPalette = .init()
    init() {}
    enum CodingKeys:String,CodingKey {case directoryBrackets,directoryTrailingSlash,showDirectoryCount,directoriesAlwaysByName,briefColumnWidthLimit,sortMethod,historySaveOnExit,historyMaximumShown,historyShowIcons,tabsRememberViewSettings,tabsRememberFileFilters,appearanceMode,darkPalette,customColumnSets,activeCustomColumnSetID,viewModes,autoSwitchRules,autoSwitchEnabled,autoSwitchRestoreDefault,tabsCloseOnDoubleClick,confirmCloseAllTabs,tabsShowLockAsterisk,customShortcuts,commandAliases,alternatingRowBackground,alternatingBackground,copyPreserveDirectoryDates,copyPreserveFileDates,copyPreservePermissions,copyVerifyAfterCopy,copyBufferSizeKB,copyDefaultCollision,confirmCopyMove,confirmOverwrite,deleteToTrash,confirmDelete,refreshOnActivate,autoRefreshEnabled,autoRefreshMetadata,autoRefreshOnlyForeground,autoRefreshExcludedPaths,autoRefreshUpdateHeader,dateSeparator,timeSeparator,use12HourTime,zipCompressionLevel,zipVerifyAfterPacking,archiveSetDateToNewest,browseArchivesAsDirectories,ftpPassiveMode,ftpConnectTimeout,ftpTransferTimeout,ftpOpenPanel,showButtonBar,showDriveList,showFolderTabs,showCurrentDirectory,showColumnHeaders,showStatusBar,showCommandLine,showFunctionButtons,verticalArrangement,showHidden,directoriesFirst,caseSensitiveSort,iconMode,iconSize,fileFontName,fileFontSize,fileFontBold,rowHeight,foreground,background,markedForeground,selectionBackground,selectionForeground,visibleColumns,columnWidths,extensionStyle,sizeFormat,useDecimalUnits,footerSizeFormat,ignoreListEnabled,ignorePatterns,quickSearchMode,quickSearchMatchBeginning,quickSearchMatchEnding,dateOrder,showSeconds,showCentury,tabsAlwaysVisible,tabTitleMaximum,newTabBesideCurrent,saveOnExit,singleClickOpen,selectionIncludesDirectories,historyLimit,externalEditorEnabled,externalEditorPath,externalViewerEnabled,externalViewerPath,thumbnailSize,viewerWordWrap,viewerFontName,viewerFontSize}
    init(from decoder:Decoder)throws {
        let values=try decoder.container(keyedBy:CodingKeys.self)
        directoryBrackets=(try? values.decode(Bool.self,forKey:.directoryBrackets)) ?? true
        directoryTrailingSlash=(try? values.decode(Bool.self,forKey:.directoryTrailingSlash)) ?? false
        showDirectoryCount=(try? values.decode(Bool.self,forKey:.showDirectoryCount)) ?? false
        directoriesAlwaysByName=(try? values.decode(Bool.self,forKey:.directoriesAlwaysByName)) ?? false
        briefColumnWidthLimit=(try? values.decode(Int.self,forKey:.briefColumnWidthLimit)) ?? 0
        sortMethod=(try? values.decode(CommanderSortMethod.self,forKey:.sortMethod)) ?? .naturalAlphabetical
        historySaveOnExit=(try? values.decode(Bool.self,forKey:.historySaveOnExit)) ?? false
        historyMaximumShown=(try? values.decode(Int.self,forKey:.historyMaximumShown)) ?? 100
        historyShowIcons=(try? values.decode(Bool.self,forKey:.historyShowIcons)) ?? false

        tabsRememberViewSettings=(try? values.decode(Bool.self,forKey:.tabsRememberViewSettings)) ?? true
        tabsRememberFileFilters=(try? values.decode(Bool.self,forKey:.tabsRememberFileFilters)) ?? true
        appearanceMode=(try? values.decode(CommanderAppearanceMode.self,forKey:.appearanceMode)) ?? .light
        darkPalette=(try? values.decode(CommanderDarkPalette.self,forKey:.darkPalette)) ?? .init()
        customColumnSets=(try? values.decode([CustomColumnSet].self,forKey:.customColumnSets)) ?? []
        activeCustomColumnSetID=(try? values.decode(String.self,forKey:.activeCustomColumnSetID)) ?? ""
        viewModes=(try? values.decode([CommanderViewMode].self,forKey:.viewModes)) ?? []
        autoSwitchRules=(try? values.decode([CommanderAutoSwitchRule].self,forKey:.autoSwitchRules)) ?? []
        autoSwitchEnabled=(try? values.decode(Bool.self,forKey:.autoSwitchEnabled)) ?? false
        autoSwitchRestoreDefault=(try? values.decode(Bool.self,forKey:.autoSwitchRestoreDefault)) ?? true
        tabsCloseOnDoubleClick=(try? values.decode(Bool.self,forKey:.tabsCloseOnDoubleClick)) ?? false
        confirmCloseAllTabs=(try? values.decode(Bool.self,forKey:.confirmCloseAllTabs)) ?? true
        tabsShowLockAsterisk=(try? values.decode(Bool.self,forKey:.tabsShowLockAsterisk)) ?? true

        customShortcuts=(try? values.decode(String.self,forKey:.customShortcuts)) ?? ""
        commandAliases=(try? values.decode(String.self,forKey:.commandAliases)) ?? ""

        alternatingRowBackground=(try? values.decode(Bool.self,forKey:.alternatingRowBackground)) ?? false
        alternatingBackground=(try? values.decode(ConfigurationColor.self,forKey:.alternatingBackground)) ?? .init(red:0.96,green:0.96,blue:0.96)
        showButtonBar=(try? values.decode(Bool.self,forKey:.showButtonBar)) ?? true
        showDriveList=(try? values.decode(Bool.self,forKey:.showDriveList)) ?? true
        showFolderTabs=(try? values.decode(Bool.self,forKey:.showFolderTabs)) ?? true
        showCurrentDirectory=(try? values.decode(Bool.self,forKey:.showCurrentDirectory)) ?? true
        showColumnHeaders=(try? values.decode(Bool.self,forKey:.showColumnHeaders)) ?? true
        showStatusBar=(try? values.decode(Bool.self,forKey:.showStatusBar)) ?? true
        showCommandLine=(try? values.decode(Bool.self,forKey:.showCommandLine)) ?? true
        showFunctionButtons=(try? values.decode(Bool.self,forKey:.showFunctionButtons)) ?? true
        verticalArrangement=(try? values.decode(Bool.self,forKey:.verticalArrangement)) ?? false
        showHidden=(try? values.decode(Bool.self,forKey:.showHidden)) ?? false
        directoriesFirst=(try? values.decode(Bool.self,forKey:.directoriesFirst)) ?? true
        caseSensitiveSort=(try? values.decode(Bool.self,forKey:.caseSensitiveSort)) ?? false
        iconMode=(try? values.decode(IconMode.self,forKey:.iconMode)) ?? .system
        iconSize=(try? values.decode(Int.self,forKey:.iconSize)) ?? 16
        fileFontName=(try? values.decode(String.self,forKey:.fileFontName)) ?? "Tahoma"
        fileFontSize=(try? values.decode(Double.self,forKey:.fileFontSize)) ?? 13
        fileFontBold=(try? values.decode(Bool.self,forKey:.fileFontBold)) ?? false
        rowHeight=(try? values.decode(Double.self,forKey:.rowHeight)) ?? 21
        foreground=(try? values.decode(ConfigurationColor.self,forKey:.foreground)) ?? .black
        background=(try? values.decode(ConfigurationColor.self,forKey:.background)) ?? .white
        markedForeground=(try? values.decode(ConfigurationColor.self,forKey:.markedForeground)) ?? ConfigurationColor(red:0.8,green:0,blue:0)
        selectionBackground=(try? values.decode(ConfigurationColor.self,forKey:.selectionBackground)) ?? ConfigurationColor(red:0,green:0,blue:0.5)
        selectionForeground=(try? values.decode(ConfigurationColor.self,forKey:.selectionForeground)) ?? .white
        visibleColumns=(try? values.decode([String].self,forKey:.visibleColumns)) ?? ["name","ext","size","date","attr"]
        columnWidths=(try? values.decode([String:Double].self,forKey:.columnWidths)) ?? ["name":225,"ext":50,"size":80,"date":130,"attr":40]
        extensionStyle=(try? values.decode(ExtensionStyle.self,forKey:.extensionStyle)) ?? .aligned
        sizeFormat=(try? values.decode(SizeFormat.self,forKey:.sizeFormat)) ?? .bytes
        footerSizeFormat=try? values.decode(SizeFormat.self,forKey:.footerSizeFormat)
        ignoreListEnabled=(try? values.decode(Bool.self,forKey:.ignoreListEnabled)) ?? false
        ignorePatterns=(try? values.decode(String.self,forKey:.ignorePatterns)) ?? ""
        quickSearchMode=(try? values.decode(QuickSearchMode.self,forKey:.quickSearchMode)) ?? .disabled
        quickSearchMatchBeginning=(try? values.decode(Bool.self,forKey:.quickSearchMatchBeginning)) ?? true
        quickSearchMatchEnding=(try? values.decode(Bool.self,forKey:.quickSearchMatchEnding)) ?? false
        useDecimalUnits=(try? values.decode(Bool.self,forKey:.useDecimalUnits)) ?? false
        dateOrder=(try? values.decode(DateOrder.self,forKey:.dateOrder)) ?? .system
        showSeconds=(try? values.decode(Bool.self,forKey:.showSeconds)) ?? true
        showCentury=(try? values.decode(Bool.self,forKey:.showCentury)) ?? true
        tabsAlwaysVisible=(try? values.decode(Bool.self,forKey:.tabsAlwaysVisible)) ?? false
        tabTitleMaximum=(try? values.decode(Int.self,forKey:.tabTitleMaximum)) ?? 32
        newTabBesideCurrent=(try? values.decode(Bool.self,forKey:.newTabBesideCurrent)) ?? false
        saveOnExit=(try? values.decode(Bool.self,forKey:.saveOnExit)) ?? true
        singleClickOpen=(try? values.decode(Bool.self,forKey:.singleClickOpen)) ?? false
        selectionIncludesDirectories=(try? values.decode(Bool.self,forKey:.selectionIncludesDirectories)) ?? true
        historyLimit=(try? values.decode(Int.self,forKey:.historyLimit)) ?? 100
        externalEditorEnabled=(try? values.decode(Bool.self,forKey:.externalEditorEnabled)) ?? false
        externalEditorPath=(try? values.decode(String.self,forKey:.externalEditorPath)) ?? ""
        externalViewerEnabled=(try? values.decode(Bool.self,forKey:.externalViewerEnabled)) ?? false
        externalViewerPath=(try? values.decode(String.self,forKey:.externalViewerPath)) ?? ""
        thumbnailSize=(try? values.decode(Int.self,forKey:.thumbnailSize)) ?? 128
        viewerWordWrap=(try? values.decode(Bool.self,forKey:.viewerWordWrap)) ?? false
        viewerFontName=(try? values.decode(String.self,forKey:.viewerFontName)) ?? "Menlo"
        viewerFontSize=(try? values.decode(Double.self,forKey:.viewerFontSize)) ?? 12
        copyPreserveDirectoryDates=(try? values.decode(Bool.self,forKey:.copyPreserveDirectoryDates)) ?? true
        copyPreserveFileDates=(try? values.decode(Bool.self,forKey:.copyPreserveFileDates)) ?? true
        copyPreservePermissions=(try? values.decode(Bool.self,forKey:.copyPreservePermissions)) ?? true
        copyVerifyAfterCopy=(try? values.decode(Bool.self,forKey:.copyVerifyAfterCopy)) ?? false
        copyBufferSizeKB=(try? values.decode(Int.self,forKey:.copyBufferSizeKB)) ?? 1024
        copyDefaultCollision=(try? values.decode(String.self,forKey:.copyDefaultCollision)) ?? "ask"
        confirmCopyMove=(try? values.decode(Bool.self,forKey:.confirmCopyMove)) ?? true
        confirmOverwrite=(try? values.decode(Bool.self,forKey:.confirmOverwrite)) ?? true
        deleteToTrash=(try? values.decode(Bool.self,forKey:.deleteToTrash)) ?? true
        confirmDelete=(try? values.decode(Bool.self,forKey:.confirmDelete)) ?? true
        refreshOnActivate=(try? values.decode(Bool.self,forKey:.refreshOnActivate)) ?? true
        autoRefreshEnabled=(try? values.decode(Bool.self,forKey:.autoRefreshEnabled)) ?? false
        autoRefreshMetadata=(try? values.decode(Bool.self,forKey:.autoRefreshMetadata)) ?? true
        autoRefreshOnlyForeground=(try? values.decode(Bool.self,forKey:.autoRefreshOnlyForeground)) ?? true
        autoRefreshExcludedPaths=(try? values.decode(String.self,forKey:.autoRefreshExcludedPaths)) ?? ""
        autoRefreshUpdateHeader=(try? values.decode(Bool.self,forKey:.autoRefreshUpdateHeader)) ?? true
        dateSeparator=(try? values.decode(String.self,forKey:.dateSeparator)) ?? ""
        timeSeparator=(try? values.decode(String.self,forKey:.timeSeparator)) ?? ""
        use12HourTime=(try? values.decode(Bool.self,forKey:.use12HourTime)) ?? false
        zipCompressionLevel=(try? values.decode(Int.self,forKey:.zipCompressionLevel)) ?? 6
        zipVerifyAfterPacking=(try? values.decode(Bool.self,forKey:.zipVerifyAfterPacking)) ?? true
        archiveSetDateToNewest=(try? values.decode(Bool.self,forKey:.archiveSetDateToNewest)) ?? false
        browseArchivesAsDirectories=(try? values.decode(Bool.self,forKey:.browseArchivesAsDirectories)) ?? true
        ftpPassiveMode=(try? values.decode(Bool.self,forKey:.ftpPassiveMode)) ?? true
        ftpConnectTimeout=(try? values.decode(Int.self,forKey:.ftpConnectTimeout)) ?? 15
        ftpTransferTimeout=(try? values.decode(Int.self,forKey:.ftpTransferTimeout)) ?? 600
        ftpOpenPanel=(try? values.decode(Int.self,forKey:.ftpOpenPanel)) ?? 0
    }
    func normalized()->CommanderConfiguration {
        var c=self
        c.darkPalette=c.darkPalette.normalized
        c.alternatingBackground=c.alternatingBackground.normalized
        func number(_ x:Double,_ range:ClosedRange<Double>,_ fallback:Double)->Double{x.isFinite ? min(range.upperBound,max(range.lowerBound,x)) : fallback}
        c.viewerFontSize=number(c.viewerFontSize,9...36,12);if c.viewerFontName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty{c.viewerFontName="Menlo"}
        c.fileFontSize=number(c.fileFontSize,9...36,13);c.rowHeight=number(c.rowHeight,16...64,21)
        c.iconSize=min(48,max(12,c.iconSize));c.thumbnailSize=min(256,max(64,c.thumbnailSize))
        c.briefColumnWidthLimit=min(1200,max(0,c.briefColumnWidthLimit));c.historyMaximumShown=min(200,max(1,c.historyMaximumShown))
        c.tabTitleMaximum=min(100,max(8,c.tabTitleMaximum));c.historyLimit=min(200,max(1,c.historyLimit))
        c.foreground=c.foreground.normalized;c.background=c.background.normalized;c.markedForeground=c.markedForeground.normalized;c.selectionBackground=c.selectionBackground.normalized;c.selectionForeground=c.selectionForeground.normalized
        let allowed=["name","ext","size","date","attr"]
        c.visibleColumns=allowed.filter{$0=="name" || c.visibleColumns.contains($0)}
        c.columnWidths=Dictionary(uniqueKeysWithValues:allowed.map{($0,number(c.columnWidths[$0] ?? CommanderConfiguration().columnWidths[$0]!,32...1200,80))})
        if c.fileFontName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {c.fileFontName="Tahoma"}
        c.ignorePatterns=String(c.ignorePatterns.prefix(16384))
        c.fileFontName=c.fileFontName.trimmingCharacters(in:.whitespacesAndNewlines);c.viewerFontName=c.viewerFontName.trimmingCharacters(in:.whitespacesAndNewlines)
        c.externalEditorPath=c.externalEditorPath.trimmingCharacters(in:.whitespacesAndNewlines);c.externalViewerPath=c.externalViewerPath.trimmingCharacters(in:.whitespacesAndNewlines)
        c.customShortcuts=String(c.customShortcuts.prefix(16384));c.commandAliases=String(c.commandAliases.prefix(16384))
        c.copyBufferSizeKB=min(16384,max(64,c.copyBufferSizeKB))
        if !["ask","skip","replace","rename"].contains(c.copyDefaultCollision){c.copyDefaultCollision="ask"}
        c.zipCompressionLevel=min(9,max(0,c.zipCompressionLevel))
        c.ftpConnectTimeout=min(300,max(1,c.ftpConnectTimeout));c.ftpTransferTimeout=min(86400,max(1,c.ftpTransferTimeout));c.ftpOpenPanel=min(3,max(0,c.ftpOpenPanel))
        c.autoRefreshExcludedPaths=String(c.autoRefreshExcludedPaths.prefix(16384))
        c.dateSeparator=String(c.dateSeparator.filter{!$0.isNewline}.prefix(3));c.timeSeparator=String(c.timeSeparator.filter{!$0.isNewline}.prefix(3))
        // Stored preferences may be older or damaged. Keep unrelated preferences usable;
        // strict file import compares the normalized form and rejects any discarded data.
        do {
            try CustomColumnSettings.validate(sets:c.customColumnSets,activeID:c.activeCustomColumnSetID)
            try ViewModeSettings.validate(modes:c.viewModes,rules:c.autoSwitchRules,customColumnSets:c.customColumnSets)
        } catch {
            c.customColumnSets=[];c.activeCustomColumnSetID="";c.viewModes=[];c.autoSwitchRules=[];c.autoSwitchEnabled=false
        }
        return c
    }
    static func load(defaults:UserDefaults = .standard)->CommanderConfiguration {
        var c:CommanderConfiguration
        if let data=defaults.data(forKey:defaultsKey),let value=try? JSONDecoder().decode(Self.self,from:data){c=value}
        else {
            c=CommanderConfiguration()
            if defaults.object(forKey:"fileFontSize") != nil{c.fileFontSize=defaults.double(forKey:"fileFontSize")}
            if defaults.object(forKey:"fileRowHeight") != nil{c.rowHeight=defaults.double(forKey:"fileRowHeight")}
            if defaults.object(forKey:"showHidden") != nil{c.showHidden=defaults.bool(forKey:"showHidden")}
            c.externalEditorPath=defaults.string(forKey:"externalEditor") ?? "";c.externalEditorEnabled = !c.externalEditorPath.isEmpty
        }
        return c.normalized()
    }
    func save(defaults:UserDefaults = .standard)throws {
        let c=normalized(),data=try JSONEncoder().encode(c)
        defaults.set(data,forKey:Self.defaultsKey)
        // Compatibility with pre-schema consumers during native UI migration.
        defaults.set(c.fileFontSize,forKey:"fileFontSize");defaults.set(c.rowHeight,forKey:"fileRowHeight");defaults.set(c.showHidden,forKey:"showHidden")
        defaults.set(c.externalEditorEnabled ? c.externalEditorPath : "",forKey:"externalEditor")
    }
    func sizeString(_ bytes:Int64,locale:Locale = .current)->String {
        let value=max(0,bytes),base=useDecimalUnits ? 1000.0 : 1024.0
        let cache=ConfigurationFormatterCache.current
        func formatted(_ value:Double,_ digits:Int=0)->String {cache.number(locale:locale,digits:digits).string(from:NSNumber(value:value)) ?? "0"}
        switch sizeFormat {
        case .bytes:return cache.number(locale:locale,digits:0).string(from:NSNumber(value:value)) ?? String(value)
        case .kilobytes:return formatted(Double(value)/base)+" k"
        case .megabytes:return formatted(Double(value)/(base*base),2)+" MB"
        case .gigabytes:return formatted(Double(value)/(base*base*base),2)+" GB"
        default:
            let units=[""," k"," M"," G"," T"]
            let maximum:Int
            switch sizeFormat {case .dynamicMegabytes,.dynamicOneDecimalMegabytes:maximum=2;case .dynamicGigabytes,.dynamicOneDecimalGigabytes,.dynamicTwoDecimalsGigabytes:maximum=3;default:maximum=4}
            let precision:Int
            switch sizeFormat {case .dynamicOneDecimal,.dynamicOneDecimalGigabytes,.dynamicOneDecimalMegabytes:precision=1;case .dynamicTwoDecimals,.dynamicTwoDecimalsGigabytes:precision=2;default:precision=0}
            var amount=Double(value),index=0
            while amount>=base && index<maximum{amount/=base;index += 1}
            return formatted(amount,index>0 ? precision : 0)+units[index]
        }
    }
    func footerSizeString(_ bytes:Int64,locale:Locale = .current)->String {var copy=self;if let footerSizeFormat{copy.sizeFormat=footerSizeFormat};return copy.sizeString(bytes,locale:locale)}
    func dateString(_ date:Date,locale:Locale = .current,timeZone:TimeZone = .current)->String {
        CommanderDateFormatting.string(date,configuration:self,locale:locale,timeZone:timeZone)
    }
}

/// A formatter is expensive to construct. File-list painting shares instances on
/// its current thread, never across worker threads. Keys include every formatting
/// input, so a changed locale, time zone or display setting takes effect immediately.
private final class ConfigurationFormatterCache:NSObject {
    private struct NumberKey:Hashable {let locale:Locale;let digits:Int}
    private struct DateKey:Hashable {let locale:Locale;let zone:TimeZone;let order:CommanderConfiguration.DateOrder;let seconds:Bool;let century:Bool}
    private var numbers:[NumberKey:NumberFormatter]=[:]
    private var dates:[DateKey:DateFormatter]=[:]
    private static let threadKey="local.totalcommander.configuration-formatters"
    static var current:ConfigurationFormatterCache {
        let storage=Thread.current.threadDictionary
        if let cache=storage[threadKey] as? ConfigurationFormatterCache{return cache}
        let cache=ConfigurationFormatterCache();storage[threadKey]=cache;return cache
    }
    func number(locale:Locale,digits:Int)->NumberFormatter {
        let key=NumberKey(locale:locale,digits:digits)
        if let formatter=numbers[key]{return formatter}
        let formatter=NumberFormatter();formatter.locale=locale;formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator=true;formatter.groupingSize=3;formatter.maximumFractionDigits=digits
        if numbers.count>=32{numbers.removeAll(keepingCapacity:true)}
        numbers[key]=formatter;return formatter
    }
    func date(locale:Locale,timeZone:TimeZone,order:CommanderConfiguration.DateOrder,seconds:Bool,century:Bool)->DateFormatter {
        let key=DateKey(locale:locale,zone:timeZone,order:order,seconds:seconds,century:century)
        if let formatter=dates[key]{return formatter}
        let formatter=DateFormatter();formatter.locale=locale;formatter.timeZone=timeZone
        if order == .system {formatter.dateStyle = .short;formatter.timeStyle=seconds ? .medium : .short;formatter.dateFormat=formatter.dateFormat.replacingOccurrences(of:"y+",with:century ? "yyyy" : "yy",options:.regularExpression)}
        else {
            let year=century ? "yyyy" : "yy",time=seconds ? "HH:mm:ss" : "HH:mm"
            switch order {case .dayFirst:formatter.dateFormat="dd.MM."+year+" "+time;case .monthFirst:formatter.dateFormat="MM/dd/"+year+" "+time;case .yearFirst:formatter.dateFormat=year+"-MM-dd "+time;case .system:break}
        }
        if dates.count>=32{dates.removeAll(keepingCapacity:true)}
        dates[key]=formatter;return formatter
    }
}


/// Every user-supplied separator is quoted as a date-format literal, not parsed
/// as an ICU pattern. Cache entries are thread-local and include every option.
enum CommanderDateFormatting {
    private final class Cache:NSObject {var values:[Key:DateFormatter]=[:]}
    private struct Key:Hashable {
        let locale:Locale,zone:TimeZone,order:CommanderConfiguration.DateOrder
        let seconds:Bool,century:Bool,hour12:Bool,dateSeparator:String,timeSeparator:String
    }
    static func string(_ date:Date,configuration c:CommanderConfiguration,locale:Locale,timeZone:TimeZone)->String {
        let key=Key(locale:locale,zone:timeZone,order:c.dateOrder,seconds:c.showSeconds,century:c.showCentury,hour12:c.use12HourTime,dateSeparator:c.dateSeparator,timeSeparator:c.timeSeparator)
        let thread=Thread.current.threadDictionary,cache:Cache
        if let existing=thread["local.totalcommander.date-settings"] as? Cache {cache=existing}
        else {cache=Cache();thread["local.totalcommander.date-settings"]=cache}
        if let formatter=cache.values[key] {return formatter.string(from:date)}
        let formatter=DateFormatter();formatter.locale=locale;formatter.timeZone=timeZone
        let year=c.showCentury ? "yyyy":"yy"
        func literal(_ text:String)->String {text.components(separatedBy:"'").map{$0.isEmpty ? "" : "'"+$0+"'"}.joined(separator:"''")}
        let defaultSeparator:String
        let fields:[String]
        switch c.dateOrder {
        case .dayFirst:fields=["dd","MM",year];defaultSeparator="."
        case .monthFirst:fields=["MM","dd",year];defaultSeparator="/"
        case .yearFirst:fields=[year,"MM","dd"];defaultSeparator="-"
        case .system:
            formatter.dateStyle = .short;formatter.timeStyle = .none
            let pattern=formatter.dateFormat ?? "M/d/yyyy"
            let ordered=[("d","dd"),("M","MM"),("y",year)].compactMap { char,field -> (Int,String)? in
                guard let range=pattern.range(of:char) else{return nil};return (pattern.distance(from:pattern.startIndex,to:range.lowerBound),field)
            }.sorted{$0.0<$1.0}.map(\.1)
            fields=ordered.count==3 ? ordered:["MM","dd",year];defaultSeparator="/"
        }
        let datePattern:String
        if c.dateOrder == .system,c.dateSeparator.isEmpty {
            formatter.dateStyle = .short;formatter.timeStyle = .none
            datePattern=formatter.dateFormat.replacingOccurrences(of:"y+",with:year,options:.regularExpression)
        } else {datePattern=fields.joined(separator:literal(c.dateSeparator.isEmpty ? defaultSeparator:c.dateSeparator))}
        let timePattern:String
        if c.dateOrder == .system,!c.use12HourTime,c.timeSeparator.isEmpty {
            // Preserve the original locale-based system time when no override is requested.
            formatter.dateStyle = .none;formatter.timeStyle=c.showSeconds ? .medium:.short
            timePattern=formatter.dateFormat
        } else {
            let separator=literal(c.timeSeparator.isEmpty ? ":":c.timeSeparator)
            timePattern=(c.use12HourTime ? "hh":"HH")+separator+"mm"+(c.showSeconds ? separator+"ss":"")+(c.use12HourTime ? " a":"")
        }
        if c.dateOrder == .system,c.dateSeparator.isEmpty,c.timeSeparator.isEmpty,!c.use12HourTime {
            formatter.dateStyle = .short;formatter.timeStyle=c.showSeconds ? .medium:.short
            formatter.dateFormat=formatter.dateFormat.replacingOccurrences(of:"y+",with:year,options:.regularExpression)
        } else {formatter.dateFormat=datePattern+" "+timePattern}
        if cache.values.count>=32 {cache.values.removeAll(keepingCapacity:true)}
        cache.values[key]=formatter;return formatter.string(from:date)
    }
}
