# Simplified Keybindings configuration — 0.10

The main page is a searchable Action / Shortcut list with readable action names. Select an action, then Record shortcut or Restore default. Default shortcuts appear immediately; custom shortcuts are marked with *. The Advanced section is collapsed by default and contains manual chord/command ID entry, aliases, individual custom-shortcut removal and Reset all.

The labels/default map is verified against the native Main.handleKey, performFunction and KeyboardFeatures.handleExtendedKey paths, not inferred from original command names. Defaults requiring numeric Plus/Minus explicitly say keypad. Context-only native keys such as Space and Ctrl+Tab participate in conflict checking but do not appear as remappable actions without an allowlisted command. This is not a complete original Windows shortcut inventory. Delete files follows the configured deletion policy. Numbered profile slots without custom bindings are hidden from the initial list but remain searchable.

Recording adds a shortcut and preserves other bindings for the action. Existing equivalent command aliases share one readable action row, while their stored command IDs roundtrip unchanged. Reusing a shortcut assigned to another action, including a known built-in or contextual action, requires the explicit Replace shortcut button. An unresolved conflict blocks Apply; selecting another action cancels the pending recording. Restore default removes that action's custom assignments and any overrides occupying its built-in keys. Advanced Remove shortcut removes only the typed chord; it does not discard other bindings.

All changes remain in the settings draft until Apply/OK. Cancel does not save. The aliases field uses the existing allowlisted parser; shell commands and alias chains remain unsupported. Existing file-pane focus, busy/loading and OS-reserved-key restrictions are unchanged.

Focused tests cover readable labels/defaults, searching, initial numbered-slot filtering, selected-action focus, multiple bindings, equivalent command IDs, individual removal, explicit custom/built-in/context conflicts, restoration, draft collection, aliases, capture cancellation, and active/inactive key equivalents. See 0.10-keybindings-tests.log for the current count. Final visible packaged-build checks are recorded in TEST-RESULTS.md.

## Historical editor

# Keybindings configuration

The dedicated Keybindings page edits the existing customShortcuts and commandAliases settings. It shows saved overrides, searches the supported native command set, records a key combination, and provides New, Assign, Remove and Reset overrides. New explicitly clears row selection so another binding does not accidentally replace the selected row. Assign updates the selected binding; duplicate chords assigned to another row are rejected.

Apply or page navigation collects valid pending field edits; malformed partial edits prevent the dialog from silently dropping them. Removing an override restores the existing built-in handler. Reset affects only the draft; Cancel leaves saved preferences unchanged. Aliases remain validated native-command names, with no shell execution or alias chains.

Capture intercepts key equivalents only while the recorder is first responder and consumes one chord, then returns focus to the shortcut field. Escape cancels. App-reserved shortcuts can be overridden in the file panes; operating-system-reserved combinations may never reach the application. Text fields and other dialogs retain normal editing behavior.

The page lists common built-in shortcuts as a reference, not a claim that every original Windows shortcut or contextual action is remappable. Supported overrides are the same allowlisted native commands used by buttons and aliases.

18 focused assertions cover staging, duplicate rejection, explicit replacement, New, invalid commands, event capture, Escape, active/inactive key-equivalent handling, command search, removal, reset, malformed initial data, and collecting pending edits. Final release evidence also records actual Preferences and visible app checks.
