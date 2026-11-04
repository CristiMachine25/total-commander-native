import AppKit
@main struct HistorySettingsTests {
    static func main()throws {
        let app=NSApplication.shared;app.setActivationPolicy(.prohibited)
        var checks=0
        func check(_ value:Bool,_ reason:String){checks += 1;precondition(value,reason)}
        let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("history-settings-"+UUID().uuidString)
        try fm.createDirectory(at:root,withIntermediateDirectories:false);defer{try? fm.removeItem(at:root)}
        let a=root.appendingPathComponent("A"),b=root.appendingPathComponent("B"),cURL=root.appendingPathComponent("C")
        for d in [a,b,cURL]{try fm.createDirectory(at:d,withIntermediateDirectories:false)}
        let suite="history-test-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
        defer{defaults.removePersistentDomain(forName:suite)}
        var profile=FTPProfile();profile.host="example.invalid";profile.username="private-user"
        let ftp=try FTPClient(profile:profile,password:"private-password")
        let mixed:[PaneLocation]=[.local(root),.ftp(ftp,path:"/private"),.local(a),.local(b)]
        check(DirectoryHistorySettings.localPaths(mixed,limit:2)==[a.path,b.path],"Only newest local entries within saved cap")
        DirectoryHistorySettings.save(left:mixed,right:[.local(cURL)],limit:3,defaults:defaults)
        let restored=DirectoryHistorySettings.restore(defaults:defaults,limit:3)
        check(restored.left==[.local(root),.local(a),.local(b)] && restored.right==[.local(cURL)],"Separate pane history roundtrip")
        let record=defaults.dictionary(forKey:DirectoryHistorySettings.key)!
        check(!String(describing:record).contains("private-user") && !String(describing:record).contains("private-password") && !String(describing:record).contains("example.invalid"),"Provider identity and password excluded")
        check(DirectoryHistorySettings.restore(defaults:defaults,limit:1).left==[.local(b)],"Restore honors current saved cap")
        check(DirectoryHistorySettings.locations(["relative","ftp://secret@host/path","/ok\0bad",a.path],limit:10)==[.local(a)],"Reject relative URI and NUL persisted paths")
        check(DirectoryHistorySettings.locations([1,2],limit:10).isEmpty,"Malformed type ignored")
        check(DirectoryHistorySettings.locations(Array(repeating:a.path,count:201),limit:200).isEmpty,"Oversized stored record ignored")
        check(DirectoryHistorySettings.locations([String(repeating:"/",count:32769)],limit:2).isEmpty,"Oversized path ignored")
        defaults.set("bad",forKey:DirectoryHistorySettings.key)
        check(DirectoryHistorySettings.restore(defaults:defaults,limit:2).left.isEmpty,"Malformed top-level value ignored")
        DirectoryHistorySettings.save(left:mixed,right:[],limit:200,defaults:defaults)
        DirectoryHistorySettings.clear(defaults:defaults)
        check(defaults.object(forKey:DirectoryHistorySettings.key)==nil,"Delete saved history removes only saved record")
        let c=CommanderController(initial:root,remember:false)
        c.runtimeConfig.historyMaximumShown=2;c.runtimeConfig.historyShowIcons=false
        c.navigate(a);c.navigate(b);c.navigate(cURL)
        let menu=c.makeDirectoryHistoryMenu()
        check(menu.numberOfItems==2 && menu.items.map(\.title)==[b.path,a.path],"History menu newest-first and separate show cap")
        check(menu.items.allSatisfy{$0.image==nil},"Icons disabled leaves menu plain")
        c.runtimeConfig.historyShowIcons=true
        check(c.makeDirectoryHistoryMenu().items.allSatisfy{$0.image != nil},"Icons enabled creates native directory symbols")
        c.left.backHistory.append(.ftp(ftp,path:"/archive"))
        check(c.makeDirectoryHistoryMenu().items.first?.image != nil,"Provider history has icon in memory")
        c.left.backHistory.removeLast()
        c.shortcutHistorySelected(menu.items[1])
        check(c.left.location == .local(a),"Menu routes selected PaneLocation to navigation")
        c.backFolder();check(c.left.location == .local(cURL),"Back navigation remains valid after history menu jump")
        c.forwardFolder();check(c.left.location == .local(a),"Forward navigation remains valid")
        c.openLocationInNewTab(.local(b),pane:c.left)
        let tabs=c.left.tabs,back=c.left.backHistory
        c.runtimeConfig.historyMaximumShown=1
        check(c.makeDirectoryHistoryMenu().numberOfItems==1 && c.left.tabs==tabs && c.left.backHistory==back,"Display cap never truncates tabs or live back stack")
        let userRecord=UserDefaults.standard.object(forKey:DirectoryHistorySettings.key) as? NSDictionary
        c.saveDirectoryHistoryNow();c.clearDirectoryHistoryNow();c.runtimeConfig.historySaveOnExit=true;c.runtimeConfig.saveOnExit=false;c.saveSession()
        let afterRecord=UserDefaults.standard.object(forKey:DirectoryHistorySettings.key) as? NSDictionary
        check(userRecord==afterRecord,"Nonpersistent controller never writes user history even with save enabled")
        c.directoryHistoryDefaults=defaults
        c.runtimeConfig.historyLimit=2;c.runtimeConfig.historySaveOnExit=true;c.runtimeConfig.saveOnExit=false
        c.left.backHistory=[.local(root),.local(a),.local(b)];c.right.backHistory=[.local(cURL)]
        c.saveSession()
        check(DirectoryHistorySettings.restore(defaults:defaults,limit:200).left==[.local(a),.local(b)],"Actual saveSession saves history independently of disabled tab persistence")
        c.runtimeConfig.historySaveOnExit=false;c.left.backHistory=[.local(root)];c.saveSession()
        check(DirectoryHistorySettings.restore(defaults:defaults,limit:200).left==[.local(a),.local(b)],"Disabling save-on-exit preserves existing saved history")
        c.restoreDirectoryHistory()
        check(c.left.backHistory==[.local(a),.local(b)] && c.right.backHistory==[.local(cURL)],"Saved history restores even while automatic saving disabled")
        c.left.backHistory=[.local(root)];c.saveDirectoryHistoryNow()
        check(DirectoryHistorySettings.restore(defaults:defaults,limit:200).left==[.local(root)],"Save now works while automatic saving disabled")
        c.clearDirectoryHistoryNow()
        check(defaults.object(forKey:DirectoryHistorySettings.key)==nil && c.left.backHistory==[.local(root)],"Delete now erases saved history but preserves live navigation")
        c.saveSession(force:true)
        check(DirectoryHistorySettings.restore(defaults:defaults,limit:200).left==[.local(root)],"Explicit Save Settings persists history with automatic saving disabled")
        var config=c.runtimeConfig;config.historyMaximumShown=900;config.historyLimit=900
        check(config.normalized().historyMaximumShown==200 && config.normalized().historyLimit==200,"Configuration clamps independent history limits")
        let encoded=try JSONEncoder().encode(config.normalized()),decoded=try JSONDecoder().decode(CommanderConfiguration.self,from:encoded)
        check(decoded.historySaveOnExit==config.historySaveOnExit && decoded.historyShowIcons==config.historyShowIcons && decoded.historyMaximumShown==200,"History settings survive Codable persistence")
        print("PASS: \(checks) history settings assertions")
    }
}
