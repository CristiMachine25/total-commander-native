import AppKit
@main struct AppearanceSettingsTests {
    static func main()throws {
        let app=NSApplication.shared;app.setActivationPolicy(.prohibited)
        let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("appearance-fixture-"+UUID().uuidString)
        try fm.createDirectory(at:root,withIntermediateDirectories:false);defer{try? fm.removeItem(at:root)}
        try Data("sample".utf8).write(to:root.appendingPathComponent("sample.txt"))
        let before=UserDefaults.standard.data(forKey:CommanderConfiguration.defaultsKey),c=CommanderController(initial:root,remember:false)
        var count=0
        func check(_ value:Bool,_ message:String){count += 1;precondition(value,message)}
        let light=NSAppearance(named:.aqua)!,dark=NSAppearance(named:.darkAqua)!
        check(!AppearanceSettings.isDark(.light,appearance:dark),"Explicit light ignores system dark")
        check(AppearanceSettings.isDark(.dark,appearance:light),"Explicit dark ignores system light")
        check(AppearanceSettings.isDark(.system,appearance:dark) && !AppearanceSettings.isDark(.system,appearance:light),"System resolution uses inherited appearance")
        check(AppearanceSettings.appearance(.system)==nil,"System leaves appearance inherited")
        var config=CommanderConfiguration();config.foreground = .init(red:0.1,green:0.2,blue:0.3);config.background = .init(red:0.9,green:0.8,blue:0.7)
        config.darkPalette.background = .init(red:0.02,green:0.03,blue:0.04);config.darkPalette.foreground = .init(red:0.8,green:0.9,blue:1)
        c.applyConfiguration(config)
        check(c.left.renderingPalette.background==config.background,"Normal palette selected")
        c.left.table.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false)
        c.toggleCommanderAppearance()
        check(c.runtimeConfig.appearanceMode == .dark && c.window.appearance?.name == .darkAqua,"Toggle applies dark window appearance")
        check(c.runtimeConfig.background==config.background && c.runtimeConfig.foreground==config.foreground,"Dark switching preserves normal palette")
        check(c.left.renderingPalette.background==config.darkPalette.background,"Full pane chooses dark background")
        check(c.left.table.backgroundColor==config.darkPalette.background.nsColor,"Actual table background updated")
        check(c.left.itemColor(marked:true,selected:false)==config.darkPalette.markedForeground.nsColor,"Marked text uses dark palette")
        check(c.left.itemColor(marked:false,selected:true)==config.darkPalette.selectionForeground.nsColor,"Selected text uses dark palette")
        let row=c.left.tableView(c.left.table,rowViewForRow:1) as! PaneSelectionRow
        check(row.selectionColor==config.darkPalette.selectionBackground.nsColor,"Actual row selection uses dark palette")
        check(c.left.table.selectedRow==1,"Appearance switching preserves selection")
        c.left.active=true;c.right.active=false
        check(c.left.heading.textColor == .white && c.right.heading.textColor == .lightGray,"Both active and inactive disk headings have dark contrast")
        check(c.left.footer.textColor==c.left.summaryTextColor && c.right.footer.textColor==c.right.summaryTextColor && c.status.textColor==c.left.summaryTextColor,"Both summaries and main status use readable dark text")
        c.right.active=true;c.left.active=false
        check(c.right.heading.textColor == .white && c.left.heading.textColor == .lightGray,"Switching panes preserves readable heading colors")
        let preferences=PreferencesController(c)
        check(preferences.window?.appearance?.name == .darkAqua,"Configuration window opens in dark appearance")
        preferences.close()
        c.toggleCommanderAppearance()
        check(c.left.renderingPalette.background==config.background && c.window.appearance?.name == .aqua,"Toggle restores normal colors exactly")
        check(c.left.heading.textColor == .darkGray && c.right.heading.textColor == .black && c.left.footer.textColor==cyan && c.status.textColor==cyan,"Normal heading and summary colors preserved")
        var mode=CommanderViewMode();mode.id="test";mode.name="Test";mode.background = .init(red:0.7,green:0.6,blue:0.5);mode.darkBackground = .init(red:0.04,green:0.05,blue:0.06);mode.darkForeground = .init(red:0.9,green:0.8,blue:0.7);mode.darkAlternatingBackground = .init(red:0.07,green:0.08,blue:0.09)
        config.viewModes=[mode];c.applyConfiguration(config);check(c.applyNamedViewMode(id:"test"),"Named mode applies")
        check(c.left.renderingPalette.background==mode.background,"Named mode normal override applies")
        c.toggleCommanderAppearance()
        check(c.left.renderingPalette.background==mode.darkBackground && c.left.renderingPalette.foreground==mode.darkForeground,"Named mode uses independent dark overrides")
        check(c.left.itemBackground(row:1)==mode.darkAlternatingBackground?.nsColor,"Named alternate dark row background applies")
        config.appearanceMode = .system;c.applyConfiguration(config);c.window.appearance=dark;c.left.view.viewDidChangeEffectiveAppearance()
        check(c.left.renderingPalette.background==mode.darkBackground,"Inherited dark appearance renders dark mode palette")
        c.window.appearance=light;c.left.view.viewDidChangeEffectiveAppearance()
        check(c.left.renderingPalette.background==mode.background,"Inherited light appearance restores normal mode palette")
        var broken=CommanderDarkPalette();broken.foreground.red=Double.nan;broken.background.blue=4
        check(broken.normalized.foreground.red==0 && broken.normalized.background.blue==1,"Palette normalization rejects nonfinite and clamps range")
        check(UserDefaults.standard.data(forKey:CommanderConfiguration.defaultsKey)==before,"Fixture never writes user preferences")
        c.window.close();print("PASS: \(count) appearance assertions")
    }
}
