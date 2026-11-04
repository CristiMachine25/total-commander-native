import AppKit
import ObjectiveC

extension ShortcutChord {
    init?(event:NSEvent) {
        let named:[UInt16:String]=[36:"RETURN",76:"RETURN",48:"TAB",49:"SPACE",51:"BACKSPACE",53:"ESCAPE",114:"INSERT",115:"HOME",116:"PAGEUP",117:"DELETE",119:"END",121:"PAGEDOWN",123:"LEFT",124:"RIGHT",125:"DOWN",126:"UP",122:"F1",120:"F2",99:"F3",118:"F4",96:"F5",97:"F6",98:"F7",100:"F8",101:"F9",109:"F10",103:"F11",111:"F12",105:"F13",107:"F14",113:"F15",106:"F16",64:"F17",79:"F18",80:"F19",90:"F20",69:"PLUS",78:"MINUS"]
        let punctuation:[String:String] = ["+":"PLUS","-":"MINUS","=":"EQUAL",",":"COMMA",".":"PERIOD","/":"SLASH","\\":"BACKSLASH","[":"LEFTBRACKET","]":"RIGHTBRACKET","'":"APOSTROPHE",";":"SEMICOLON","`":"GRAVE"]
        let character=event.charactersIgnoringModifiers ?? ""
        guard let key=named[event.keyCode] ?? punctuation[character] ?? Self.canonicalKey(character) else{return nil}
        var modifiers:Modifiers=[]
        if event.modifierFlags.contains(.control){modifiers.insert(.control)}
        if event.modifierFlags.contains(.option){modifiers.insert(.option)}
        if event.modifierFlags.contains(.shift){modifiers.insert(.shift)}
        if event.modifierFlags.contains(.command){modifiers.insert(.command)}
        self.init(key:key,modifiers:modifiers)
    }
}

#if !SHORTCUT_SETTINGS_EVENT_TESTS
private var shortcutCacheKey:UInt8=0
private final class ShortcutSettingsCache:NSObject {
    let shortcuts:String,aliases:String,value:ShortcutSettings
    init(shortcuts:String,aliases:String,value:ShortcutSettings){self.shortcuts=shortcuts;self.aliases=aliases;self.value=value}
}
extension CommanderController {
    func configuredShortcuts()throws->ShortcutSettings {
        if let cache=objc_getAssociatedObject(self,&shortcutCacheKey) as? ShortcutSettingsCache,cache.shortcuts==runtimeConfig.customShortcuts,cache.aliases==runtimeConfig.commandAliases{return cache.value}
        let value=try ShortcutSettings.parse(shortcuts:runtimeConfig.customShortcuts,aliases:runtimeConfig.commandAliases)
        objc_setAssociatedObject(self,&shortcutCacheKey,ShortcutSettingsCache(shortcuts:runtimeConfig.customShortcuts,aliases:runtimeConfig.commandAliases,value:value),.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return value
    }
    func handleCustomShortcut(_ event:NSEvent)->Bool {
        guard !runtimeConfig.customShortcuts.isEmpty,window.attachedSheet==nil,
              event.windowNumber==window.windowNumber,
              let responder=window.firstResponder,
              responder === activePane.fileResponder || separateTrees.hasFocus,
              let chord=ShortcutChord(event:event) else{return false}
        do {
            guard let command=try configuredShortcuts().bindings[chord] else{return false}
            // Consume a configured key while busy/loading rather than letting its
            // default action run unexpectedly. Text fields never reach this path.
            guard !busy,!activePane.isLoading else{return true}
            if !dispatchInternalCommand(command){status.stringValue="Configured command is unavailable in this pane: "+command}
            return true
        } catch {status.stringValue=error.localizedDescription;return false}
    }
}
#endif
