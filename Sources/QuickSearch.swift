import Foundation

enum QuickSearchMatcher {
    static func matches(_ name:String,query:String,beginning:Bool,ending:Bool)->Bool {
        guard !query.isEmpty else{return true}
        let name=name.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:.current)
        let query=query.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:.current)
        if ending,let dot=query.firstIndex(of:".") {
            let stem=String(query[..<dot]),ext=String(query[query.index(after:dot)...])
            let actual=(name as NSString).deletingPathExtension,actualExt=(name as NSString).pathExtension
            return (beginning ? actual==stem : actual.hasSuffix(stem)) && actualExt.hasPrefix(ext)
        }
        return beginning ? name.hasPrefix(query) : name.contains(query)
    }
}
#if !QUICK_SEARCH_TEST
import AppKit
extension CommanderController {
    func handleQuickSearch(_ event:NSEvent)->Bool {
        guard !activePane.isTreeMode,!separateTrees.hasFocus else{return false}
        let mods=event.modifierFlags.intersection([.control,.option,.shift,.command])
        let expected:NSEvent.ModifierFlags
        switch runtimeConfig.quickSearchMode {
        case .disabled:return false
        case .letters:expected=[]
        case .alt:expected=[.option]
        case .ctrlAlt:expected=[.control,.option]
        }
        guard mods.subtracting(.shift)==expected else{return false}
        let now=Date.timeIntervalSinceReferenceDate
        if now-quickSearchTime>2 {quickSearchText=""}
        if event.keyCode==51,!quickSearchText.isEmpty {quickSearchText.removeLast()}
        else {
            guard let text=event.charactersIgnoringModifiers,!text.isEmpty,text.unicodeScalars.allSatisfy({!CharacterSet.controlCharacters.contains($0) && $0.value<0xF700}),text != " " else{return false}
            quickSearchText += text
        }
        quickSearchTime=now
        guard let index=activePane.entries.firstIndex(where:{QuickSearchMatcher.matches($0.name,query:quickSearchText,beginning:runtimeConfig.quickSearchMatchBeginning,ending:runtimeConfig.quickSearchMatchEnding)}) else {
            NSSound.beep();status.stringValue="Quick search: "+quickSearchText+" — no match";return true
        }
        activePane.table.selectRowIndexes(IndexSet(integer:index+1),byExtendingSelection:false)
        activePane.table.scrollRowToVisible(index+1);activePane.updateFooter()
        status.stringValue="Quick search: "+quickSearchText
        return true
    }
}
#endif
