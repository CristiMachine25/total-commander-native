import AppKit

extension Pane {
    /// Context clicks outside the effective selection replace it. Clicking a member
    /// preserves the whole marked/multiselected group; empty space never targets it.
    func contextMenu(forRow row:Int)->NSMenu? {
        guard !isLoading,!isTreeMode,contextMenuAllowed?() != false else{return nil}
        onActivate?();view.window?.makeFirstResponder(fileResponder)
        if row>0,row<=entries.count {
            let url=entries[row-1].url
            let member = marked.isEmpty ? table.selectedRowIndexes.contains(row):marked.contains(url)
            if !member {marked.removeAll();table.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)}
            else if !marked.isEmpty {table.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)}
        } else if row == 0 {
            marked.removeAll();table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
        }
        let selection=table.selectedRowIndexes
        table.reloadData();table.selectRowIndexes(selection,byExtendingSelection:false);updateFooter();briefGrid.needsDisplay=true;thumbnailGrid.needsDisplay=true
        return onContextMenu?(row>0 && row<=entries.count ? row:0)
    }
}

private final class FileContextSnapshot:NSObject {
    weak var pane:Pane?
    let identity:String
    let selection:[URL]
    let hasTarget:Bool
    init(_ pane:Pane,hasTarget:Bool){self.pane=pane;identity=pane.location.identity;selection=pane.selectedEntries.map(\.url);self.hasTarget=hasTarget}
}

extension CommanderController {
    func installFileContextMenus() {
        for pane in [left,right] {
            pane.contextMenuAllowed={ [weak self] in guard let self else{return false};return !self.busy && self.window.attachedSheet==nil }
            pane.onContextMenu={ [weak self,weak pane] row in
                guard let self,let pane,!self.busy,!pane.isLoading else{return nil}
                self.activate(pane === self.left ? 0:1,focus:false)
                return self.fileContextMenu(hasTarget:row>0)
            }
        }
    }
    private func contextWritable(_ location:PaneLocation)->Bool {
        guard case .archive(let session,_)=location else{return true}
        func writable(_ origin:ArchiveWritebackOrigin)->Bool {if case .nested(let parent,_,let ancestor,_)=origin{return parent.isWritableZIP && writable(ancestor)};return true}
        guard session.isWritableZIP,let origin=try? archiveOrigin(session) else{return false}
        return writable(origin)
    }
    func fileContextMenu(hasTarget:Bool)->NSMenu {
        let menu=NSMenu(title:"File context");menu.autoenablesItems=false
        let pane=activePane,entries=hasTarget ? pane.selectedEntries:[],single=entries.count==1
        let available = !busy && !pane.isLoading && !pane.isTreeMode
        let writable=contextWritable(pane.location),targetWritable=contextWritable(otherPane.location)
        let snapshot=FileContextSnapshot(pane,hasTarget:hasTarget)
        func item(_ title:String,_ tag:Int,_ enabled:Bool=true) {
            let item=NSMenuItem(title:title,action:#selector(fileContextAction(_:)),keyEquivalent:"")
            item.target=self;item.tag=tag;item.isEnabled=available && enabled;item.representedObject=snapshot;menu.addItem(item)
        }
        if hasTarget {
            item("Open",1,single)
            item("View",2,single && entries.first?.isDirectory == false)
            item("Edit",3,single && entries.first?.isDirectory == false && writable)
            menu.addItem(.separator())
            let canTransfer = !entries.isEmpty && !otherPane.isLoading && !otherPane.isTreeMode && targetWritable
            item("Copy to other pane…",4,canTransfer);item("Move to other pane…",5,canTransfer && writable)
            item("Rename…",6,single && writable)
            let deletion:String
            switch pane.location {case .local:deletion="Move to Trash…";case .archive:deletion="Delete from archive…";case .ftp:deletion="Delete from server…"}
            item(deletion,7,!entries.isEmpty && writable)
            menu.addItem(.separator());item("Copy full paths",8,!entries.isEmpty)
            item("Properties",9,single && pane.location.localDirectory != nil)
            menu.addItem(.separator())
        }
        item("New folder…",10,writable);item("Refresh",11)
        return menu
    }
    @objc func fileContextAction(_ sender:NSMenuItem) {
        guard sender.isEnabled,!busy,!activePane.isLoading,
              let snapshot=sender.representedObject as? FileContextSnapshot,
              snapshot.pane === activePane,snapshot.identity==activePane.location.identity,
              !snapshot.hasTarget || snapshot.selection==activePane.selectedEntries.map(\.url) else {
            status.stringValue="The context changed. Open the file menu again.";return
        }
        switch sender.tag {
        case 1:openCurrent()
        case 2:viewFile(editable:false)
        case 3:viewFile(editable:true)
        case 4:transfer(move:false)
        case 5:transfer(move:true)
        case 6:renameCurrent()
        case 7:trash()
        case 8:copyFullNames()
        case 9:fileProperties()
        case 10:makeFolder()
        case 11:refreshSource()
        default:break
        }
    }
}
