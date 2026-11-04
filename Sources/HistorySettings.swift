import AppKit
import ObjectiveC

/// Native local-only history storage. Provider identities may contain credentials;
/// they remain in memory and are never serialized by this store.
enum DirectoryHistorySettings {
    static let key="commander.directoryHistory.v1"
    static func localPaths(_ locations:[PaneLocation],limit:Int)->[String] {
        Array(locations.compactMap { location -> String? in
            guard let url=location.localDirectory,url.isFileURL else{return nil}
            return url.standardizedFileURL.path
        }.suffix(min(200,max(1,limit))))
    }
    static func locations(_ value:Any?,limit:Int)->[PaneLocation] {
        guard let paths=value as? [String],paths.count<=200 else{return []}
        return paths.suffix(min(200,max(1,limit))).compactMap { path in
            guard path.hasPrefix("/"),!path.contains("\0"),path.utf8.count<=32768 else{return nil}
            return .local(URL(fileURLWithPath:path).standardizedFileURL)
        }
    }
    static func save(left:[PaneLocation],right:[PaneLocation],limit:Int,defaults:UserDefaults) {
        defaults.set(["left":localPaths(left,limit:limit),"right":localPaths(right,limit:limit)],forKey:key)
    }
    static func restore(defaults:UserDefaults,limit:Int)->(left:[PaneLocation],right:[PaneLocation]) {
        let record=defaults.dictionary(forKey:key) ?? [:]
        return (locations(record["left"],limit:limit),locations(record["right"],limit:limit))
    }
    static func clear(defaults:UserDefaults){defaults.removeObject(forKey:key)}
}

private var directoryHistoryDefaultsKey:UInt8=0
extension CommanderController {
    /// Production persistence uses the app domain; fixtures can inject an isolated suite.
    var directoryHistoryDefaults:UserDefaults? {
        get {if let store=objc_getAssociatedObject(self,&directoryHistoryDefaultsKey) as? UserDefaults{return store};return remember ? .standard:nil}
        set {objc_setAssociatedObject(self,&directoryHistoryDefaultsKey,newValue,.OBJC_ASSOCIATION_RETAIN_NONATOMIC)}
    }
    func saveDirectoryHistoryOnSessionExit(force:Bool=false) {
        if runtimeConfig.historySaveOnExit || force {saveDirectoryHistoryNow()}
    }

    func makeDirectoryHistoryMenu()->NSMenu {
        let menu=NSMenu(title:"History")
        for location in activePane.backHistory.reversed().prefix(min(200,max(1,runtimeConfig.historyMaximumShown))) {
            let item=NSMenuItem(title:location.displayPath,action:#selector(shortcutHistorySelected(_:)),keyEquivalent:"")
            item.target=self;item.representedObject=location
            if runtimeConfig.historyShowIcons {
                let symbol:String
                switch location {case .local:symbol="folder";case .archive:symbol="archivebox";case .ftp:symbol="network"}
                item.image=NSImage(systemSymbolName:symbol,accessibilityDescription:nil)
            }
            menu.addItem(item)
        }
        return menu
    }
    func saveDirectoryHistoryNow() {
        guard let defaults=directoryHistoryDefaults else{return}
        DirectoryHistorySettings.save(left:left.backHistory,right:right.backHistory,limit:runtimeConfig.historyLimit,defaults:defaults)
    }
    /// Matches original Delete now: erase the saved record, not live navigation.
    func clearDirectoryHistoryNow() {
        guard let defaults=directoryHistoryDefaults else{return}
        DirectoryHistorySettings.clear(defaults:defaults)
    }
    func restoreDirectoryHistory() {
        guard let defaults=directoryHistoryDefaults else{return}
        let saved=DirectoryHistorySettings.restore(defaults:defaults,limit:runtimeConfig.historyLimit)
        left.backHistory=saved.left;right.backHistory=saved.right
    }
}
