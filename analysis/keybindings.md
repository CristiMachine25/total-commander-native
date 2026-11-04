# Keybindings configuration

The dedicated Keybindings page edits the existing customShortcuts and commandAliases settings. It shows saved overrides, searches the supported native command set, records a key combination, and provides New, Assign, Remove and Reset overrides. New explicitly clears row selection so another binding does not accidentally replace the selected row. Assign updates the selected binding; duplicate chords assigned to another row are rejected.

Apply or page navigation collects valid pending field edits; malformed partial edits prevent the dialog from silently dropping them. Removing an override restores the existing built-in handler. Reset affects only the draft; Cancel leaves saved preferences unchanged. Aliases remain validated native-command names, with no shell execution or alias chains.

Capture intercepts key equivalents only while the recorder is first responder and consumes one chord, then returns focus to the shortcut field. Escape cancels. App-reserved shortcuts can be overridden in the file panes; operating-system-reserved combinations may never reach the application. Text fields and other dialogs retain normal editing behavior.

The page lists common built-in shortcuts as a reference, not a claim that every original Windows shortcut or contextual action is remappable. Supported overrides are the same allowlisted native commands used by buttons and aliases.

18 focused assertions cover staging, duplicate rejection, explicit replacement, New, invalid commands, event capture, Escape, active/inactive key-equivalent handling, command search, removal, reset, malformed initial data, and collecting pending edits. Final release evidence also records actual Preferences and visible app checks.
