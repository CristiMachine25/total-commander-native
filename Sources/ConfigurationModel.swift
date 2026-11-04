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
    init() {}
    enum CodingKeys:String,CodingKey {case showButtonBar,showDriveList,showFolderTabs,showCurrentDirectory,showColumnHeaders,showStatusBar,showCommandLine,showFunctionButtons,verticalArrangement,showHidden,directoriesFirst,caseSensitiveSort,iconMode,iconSize,fileFontName,fileFontSize,fileFontBold,rowHeight,foreground,background,markedForeground,selectionBackground,selectionForeground,visibleColumns,columnWidths,extensionStyle,sizeFormat,useDecimalUnits,footerSizeFormat,ignoreListEnabled,ignorePatterns,quickSearchMode,quickSearchMatchBeginning,quickSearchMatchEnding,dateOrder,showSeconds,showCentury,tabsAlwaysVisible,tabTitleMaximum,newTabBesideCurrent,saveOnExit,singleClickOpen,selectionIncludesDirectories,historyLimit,externalEditorEnabled,externalEditorPath,externalViewerEnabled,externalViewerPath,thumbnailSize,viewerWordWrap,viewerFontName,viewerFontSize}
    init(from decoder:Decoder)throws {
        let values=try decoder.container(keyedBy:CodingKeys.self)
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
    }
    func normalized()->CommanderConfiguration {
        var c=self
        func number(_ x:Double,_ range:ClosedRange<Double>,_ fallback:Double)->Double{x.isFinite ? min(range.upperBound,max(range.lowerBound,x)) : fallback}
        c.viewerFontSize=number(c.viewerFontSize,9...36,12);if c.viewerFontName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty{c.viewerFontName="Menlo"}
        c.fileFontSize=number(c.fileFontSize,9...36,13);c.rowHeight=number(c.rowHeight,16...64,21)
        c.iconSize=min(48,max(12,c.iconSize));c.thumbnailSize=min(256,max(64,c.thumbnailSize))
        c.tabTitleMaximum=min(100,max(8,c.tabTitleMaximum));c.historyLimit=min(200,max(1,c.historyLimit))
        c.foreground=c.foreground.normalized;c.background=c.background.normalized;c.markedForeground=c.markedForeground.normalized;c.selectionBackground=c.selectionBackground.normalized;c.selectionForeground=c.selectionForeground.normalized
        let allowed=["name","ext","size","date","attr"]
        c.visibleColumns=allowed.filter{$0=="name" || c.visibleColumns.contains($0)}
        c.columnWidths=Dictionary(uniqueKeysWithValues:allowed.map{($0,number(c.columnWidths[$0] ?? CommanderConfiguration().columnWidths[$0]!,32...1200,80))})
        if c.fileFontName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {c.fileFontName="Tahoma"}
        c.ignorePatterns=String(c.ignorePatterns.prefix(16384))
        c.fileFontName=c.fileFontName.trimmingCharacters(in:.whitespacesAndNewlines);c.viewerFontName=c.viewerFontName.trimmingCharacters(in:.whitespacesAndNewlines)
        c.externalEditorPath=c.externalEditorPath.trimmingCharacters(in:.whitespacesAndNewlines);c.externalViewerPath=c.externalViewerPath.trimmingCharacters(in:.whitespacesAndNewlines)
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
        ConfigurationFormatterCache.current.date(locale:locale,timeZone:timeZone,order:dateOrder,seconds:showSeconds,century:showCentury).string(from:date)
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
