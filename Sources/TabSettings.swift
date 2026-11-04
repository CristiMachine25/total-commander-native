import AppKit

/// Mouse behavior is kept on the actual segmented control, not a global event monitor.
final class CommanderTabControl:NSSegmentedControl {
    var closeOnDoubleClick:(()->Bool)?
    var onClose:((Int)->Void)?
    var contextMenu:((Int)->NSMenu?)?
    override func mouseDown(with event:NSEvent) {
        super.mouseDown(with:event)
        handleCompletedClick(count:event.clickCount,segment:selectedSegment)
    }
    func handleCompletedClick(count:Int,segment:Int) {
        if count==2,segment>=0,closeOnDoubleClick?()==true {onClose?(segment)}
    }
    func segment(at point:NSPoint)->Int? {
        guard bounds.contains(point) else{return nil}
        var x:CGFloat=0
        for index in 0..<segmentCount {
            let width=width(forSegment:index)
            if point.x>=x,point.x<x+width{return index};x += width
        }
        return nil
    }
    override func menu(for event:NSEvent)->NSMenu? {
        guard let index=segment(at:convert(event.locationInWindow,from:nil)) else{return nil}
        return contextMenu?(index)
    }
}
private final class TabMenuAction:NSObject {
    let action:()->Void
    init(_ action:@escaping ()->Void){self.action=action}
    @objc func invoke(){action()}
}
extension Pane {
    func insertTab(_ location:PaneLocation,at index:Int) {
        lockedTabRoots=Dictionary(uniqueKeysWithValues:lockedTabRoots.map{($0.key>=index ? $0.key+1 : $0.key,$0.value)})
        tabs.insert(location,at:index)
        if index<=selectedTab {selectedTab += 1}
    }
    func removeTab(at index:Int) {
        lockedTabRoots=Dictionary(uniqueKeysWithValues:lockedTabRoots.filter{$0.key != index}.map{($0.key>index ? $0.key-1 : $0.key,$0.value)})
        tabs.remove(at:index)
        if index<selectedTab {selectedTab -= 1}
        selectedTab=min(selectedTab,tabs.count-1)
    }
    func retainTabs(_ indices:[Int]) {
        let prior=tabs,locks=lockedTabRoots,oldSelected=selectedTab
        tabs=indices.map{prior[$0]};selectedTab=indices.firstIndex(of:oldSelected) ?? 0
        lockedTabRoots=Dictionary(uniqueKeysWithValues:indices.enumerated().compactMap{new,old in locks[old].map{(new,$0)}})
        updateTabs()
    }
    func lockTab(_ index:Int)->Bool {
        guard tabs.indices.contains(index),let root=tabs[index].localDirectory else{return false}
        lockedTabRoots[index]=root;updateTabs();return true
    }
    var savedLocalTabLocks:[String:String] {
        let localIndices=tabs.indices.filter{tabs[$0].localDirectory != nil}
        return Dictionary(uniqueKeysWithValues:localIndices.enumerated().compactMap{saved,index in lockedTabRoots[index].map{(String(saved),$0.path)}})
    }
    func restoreLocalTabLocks(_ saved:[String:String]) {
        lockedTabRoots=Dictionary(uniqueKeysWithValues:saved.compactMap{key,path -> (Int,URL)? in
            guard let index=Int(key),tabs.indices.contains(index),let root=tabs[index].localDirectory,root.standardizedFileURL.path==URL(fileURLWithPath:path).standardizedFileURL.path else{return nil}
            return(index,root)
        });updateTabs()
    }
}
extension CommanderController {
    func tabContextMenu(_ index:Int,pane:Pane)->NSMenu? {
        guard !busy,!pane.isLoading,window.attachedSheet==nil,pane.tabs.indices.contains(index) else{return nil}
        let menu=NSMenu();menu.autoenablesItems=false
        func add(_ title:String,enabled:Bool=true,_ action:@escaping ()->Void) {
            let target=TabMenuAction(action),item=NSMenuItem(title:title,action:#selector(TabMenuAction.invoke),keyEquivalent:"")
            item.target=target;item.representedObject=target;item.isEnabled=enabled;menu.addItem(item)
        }
        let locked=pane.lockedTabRoots[index] != nil
        add(locked ? "Unlock tab" : "Lock tab",enabled:pane.tabs[index].localDirectory != nil){[weak self,weak pane] in
            guard let self,let pane,!self.busy,!pane.isLoading,pane.tabs.indices.contains(index) else{return}
            if pane.lockedTabRoots[index] != nil {pane.lockedTabRoots[index]=nil;pane.updateTabs()} else {_=pane.lockTab(index)}
        }
        add("Close tab",enabled:!locked && pane.tabs.count>1){[weak self,weak pane] in guard let pane else{return};self?.closeFolderTab(index,pane:pane)}
        add("Close other unlocked tabs",enabled:pane.tabs.count>1){[weak self,weak pane] in guard let self,let pane else{return};self.closeOtherTabs(pane,keeping:index)}
        return menu
    }
    func closeFolderTab(_ index:Int,pane:Pane) {
        guard !busy,!pane.isLoading,pane.tabs.count>1,pane.tabs.indices.contains(index) else{return}
        guard pane.lockedTabRoots[index]==nil else{status.stringValue="Unlock this tab before closing it.";return}
        if index != pane.selectedTab {pane.removeTab(at:index);pane.updateTabs();return}
        let nextIndex=index==pane.tabs.count-1 ? index-1 : index+1,next=pane.tabs[nextIndex]
        navigate(next,pane:pane,recordHistory:false,storeTab:false) {success in
            if success {pane.selectedTab=nextIndex;pane.removeTab(at:index)}
            pane.updateTabs()
        }
    }
    func closeOtherTabs(_ pane:Pane,keeping index:Int?=nil) {
        guard !busy,!pane.isLoading,window.attachedSheet==nil else{return}
        if let index {
            guard pane.tabs.indices.contains(index) else{return}
            activate(pane === left ? 0 : 1)
            if index != pane.selectedTab {
                let snapshot=pane.tabs
                navigate(snapshot[index],pane:pane,recordHistory:false,storeTab:false) { [weak self,weak pane] success in
                    guard let self,let pane,success,pane.tabs==snapshot else{return}
                    pane.selectedTab=index;pane.updateTabs()
                    self.closeOtherTabs(pane)
                }
                return
            }
        }
        let before=pane.tabs,selected=pane.selectedTab
        let retained=pane.tabs.indices.filter{$0==selected || pane.lockedTabRoots[$0] != nil}
        guard retained.count<before.count else{return}
        let commit={ [weak self,weak pane] in
            guard let self,let pane,!self.busy,!pane.isLoading,pane.tabs==before,pane.selectedTab==selected else{return}
            pane.retainTabs(retained)
        }
        if runtimeConfig.confirmCloseAllTabs {
            let alert=NSAlert();alert.messageText="Close other unlocked tabs?";alert.informativeText="The current tab and locked tabs will remain open.";alert.addButton(withTitle:"Close Tabs");alert.addButton(withTitle:"Cancel")
            alert.beginSheetModal(for:window){if $0 == .alertFirstButtonReturn {commit()}}
        } else {commit()}
    }
}
