import AppKit
extension CommanderController {
    @objc func thumbnailView() {
        guard !busy else{return}
        if !activePane.setThumbnailMode() {showMessage("Thumbnail view","Thumbnails are available in local folders.")}
        else {recordManualViewChange(in:activePane);window.makeFirstResponder(activePane.fileResponder)}
    }
    @objc func treeView() {
        guard !busy else{return}
        let pane=activePane,other=otherPane,root:PaneLocation
        switch other.location {
        case .local(let url):root = .local((try? url.resourceValues(forKeys:[.volumeURLKey]).volume) ?? URL(fileURLWithPath:"/"))
        case .archive(let archive,_):root = .archive(archive,path:"")
        case .ftp(let client,_):root = .ftp(client,path:"/")
        }
        pane.onTreeOpen={ [weak self,weak other] location in guard let self,let other else{return};self.navigate(location,pane:other,focus:false)}
        pane.setTreeMode(root:root);window.makeFirstResponder(pane.fileResponder)
    }
    func permitFileAction()->Bool {
        if activePane.isTreeMode || separateTrees.hasFocus {NSSound.beep();status.stringValue="Open a directory from the tree in the opposite pane before managing its files.";return false}
        return true
    }
}
