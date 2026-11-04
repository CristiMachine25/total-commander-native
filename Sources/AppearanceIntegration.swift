import AppKit

extension Pane {
    var renderingPalette:CommanderDarkPalette {AppearanceSettings.palette(configuration,appearance:view.effectiveAppearance)}
    var darkChrome:Bool {AppearanceSettings.isDark(configuration.appearanceMode,appearance:view.effectiveAppearance)}
    var summaryTextColor:NSColor {darkChrome ? NSColor(srgbRed:0.65,green:0.81,blue:1,alpha:1):cyan}
    var driveHeadingTextColor:NSColor {darkChrome ? (active ? .white:.lightGray):(active ? .black:.darkGray)}
}
extension CommanderController {
    func applyCommanderAppearance() {
        // App-local only: allows independent settings/editor windows to inherit the choice.
        // Nonpersistent fixtures never change the test application's global appearance.
        if remember {NSApp.appearance=AppearanceSettings.appearance(runtimeConfig.appearanceMode)}
        window.appearance=AppearanceSettings.appearance(runtimeConfig.appearanceMode)
        let dark=AppearanceSettings.isDark(runtimeConfig.appearanceMode,appearance:window.effectiveAppearance)
        window.backgroundColor=dark ? NSColor(srgbRed:0.10,green:0.10,blue:0.12,alpha:1):navy
        window.contentView?.layer?.backgroundColor=window.backgroundColor.cgColor
        for pane in [left,right]{pane.refreshAppearanceRendering()}
        refreshChromeLabelColors()
        refreshPreferencesAppearance(runtimeConfig.appearanceMode)
    }
    func refreshChromeLabelColors() {
        let dark=AppearanceSettings.isDark(runtimeConfig.appearanceMode,appearance:window.effectiveAppearance)
        status.textColor=dark ? NSColor(srgbRed:0.65,green:0.81,blue:1,alpha:1):cyan
    }
    func toggleCommanderAppearance() {
        runtimeConfig.appearanceMode=AppearanceSettings.isDark(runtimeConfig.appearanceMode,appearance:window.effectiveAppearance) ? .light:.dark
        applyConfiguration(runtimeConfig);if remember {try? runtimeConfig.save()}
    }
}
