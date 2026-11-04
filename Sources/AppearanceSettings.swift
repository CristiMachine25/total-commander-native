import AppKit

enum CommanderAppearanceMode:String,Codable,CaseIterable {case light,dark,system}
struct CommanderDarkPalette:Codable,Equatable {
    var foreground=ConfigurationColor(red:0.90,green:0.90,blue:0.92)
    var background=ConfigurationColor(red:0.12,green:0.12,blue:0.14)
    var markedForeground=ConfigurationColor(red:1,green:0.45,blue:0.40)
    var selectionBackground=ConfigurationColor(red:0.12,green:0.34,blue:0.62)
    var selectionForeground=ConfigurationColor.white
    var alternatingBackground=ConfigurationColor(red:0.16,green:0.16,blue:0.18)
    var normalized:CommanderDarkPalette {
        var p=self;p.foreground=p.foreground.normalized;p.background=p.background.normalized;p.markedForeground=p.markedForeground.normalized;p.selectionBackground=p.selectionBackground.normalized;p.selectionForeground=p.selectionForeground.normalized;p.alternatingBackground=p.alternatingBackground.normalized;return p
    }
}
enum AppearanceSettings {
    static func isDark(_ mode:CommanderAppearanceMode,appearance:NSAppearance)->Bool {
        switch mode {case .light:return false;case .dark:return true;case .system:return appearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua}
    }
    static func appearance(_ mode:CommanderAppearanceMode)->NSAppearance? {
        switch mode {case .light:return NSAppearance(named:.aqua);case .dark:return NSAppearance(named:.darkAqua);case .system:return nil}
    }
    static func palette(_ configuration:CommanderConfiguration,appearance:NSAppearance)->CommanderDarkPalette {
        if isDark(configuration.appearanceMode,appearance:appearance){return configuration.darkPalette.normalized}
        return CommanderDarkPalette(foreground:configuration.foreground,background:configuration.background,markedForeground:configuration.markedForeground,selectionBackground:configuration.selectionBackground,selectionForeground:configuration.selectionForeground,alternatingBackground:configuration.alternatingBackground)
    }
}
/// AppKit calls this for inherited system changes as well as explicit window overrides.
final class CommanderAppearanceView:NSView {
    var appearanceDidChange:(()->Void)?
    override func viewDidChangeEffectiveAppearance(){super.viewDidChangeEffectiveAppearance();appearanceDidChange?()}
}
