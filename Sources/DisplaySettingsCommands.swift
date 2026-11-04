import AppKit

extension CommanderController {
    func displaySettingsCommandID(_ command:String)->Int? {
        let value=command.lowercased()
        let fixed=["cm_srccustomviewmenu":270,"cm_srcviewmodelist":333,"cm_customcolumnconfig":483,"cm_customcolumndlg":2920,"cm_configviewmodes":2939,"cm_configviewmodeswitch":2940,"cm_toggleautoviewmodeswitch":2947]
        if let id=fixed[value] {return id}
        if value.hasPrefix("cm_srccustomview"),let index=Int(value.dropFirst("cm_srccustomview".count)),(1...29).contains(index) {return 270+index}
        if value.hasPrefix("cm_srcviewmode"),let index=Int(value.dropFirst("cm_srcviewmode".count)),(0...249).contains(index) {return 8500+index}
        return nil
    }
    func showCustomColumnMenu() {
        guard !busy,!activePane.isLoading else{return}
        let menu=customColumnsMenu()
        menu.addItem(.separator())
        let configure=NSMenuItem(title:"Configure custom columns…",action:#selector(referenceCommand(_:)),keyEquivalent:"");configure.tag=483;configure.target=self;menu.addItem(configure)
        menu.popUp(positioning:nil,at:NSPoint(x:16,y:activePane.view.bounds.height-50),in:activePane.view)
    }
    @discardableResult func routeDisplaySettingsCommand(_ id:Int)->Bool {
        switch id {
        case 270:showCustomColumnMenu()
        case 333:showViewModeMenu()
        case 483,2920:openPreferences(page:6)
        case 2939:openPreferences(page:7)
        case 2940:openPreferences(page:8)
        case 2947:
            runtimeConfig.autoSwitchEnabled.toggle();applyConfiguration(runtimeConfig)
            if remember {try? runtimeConfig.save()}
        case 271...299:
            let index=id-271;guard runtimeConfig.customColumnSets.indices.contains(index) else{return false}
            selectCustomColumns(runtimeConfig.customColumnSets[index].id)
        case 8500:return applyNamedViewMode(id:"default")
        case 8501...8749:
            let modes=runtimeConfig.viewModes.filter{$0.id != "default"},index=id-8501
            guard modes.indices.contains(index) else{return false};return applyNamedViewMode(id:modes[index].id)
        default:return false
        }
        return true
    }
}
