# Native normal, dark and system appearance

Original reference: `dlg_configcolor.htm` in the shipped Total Commander help describes separate normal/dark colors and following the operating system app appearance. The native implementation exposes Normal, Dark and Follow macOS in Configuration → Color. Changes commit with the containing Apply/OK action.

The six dark file-pane colors are independent of the existing normal palette: foreground, background, marked text, selected-row background/text, and alternating-row background. Switching appearance never replaces stored normal colors. Named view modes can override dark background/text/alternating background/tab color separately from their normal overrides. Native controls and configuration windows inherit the chosen AppKit appearance.

Full, Brief, Thumbnails and directory trees resolve row colors against the active appearance. A native NSView `viewDidChangeEffectiveAppearance()` callback refreshes file-pane rendering when Follow macOS inherits a system change; it does not rescan folders or alter selection. App-local NSApplication appearance is changed only by persistent application controllers; tests use nonpersistent controllers and do not modify global preferences or OS appearance. [Apple API reference](https://developer.apple.com/documentation/appkit/nsview/viewdidchangeeffectiveappearance()).

The original Windows cursor-outline/theme styles, border palettes, colors by file type, and every auxiliary legacy dialog are not claimed complete. Normal/dark does not make the native UI pixel-identical to Windows.

## Validation

A frozen full-source build passed **23 appearance assertions** (exit 0): light/dark/system resolution, real table background and row selection colors, marked text, unchanged selection, Configuration window appearance, preserving normal colors through toggles, named mode normal/dark overrides including alternating rows, inherited appearance changes, normalized invalid colors, and unchanged UserDefaults. Evidence: [appearance test log](0.9-appearance-tests.log). These are controller/rendering assertions; the release's visible UI checks are recorded separately.

Visible-build follow-up: active and inactive disk-space headings now use white/light gray in dark mode; both pane summaries and main status use a lighter blue. Switching active panes reapplies these colors. Normal black/dark-gray/cyan colors remain unchanged. A fresh full-source test run passed **27 assertions**, including four new heading/summary contrast and restoration checks; [evidence](0.9-appearance-contrast-tests.log).
