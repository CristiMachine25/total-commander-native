# Native button bar

The original Configuration → Button Bar entry (`cm_ButtonConfig`, 498) now opens a native editor. The former fixed fourteen-button strip is the default ordered model. Existing visibility preferences are retained.

The separate versioned `commander.buttonBar.v1` preference stores button labels, commands, literal executable arguments, start paths, icon paths, separators, icon size and label visibility. Invalid stored data falls back to defaults. Edits are staged; Apply validates/saves once and redraws; Cancel does not undo a previous Apply. An empty bar retains an editor button. Long bars scroll horizontally.

Supported internal commands reuse existing app actions; the chooser includes explicitly supported reference commands and the default/file-operation routes. External targets use native workspace opening or Process with an argument array. No shell/file macro expansion occurs. External programs run through the existing background operation UI and report nonzero exits.

Scope limits: Windows .bar import/export, sub-bars, a vertical second bar, DLL icon extraction, TC parameter macros, per-button shortcut assignments and drag-and-drop editing are not implemented. General configuration JSON export does not yet include the separate button-bar preference.
