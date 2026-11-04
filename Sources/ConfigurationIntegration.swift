import AppKit

extension CommanderController {
    func applyConfiguration(_ configuration:CommanderConfiguration) {
        let oldHidden=showHidden
        runtimeConfig=configuration;showHidden=configuration.showHidden
        barScroll?.isHidden = !configuration.showButtonBar
        buttonBar?.isHidden = !configuration.showButtonBar
        status.isHidden = !configuration.showStatusBar
        commandField?.isHidden = !configuration.showCommandLine
        functionBar?.isHidden = !configuration.showFunctionButtons
        let vertical = !configuration.verticalArrangement
        if splitView.isVertical != vertical {
            splitView.isVertical=vertical
            window.contentView?.layoutSubtreeIfNeeded()
            splitView.setPosition((vertical ? splitView.bounds.width : splitView.bounds.height)/2,ofDividerAt:0)
        }
        ListerController.appearanceProvider={ListerAppearance(fontName:configuration.viewerFontName,fontSize:configuration.viewerFontSize,wordWrap:configuration.viewerWordWrap,sizeText:{configuration.sizeString($0)})}
        for pane in [left,right] {
            pane.backHistory=Array(pane.backHistory.suffix(configuration.historyLimit));pane.forwardHistory=Array(pane.forwardHistory.suffix(configuration.historyLimit))
            pane.applyConfiguration(configuration)
        }
        reconfigureQuickView();separateTrees.refreshRoots()
        if oldHidden != showHidden {refresh()}
        refreshController.configure()
    }
    func configuredExternalApplication(editable:Bool)->URL? {
        let enabled=editable ? runtimeConfig.externalEditorEnabled : runtimeConfig.externalViewerEnabled
        let path=editable ? runtimeConfig.externalEditorPath : runtimeConfig.externalViewerPath
        return enabled && !path.isEmpty ? URL(fileURLWithPath:path) : nil
    }
    @objc func verticalArrangement() {
        runtimeConfig.verticalArrangement.toggle();applyConfiguration(runtimeConfig);if remember {try? runtimeConfig.save()}
    }
    @objc func saveWindowPosition() {
        guard remember else {return}
        UserDefaults.standard.set(NSStringFromRect(window.frame),forKey:"savedWindowFrame")
        UserDefaults.standard.set(splitView.isVertical ? splitView.subviews[0].frame.width/splitView.bounds.width : splitView.subviews[0].frame.height/splitView.bounds.height,forKey:"savedDividerRatio")
        status.stringValue="Window position saved"
    }
    func restoreWindowPosition() {
        guard let value=UserDefaults.standard.string(forKey:"savedWindowFrame") else{return}
        let rectangle=NSRectFromString(value)
        guard rectangle.width>=window.minSize.width,rectangle.height>=window.minSize.height,
              NSScreen.screens.contains(where:{$0.visibleFrame.intersects(rectangle)}) else{return}
        window.setFrame(rectangle,display:false)
    }
    @objc func saveConfiguration() {
        guard remember else {return}
        do {try runtimeConfig.save();saveSession();status.stringValue="Settings saved"}catch{showError(error)}
    }
}
