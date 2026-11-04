import Foundation

@main struct ReferenceMenuTests {
    static var count=0
    static func check(_ value:@autoclosure ()throws->Bool,_ message:String)throws{count += 1;if try !value(){throw NSError(domain:"ReferenceMenuTests",code:count,userInfo:[NSLocalizedDescriptionKey:message])}}
    static func rejects(_ message:String,_ work:()throws->Void)throws{var rejected=false;do{try work()}catch{rejected=true};try check(rejected,message)}
    static func main()throws{
        let resources=URL(fileURLWithPath:CommandLine.arguments.count>1 ? CommandLine.arguments[1] : "outputs/TotalCommanderNative/Resources")
        let menu=try String(contentsOf:resources.appendingPathComponent("WCMD_ENG.MNU"),encoding:.windowsCP1252),inc=try String(contentsOf:resources.appendingPathComponent("TOTALCMD.INC"),encoding:.windowsCP1252)
        let catalog=try ReferenceMenuCatalog(menuText:menu,commandsText:inc)
        try check(catalog.topLevelTitles==["Files","Mark","Commands","Net","Show","Configuration","Start","Help"],"Original shipped top-level menu order including Start marker")
        try check(catalog.roots.contains(.helpBreak) && catalog.roots.contains(.startMenu),"Dynamic Start and Help alignment directives preserved")
        let files=catalog.popup("&Files")!
        guard case .command(let first,let token,let id)=files[0] else{fatalError("Missing first item")}
        try check(first.raw=="&Change Attributes..." && first.title=="Change Attributes..." && first.mnemonic=="C" && token=="cm_SetAttrib" && id==502,"Exact first original label/mnemonic/symbol resolves INC ID")
        guard case .command(let pack,_,let packID)=files[1] else{fatalError()}
        try check(pack.raw=="&Pack...\\tAlt+F5" && pack.title=="Pack..." && pack.shortcut=="Alt+F5" && packID==508,"Escaped shortcut parsed separately without changing raw source label")
        let printPopup=files.first {if case .popup(let label,_)=$0{return label.title=="Print"};return false}!
        guard case .popup(let printLabel,let printItems)=printPopup else{fatalError()}
        try check(printLabel.raw=="Prin&t" && printLabel.mnemonic=="t" && printItems.count==3,"Nested Print popup retains original children")
        guard case .command(let printLast,_,let printID)=printItems[2] else{fatalError()}
        try check(printLast.title=="File Contents" && printLast.shortcut=="Ctrl+F9" && printID==504,"Nested symbolic command resolves correctly")
        let separate=catalog.popup("Show")!.first {if case .popup(let label,_)=$0{return label.title=="Separate Tree"};return false}!
        guard case .popup(let separateLabel,let separateItems)=separate else{fatalError()}
        try check(separateLabel.shortcut=="Ctrl+Shift+F8" && separateItems.count==3,"Popup shortcut and three numeric submenu routes retained")
        try check(catalog.id(for:"CM_SRCBYNAME")==321 && catalog.id(for:"cm_srcbyname")==321 && catalog.id(for:"24340")==24340,"Original aliases are case insensitive and numeric commands supported")
        try check(catalog.aliasesByID[24340]?.contains("cm_Exit")==true,"Original command spelling registry preserved")
        func flattened(_ nodes:[ReferenceMenuNode])->[(ReferenceMenuLabel,String,Int?)] {
            nodes.flatMap{node -> [(ReferenceMenuLabel,String,Int?)] in
                switch node {case .command(let label,let token,let id):return[(label,token,id)];case .popup(_,let children):return flattened(children);default:return[]}
            }
        }
        let all=flattened(catalog.roots)
        let originalCount=menu.components(separatedBy:.newlines).filter{$0.trimmingCharacters(in:.whitespaces).hasPrefix("MENUITEM \"")}.count
        try check(all.count==originalCount && all.count>90,"Every original shipped command is represented exactly once")
        try check(all.allSatisfy{$0.2 != nil},"All shipped menu tokens resolve to original command IDs")
        try check(all.first{$0.2==2022}?.0.raw=="Compare B&y Content...","Numeric original command label preserved exactly")
        try check(all.last?.0.raw=="&About Total Commander..." && all.last?.2==690,"Final original Help label/order retained")
        try check(files.filter{if case .separator=$0{return true};return false}.count==2,"Original separator positions retained")
        let escaped=ReferenceMenuLabel("Rock && &Roll\\tCtrl+R")
        try check(escaped.title=="Rock & Roll" && escaped.mnemonic=="R" && escaped.shortcut=="Ctrl+R" && escaped.displayedTitle=="Rock & Roll\tCtrl+R","Escaped ampersands and mnemonic markers handled")
        let custom=try ReferenceMenuCatalog(menuText:"POPUP \"&X\"\nMENUITEM \"Un&known\", cm_missing\nMENUITEM \"Alias\", cm_alias\nEND_POPUP",commandsText:"cm_one=7;First\ncm_alias=7;Second")
        try check(custom.aliasesByID[7]==["cm_one","cm_alias"],"Multiple symbols for one ID preserve aliases")
        guard case .command(_,_,let missing)=custom.popup("X")![0] else{fatalError()}
        try check(missing==nil && !ReferenceCommandRouting.isSupported(missing),"Unresolved tokens remain visible and disabled")
        try check(!ReferenceCommandRouting.isSupported(502) && !ReferenceCommandRouting.isSupported(2204) && !ReferenceCommandRouting.isSupported(650),"Unavailable attributes/admin shares/update commands are disabled")
        try check(ReferenceCommandRouting.isSupported(501) && ReferenceCommandRouting.isSupported(508) && ReferenceCommandRouting.isSupported(550) && ReferenceCommandRouting.isSupported(304),"Real search/archive/FTP/QuickView routes advertised")
        try check(ReferenceCommandRouting.supportedIDs.allSatisfy{catalog.aliasesByID[$0] != nil},"Every enabled capability uses an actual original command ID")
        try check(!ReferenceCommandRouting.selectedIDs.contains(501),"Search remains available in an empty directory")
        try check(ReferenceCommandRouting.unsupportedReason(650).contains("650"),"Unavailable menu tooltip identifies original command")
        try rejects("Missing popup terminator rejected"){_=try ReferenceMenuCatalog(menuText:"POPUP \"X\"",commandsText:"")}
        try rejects("Unexpected terminator rejected"){_=try ReferenceMenuCatalog(menuText:"END_POPUP",commandsText:"")}
        try rejects("Unclosed label rejected"){_=try ReferenceMenuCatalog(menuText:"POPUP \"X",commandsText:"")}
        try rejects("Missing command rejected"){_=try ReferenceMenuCatalog(menuText:"MENUITEM \"X\",",commandsText:"")}
        try rejects("Unknown directive rejected"){_=try ReferenceMenuCatalog(menuText:"BROKEN",commandsText:"")}
        try rejects("Conflicting alias rejected"){_=try ReferenceMenuCatalog(menuText:"",commandsText:"cm_alias=7\nCM_ALIAS=8")}
        let bundled=try ReferenceMenuCatalog.load(bundle:Bundle(path:resources.deletingLastPathComponent().path) ?? .main)
        _=bundled // Absence is a supported fallback for source/test runs.
        let fixture=FileManager.default.temporaryDirectory.appendingPathComponent("MenuCache-"+UUID().uuidString+".bundle")
        try FileManager.default.createDirectory(at:fixture,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:fixture)}
        try menu.write(to:fixture.appendingPathComponent("WCMD_ENG.MNU"),atomically:true,encoding:.windowsCP1252)
        try inc.write(to:fixture.appendingPathComponent("TOTALCMD.INC"),atomically:true,encoding:.windowsCP1252)
        let bundle=Bundle(path:fixture.path)!
        let loaded=try ReferenceMenuCatalog.load(bundle:bundle)!
        try check(loaded.roots==catalog.roots,"Cached loader preserves original resource structure")
        try FileManager.default.removeItem(at:fixture.appendingPathComponent("TOTALCMD.INC"))
        try check(try ReferenceMenuCatalog.load(bundle:bundle)?.roots==loaded.roots,"Repeated menus use cached bundle resources without reparsing")
        try check(ReferenceCommandRouting.isSupported(581),"Configuration-file editor is routed through original ID581")
        print("PASS: \(count) reference menu assertions; \(all.count) original items, \(ReferenceCommandRouting.supportedIDs.count) supported command IDs")
    }
}
