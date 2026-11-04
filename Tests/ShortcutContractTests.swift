import AppKit

@main struct ShortcutContractTests {
    static var checks=0
    static func check(_ value:Bool,_ message:String) {
        checks += 1; precondition(value,message)
    }
    static func main() throws {
        let contract=ShortcutContract.bindings
        check(Set(contract.map{"\($0.key):\($0.modifiers.rawValue)"}).count == contract.count,"unique exact routes")
        for binding in contract {
            check(ShortcutContract.action(key:binding.key,modifiers:binding.modifiers) == binding.action,binding.reference)
            check(ShortcutContract.action(key:binding.key,modifiers:binding.modifiers.union([.capsLock,.numericPad,.function])) == binding.action,"ignore event metadata")
            for mask in 0..<16 {
                var flags:NSEvent.ModifierFlags=[]
                for (i,flag) in [NSEvent.ModifierFlags.control,.shift,.option,.command].enumerated() where mask & (1<<i) != 0 { flags.insert(flag) }
                let expected=contract.first{$0.key == binding.key && $0.modifiers == flags}?.action
                check(ShortcutContract.action(key:binding.key,modifiers:flags) == expected,"exact modifier matching, no destructive fallthrough")
            }
        }
        check(ShortcutContract.action(key:96,modifiers:[.shift]) == "copySameFolder","ShiftF5 is same-folder copy")
        check(ShortcutContract.action(key:98,modifiers:[.shift]) == "mkdirTarget","ShiftF7 target folder")
        check(ShortcutContract.action(key:96,modifiers:[.option,.shift]) == nil,"move-to-archive unsupported, never ordinary copy")
        check(ShortcutContract.action(key:100,modifiers:[.shift]) == nil,"ShiftF8 must not become ordinary Trash")
        check(ShortcutContract.action(key:126,modifiers:[.control,.shift]) == "childTargetTab","CtrlShiftUp other pane")
        check(ShortcutContract.action(key:48,modifiers:[.control,.shift]) == "previousTab","CtrlShiftTab backwards")
        let current:Set<String>=["directory","a"], files:Set<String>=["a","b"]
        check(ShortcutContract.selection(current:current,files:files,operation:"invertFiles") == ["directory","b"],"file-only invert preserves marked folder")
        check(ShortcutContract.selection(current:current,files:files,operation:"unselectFiles") == ["directory"],"file-only deselect")
        check(ShortcutContract.selection(current:current,files:files,operation:"selectFiles") == ["directory","a","b"],"file-only select")
        for name in ["", ".", "..", "a/b", "a\0b"] { check(!ShortcutContract.validCopyName(name),"invalid same-folder name") }
        for name in ["copy.txt", "a b", "é.txt"] { check(ShortcutContract.validCopyName(name),"valid same-folder name") }
        if CommandLine.arguments.count > 1 {
            let reference=try String(contentsOfFile:CommandLine.arguments[1],encoding:.utf8)
            for text in ["SHIFT+F5", "SHIFT+F7", "CTRL+SHIFT+U", "CTRL+SHIFT+A", "CTRL+SHIFT+UP", "CTRL+SHIFT+NUM -", "ALT+NUM +"] {
                check(reference.contains(text),"original bundled keyboard reference: "+text)
            }
        }
        print("Shortcut contract: \(checks) checks passed")
    }
}
