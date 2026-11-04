import Foundation
import AppKit
import ObjectiveC

/// Only value data belongs in tab sessions; no provider/client/password objects.
struct CommanderTabViewDefaults:Codable,Equatable {
    var columns="full"
    var customColumnSetID=""
    var sortColumn="name"
    var ascending=true
    var secondarySortColumns:[String]=[]
    var directoriesFirst=true
    var fileMask=""
    var programsOnly=false
}
struct CommanderTabViewSettings:Codable,Equatable {
    var defaultView:CommanderTabViewDefaults?=nil
    var manualModeID:String?
    var customColumnSetID=""
    var columns="full"
    var sortColumn="name"
    var ascending=true
    var secondarySortColumns:[String]=[]
    var directoriesFirst=true
    var fileMask=""
    var programsOnly=false
    var nameFilter=""
    var selectedOnlyNames:[String]?=nil
    var selectedNames:[String]=[]
    var markedNames:[String]=[]
    var locationIdentity=""
    func sanitized(configuration:CommanderConfiguration)->CommanderTabViewSettings? {
        guard ["full","brief","thumbnails","tree"].contains(columns),fileMask.utf8.count<=4096,nameFilter.utf8.count<=4096,locationIdentity.utf8.count<=16384,secondarySortColumns.count<=8,selectedNames.count<=100000,markedNames.count<=100000,(selectedOnlyNames?.count ?? 0)<=100000 else{return nil}
        func namesValid(_ names:[String])->Bool {names.allSatisfy{!$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/") && !$0.contains("\0") && $0.utf8.count<=4096}}
        guard namesValid(selectedNames),namesValid(markedNames),namesValid(selectedOnlyNames ?? []) else{return nil}
        var result=self
        if !configuration.viewModes.contains(where:{$0.id==manualModeID}) {result.manualModeID=nil}
        if !configuration.customColumnSets.contains(where:{$0.id==customColumnSetID}) {result.customColumnSetID=""}
        let custom=configuration.customColumnSets.first{$0.id==result.customColumnSetID}
        let allowed:Set<String>=["name","ext","size","date","unsorted"]
        func validSort(_ key:String)->Bool {allowed.contains(key) || (custom?.columns.contains{"custom."+$0.id==key} ?? false)}
        if !validSort(result.sortColumn) {result.sortColumn="name"}
        result.secondarySortColumns=result.secondarySortColumns.filter{validSort($0.hasPrefix("-") ? String($0.dropFirst()):$0)}
        if var defaults=result.defaultView {
            guard ["full","brief","thumbnails","tree"].contains(defaults.columns),defaults.fileMask.utf8.count<=4096,defaults.secondarySortColumns.count<=8 else{return nil}
            if !configuration.customColumnSets.contains(where:{$0.id==defaults.customColumnSetID}) {defaults.customColumnSetID=""}
            let defaultSet=configuration.customColumnSets.first{$0.id==defaults.customColumnSetID}
            func allowedDefault(_ key:String)->Bool {allowed.contains(key) || (defaultSet?.columns.contains{"custom."+$0.id==key} ?? false)}
            if !allowedDefault(defaults.sortColumn){defaults.sortColumn="name"}
            defaults.secondarySortColumns=defaults.secondarySortColumns.filter{allowedDefault($0.hasPrefix("-") ? String($0.dropFirst()):$0)}
            result.defaultView=defaults
        }
        return result
    }
}
private final class TabViewStorage:NSObject {var values:[Int:CommanderTabViewSettings]=[:]}
private var tabViewStorageKey:UInt8=0
extension Pane {
    var tabViewSettings:[Int:CommanderTabViewSettings] {
        get {(objc_getAssociatedObject(self,&tabViewStorageKey) as? TabViewStorage)?.values ?? [:]}
        set {let storage=(objc_getAssociatedObject(self,&tabViewStorageKey) as? TabViewStorage) ?? TabViewStorage();storage.values=newValue;objc_setAssociatedObject(self,&tabViewStorageKey,storage,.OBJC_ASSOCIATION_RETAIN_NONATOMIC)}
    }
    func rememberCurrentTabView() {
        guard configuration.tabsRememberViewSettings,tabs.indices.contains(selectedTab),!isLoading else{return}
        tabViewSettings[selectedTab]=captureManualTabView()
    }
    struct SavedTabViews:Codable {
        struct Record:Codable {var index:Int;var path:String;var view:CommanderTabViewSettings}
        var version=1
        var records:[Record]
    }
    func savedLocalTabViews()->Data? {
        guard configuration.tabsRememberViewSettings else{return nil}
        rememberCurrentTabView()
        let local=tabs.indices.filter{tabs[$0].localDirectory != nil}
        let records=local.enumerated().compactMap {saved,index -> SavedTabViews.Record? in
            guard var value=tabViewSettings[index],let path=tabs[index].localDirectory?.standardizedFileURL.path else{return nil}
            let identity="local:"+path
            if value.locationIdentity != identity {value.locationIdentity=identity;value.selectedOnlyNames=nil;value.selectedNames=[];value.markedNames=[]}
            return .init(index:saved,path:path,view:value)
        }
        return try? JSONEncoder().encode(SavedTabViews(records:records))
    }
    func restoreLocalTabViews(_ data:Data?,configuration:CommanderConfiguration) {
        tabViewSettings=[:]
        guard configuration.tabsRememberViewSettings,let data,data.count<=8*1024*1024,let envelope=try? JSONDecoder().decode(SavedTabViews.self,from:data),envelope.version==1,envelope.records.count<=10000 else{return}
        var seen=Set<Int>()
        for record in envelope.records {
            guard seen.insert(record.index).inserted,tabs.indices.contains(record.index),let root=tabs[record.index].localDirectory,root.standardizedFileURL.path==record.path,let value=record.view.sanitized(configuration:configuration) else{continue}
            tabViewSettings[record.index]=value
        }
    }
}
