import AppKit
@main struct PaneTabShortcutTests {
    static func main()throws {
        let app=NSApplication.shared;app.setActivationPolicy(.prohibited)
        let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("pane-tab-shortcuts-"+UUID().uuidString)
        try fm.createDirectory(at:root,withIntermediateDirectories:false);defer{try? fm.removeItem(at:root)}
        let a=root.appendingPathComponent("A"),b=root.appendingPathComponent("B")
        try fm.createDirectory(at:a,withIntermediateDirectories:false);try fm.createDirectory(at:b,withIntermediateDirectories:false)
        let c=CommanderController(initial:a,remember:false),p=c.left
        _=c.openLocationInNewTab(.local(b),background:true)
        var checks=0
        func check(_ condition:Bool,_ reason:String){checks += 1;precondition(condition,reason)}
        func event(_ flags:NSEvent.ModifierFlags,key:UInt16=48)->NSEvent {NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:c.window.windowNumber,context:nil,characters:flags.contains(.shift) ? "\u{19}":"\t",charactersIgnoringModifiers:"\t",isARepeat:false,keyCode:key)!}
        c.fullView();c.window.makeFirstResponder(p.table)
        check(p.table.performKeyEquivalent(with:event([.control,.shift])),"Full-table CtrlShiftTab is claimed before AppKit traversal")
        check(p.selectedTab==1 && c.window.firstResponder === p.table,"Previous tab wraps and retains Full-pane focus")
        check(p.table.performKeyEquivalent(with:event([.control])) && p.selectedTab==0,"Full-table CtrlTab forwards next-tab command")
        check(c.handlePaneTabShortcut(event([.control,.shift])) && p.selectedTab==1,"Local-monitor handler routes reverse tab from Full")
        c.briefView();c.window.makeFirstResponder(p.briefGrid)
        check(c.handlePaneTabShortcut(event([.control])) && p.selectedTab==0,"Local-monitor handler routes forward tab from Brief")
        c.window.makeFirstResponder(p.path);let field=c.window.fieldEditor(false,for:p.path)
        check(field != nil && !c.handlePaneTabShortcut(event([.control,.shift])) && p.selectedTab==0,"Path editing retains native traversal")
        check(!p.table.performKeyEquivalent(with:event([.control,.shift])) && p.selectedTab==0,"Nonfocused table cannot steal text-field tab shortcut")
        c.window.makeFirstResponder(p.fileResponder)
        check(!c.handlePaneTabShortcut(event([.shift])) && !c.handlePaneTabShortcut(event([.command,.shift])),"Unrelated Tab modifier combinations retain native handling")
        c.busy=true;check(c.handlePaneTabShortcut(event([.control,.shift])) && p.selectedTab==0,"Busy pane consumes shortcut without switching")
        c.busy=false;c.fullView();c.window.makeFirstResponder(p.table)
        let before=p.selectedTab;p.table.keyDown(with:event([.control,.shift]));check(p.selectedTab != before,"Ordinary keyDown route remains functional")
        print("PASS: \(checks) pane-tab shortcut assertions")
    }
}
