import AppKit

extension CommanderController {
    /// Escape leaves our path/command field editors without altering file marks.
    /// Other text editors and attached dialogs keep their own Escape behavior.
    func handleFieldEscape(_ event:NSEvent)->Bool {
        guard event.keyCode==53,event.modifierFlags.intersection([.command,.control,.option,.shift]).isEmpty,
              window.attachedSheet==nil,let responder=window.firstResponder else{return false}
        for (index,pane) in [left,right].enumerated() {
            if let editor=pane.path.currentEditor(),responder === editor {
                pane.path.stringValue=pane.location.displayPath;activate(index);return true
            }
        }
        if let editor=commandField.currentEditor(),responder === editor {
            commandField.stringValue="";activate(activeIndex);return true
        }
        return false
    }
}
