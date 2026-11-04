import AppKit
import ObjectiveC
import Darwin

/// Polls only the two visible local directories, never a recursive tree or a
/// remote provider. Scans run off the main thread and stale results are discarded.
final class CommanderRefreshController:NSObject {
    private weak var commander:CommanderController?
    private var timer:Timer?
    private var activationObserver:NSObjectProtocol?
    private var inFlight=false
    private var activationPending=false
    private var revision=0
    private struct FolderStamp:Equatable {let modifiedSeconds:Int,modifiedNanos:Int,changedSeconds:Int,changedNanos:Int}
    private struct CachedFolderStamp {let location:String;let stamp:FolderStamp}
    private var folderStamps:[ObjectIdentifier:CachedFolderStamp]=[:]
    private static func stamp(_ url:URL)->FolderStamp? {
        var info=stat();guard lstat(url.resolvingSymlinksInPath().path,&info)==0 else{return nil}
        return FolderStamp(modifiedSeconds:info.st_mtimespec.tv_sec,modifiedNanos:info.st_mtimespec.tv_nsec,changedSeconds:info.st_ctimespec.tv_sec,changedNanos:info.st_ctimespec.tv_nsec)
    }
    private let queue=DispatchQueue(label:"local.totalcommander.visible-refresh",qos:.utility)
    private(set) var completedScans=0
    init(_ commander:CommanderController) {
        self.commander=commander
        super.init()
        if commander.remember {
        activationObserver=NotificationCenter.default.addObserver(forName:NSApplication.didBecomeActiveNotification,object:nil,queue:.main){[weak self] _ in
            guard let self,self.commander?.runtimeConfig.refreshOnActivate == true else{return}
            self.activationPending=true;self.scanNow()
        }
        }
    }
    deinit {timer?.invalidate();if let activationObserver{NotificationCenter.default.removeObserver(activationObserver)}}
    func configure() {
        revision += 1;folderStamps.removeAll()
        timer?.invalidate();timer=nil
        guard let commander else{return}
        if !commander.runtimeConfig.refreshOnActivate {activationPending=false}
        // Nonpersistent test controllers are driven explicitly rather than installing timers.
        guard commander.remember,commander.runtimeConfig.autoRefreshEnabled || commander.runtimeConfig.refreshOnActivate else{return}
        let timer=Timer(timeInterval:2,repeats:true){[weak self] _ in self?.scanNow()};timer.tolerance=0.4
        self.timer=timer;RunLoop.main.add(timer,forMode:.common)
    }
    static func excluded(_ url:URL,paths:String)->Bool {
        let path=url.standardizedFileURL.path
        return paths.split(separator:";").contains { raw in
            let value=String(raw).trimmingCharacters(in:.whitespacesAndNewlines)
            guard value.hasPrefix("/") || value.hasPrefix("~/") else{return false}
            let excluded=URL(fileURLWithPath:(value as NSString).expandingTildeInPath).standardizedFileURL.path
            return excluded=="/" || path==excluded || path.hasPrefix(excluded+"/")
        }
    }
    private struct EntrySignature:Equatable {
        let directory:Bool,symbolicLink:Bool
        let size:Int64?
        let modified:Date?
    }
    static func differs(_ old:[FileEntry],_ new:[FileEntry],metadata:Bool)->Bool {
        func signatures(_ entries:[FileEntry])->[String:EntrySignature] {
            Dictionary(uniqueKeysWithValues:entries.map{($0.name,EntrySignature(directory:$0.isDirectory,symbolicLink:$0.isSymbolicLink,size:metadata ? $0.size:nil,modified:metadata ? $0.modified:nil))})
        }
        return signatures(old) != signatures(new)
    }
    /// Exposed for deterministic fixture tests; production is driven by activation/timer.
    func requestActivationRefresh() {activationPending=true;scanNow()}
    func scanNow() {
        guard let commander,!inFlight,!commander.busy,commander.window.attachedSheet==nil,NSApp.modalWindow==nil,
              commander.window.isVisible || !commander.remember,
              !((commander.window.firstResponder as? NSTextView)?.isFieldEditor ?? false) else{return}
        let config=commander.runtimeConfig
        let activating=activationPending && config.refreshOnActivate
        guard config.autoRefreshEnabled || activating else{return}
        guard !config.autoRefreshOnlyForeground || NSApp.isActive else{return}
        let targets=[commander.left,commander.right].filter {
            guard !$0.isLoading,!$0.isTreeMode,let url=$0.location.localDirectory else{return false}
            return !Self.excluded(url,paths:config.autoRefreshExcludedPaths)
        }
        guard !targets.isEmpty else{return}
        let requests=targets.map { pane in
            let saved=folderStamps[ObjectIdentifier(pane)]
            let previous=saved?.location == pane.location.identity ? saved?.stamp:nil
            return (pane,pane.location,pane.loadGeneration,pane.refreshListedEntries,previous)
        }
        let showHidden=commander.showHidden,revision=self.revision
        inFlight=true
        queue.async { [weak self] in
            let results=requests.map { pane,location,generation,old,lastStamp in
                let stamp=location.localDirectory.flatMap(Self.stamp)
                let result:Result<[FileEntry]?,Error>=Result {
                    if !activating,!config.autoRefreshMetadata,let stamp,stamp==lastStamp {return nil}
                    return try location.list(showHidden:showHidden)
                }
                return (pane,location,generation,old,stamp,result)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else{return}
                self.inFlight=false;self.completedScans += 1
                guard let commander=self.commander,revision==self.revision,!commander.busy,commander.window.attachedSheet==nil,NSApp.modalWindow==nil,
                      commander.window.isVisible || !commander.remember,
                      !((commander.window.firstResponder as? NSTextView)?.isFieldEditor ?? false),
                      !config.autoRefreshOnlyForeground || NSApp.isActive else{return}
                var committed=false
                for (pane,location,generation,old,stamp,result) in results {
                    guard !pane.isLoading,pane.location==location,pane.loadGeneration==generation else{continue}
                    guard case .success(let listing)=result else{continue}
                    if let listing,Self.differs(old,listing,metadata:activating || config.autoRefreshMetadata) {
                        pane.applyAutoRefreshListing(listing,updateHeader:config.autoRefreshUpdateHeader)
                    }
                    self.folderStamps[ObjectIdentifier(pane)]=stamp.map{CachedFolderStamp(location:location.identity,stamp:$0)}
                    committed=true
                }
                // A busy/sheet/stale result never consumes the pending activation request.
                if committed && activating {self.activationPending=false}
            }
        }
    }
}

extension Pane {
    func applyAutoRefreshListing(_ listing:[FileEntry],updateHeader:Bool) {
        let selected=Set(table.selectedRowIndexes.compactMap { $0>0 && $0<=entries.count ? entries[$0-1].url:nil })
        let scroll=table.enclosingScrollView,origin=table.enclosingScrollView?.contentView.bounds.origin
        applyListing(listing,location:location,updateHeader:updateHeader)
        let surviving=IndexSet(entries.enumerated().compactMap {selected.contains($0.element.url) ? $0.offset+1:nil})
        table.selectRowIndexes(surviving.isEmpty ? IndexSet(integer:0):surviving,byExtendingSelection:false)
        if let scroll,let origin {scroll.contentView.scroll(to:origin);scroll.reflectScrolledClipView(scroll.contentView)}
        updateFooter()
    }
}

private var refreshControllerKey:UInt8=0
extension CommanderController {
    var refreshController:CommanderRefreshController {
        if let value=objc_getAssociatedObject(self,&refreshControllerKey) as? CommanderRefreshController{return value}
        let value=CommanderRefreshController(self);objc_setAssociatedObject(self,&refreshControllerKey,value,.OBJC_ASSOCIATION_RETAIN_NONATOMIC);return value
    }
}
