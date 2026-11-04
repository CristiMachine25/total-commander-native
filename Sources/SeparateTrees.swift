import AppKit
import ObjectiveC

private var separateTreesKey:UInt8=0

/// Original separate tree states: off, one tree following active pane, two trees.
final class SeparateTreeCoordinator {
    weak var commander:CommanderController?
    let leftView=DirectoryTreeView(frame:.zero)
    let rightView=DirectoryTreeView(frame:.zero)
    private(set) var state=0
    var hasFocus:Bool {guard let responder=commander?.window.firstResponder else{return false};return (state>0 && responder === leftView.responder) || (state==2 && responder === rightView.responder)}
    var focusedLocation:PaneLocation? {guard let responder=commander?.window.firstResponder else{return nil};if responder === leftView.responder{return leftView.selectedLocation};if responder === rightView.responder{return rightView.selectedLocation};return nil}
    private var leftRoot:PaneLocation?,rightRoot:PaneLocation?
    private var settingUp=false
    init(_ commander:CommanderController){
        self.commander=commander
        leftView.isHidden=true;rightView.isHidden=true
        leftView.widthAnchor.constraint(greaterThanOrEqualToConstant:180).isActive=true
        rightView.widthAnchor.constraint(greaterThanOrEqualToConstant:180).isActive=true
        leftView.widthAnchor.constraint(equalToConstant:220).isActive=true
        rightView.widthAnchor.constraint(equalToConstant:220).isActive=true
        leftView.onOpenLocation={ [weak self] location in
            guard let self,let commander=self.commander else{return}
            let target=self.state==1 ? commander.activePane:commander.left
            commander.navigate(location,pane:target)
        }
        rightView.onOpenLocation={ [weak self] location in guard let commander=self?.commander else{return};commander.navigate(location,pane:commander.right) }
    }
    func setState(_ value:Int){
        state=min(2,max(0,value));leftView.isHidden=state==0;rightView.isHidden=state != 2
        if state==0{leftView.cancel();rightView.cancel();leftRoot=nil;rightRoot=nil}
        if state==1{rightView.cancel();rightRoot=nil}
        if let commander,commander.remember {UserDefaults.standard.set(state,forKey:"separateTreeState")}
        refreshRoots()
    }
    func restore(){if commander?.remember==true{setState(UserDefaults.standard.integer(forKey:"separateTreeState"))}}
    func cycle(){setState((state+1)%3)}
    func refreshRoots(){
        guard state>0,!settingUp,let commander else{return};settingUp=true;defer{settingUp=false}
        func root(_ location:PaneLocation)->PaneLocation{
            switch location {
            case .local(let url):
                let volume=(try? url.resourceValues(forKeys:[.volumeURLKey]))?.volume
                return .local(volume ?? URL(fileURLWithPath:"/"))
            case .archive(let session,_):return .archive(session,path:"")
            case .ftp(let client,_):return .ftp(client,path:"/")
            }
        }
        let leftPane=state==1 ? commander.activePane:commander.left,nextLeft=root(leftPane.location)
        leftView.pane=leftPane;leftView.applyConfiguration(leftPane.configuration)
        if leftRoot != nextLeft{leftRoot=nextLeft;leftView.setRoot(nextLeft,showHidden:commander.showHidden)}
        leftView.reveal(leftPane.location)
        if state==2 {
            let rightPane=commander.right,nextRight=root(rightPane.location)
            rightView.pane=rightPane;rightView.applyConfiguration(rightPane.configuration)
            if rightRoot != nextRight{rightRoot=nextRight;rightView.setRoot(nextRight,showHidden:commander.showHidden)}
            rightView.reveal(rightPane.location)
        }
    }
}
extension CommanderController {
    var separateTrees:SeparateTreeCoordinator {
        if let value=objc_getAssociatedObject(self,&separateTreesKey) as? SeparateTreeCoordinator{return value}
        let value=SeparateTreeCoordinator(self);objc_setAssociatedObject(self,&separateTreesKey,value,.OBJC_ASSOCIATION_RETAIN_NONATOMIC);return value
    }
    @objc func cycleSeparateTrees(){separateTrees.cycle()}
}
