# Display settings editors

Source reference: original shipped help pages `dlg_configcustomcolumns.htm`, `dialog_usercolumns.htm`, `dlg_configviewmode.htm`, and `dlg_configautoviewmode.htm` in the extracted Total Commander help. Native controls follow the supported model semantics; they are not pixel-identical Windows dialogs.

## Working controls

- Custom Columns: saved set name, New/Edit/Copy/Delete/Up/Down, active default set, ordered column definitions, caption, expression, built-in field insertion, width in points, left/right alignment, adjustable name width and horizontal scrolling.
- View Modes: saved mode name and ordering, default-mode selection, Full/Brief/Thumbnails/unchanged, custom-column set, primary and secondary sort order, direction, directories first, optional filter and panel colors, alternate background, tab color, SF Symbol icon, and validated native automatic enter/leave commands.
- Auto Switch Mode: enable and restore-default flags, ordered rule list, target mode, enabled state, common AND/OR plus per-condition conjunction, NOT, directory/path/subdirectory constraints, local/archive/FTP kinds, matching-file masks, all/none/half/any/percentage policies.

All controls are draft-only until the containing Configuration window applies. Switching a list selection collects the current form; malformed values leave the selection in place with an inline error. Deleting an invalid unreferenced draft remains possible. Referenced column sets and modes cannot be removed until their consumers are updated. Changing a mode to/from the reserved default identity requires updating existing rule references; strict Apply validation prevents dangling identities.

The three related pages rebuild their controls from collected drafts when revisited so choices reflect newly created/deleted column sets and modes. Other configuration pages retain their existing cache. Outer Cancel/close discards pending drafts. The editors do not write preferences directly.

## Validation

- Existing ConfigurationUITests: **38 assertions passed**, including navigation geometry for all categories, existing page caching, Apply/Cancel, defaults, and stale dialog rejection.
- DisplaySettingsUITests: **17 assertions passed** against actual NSButton/NSPopUpButton/NSTextField controls and PreferencesController. Creates/reorders columns, chooses a default set, creates a mode and rule across pages, applies all three, checks references, rejects deletion of referenced objects, duplicates/removes a draft, and rejects an unsupported plugin expression while preserving applied runtime configuration.
- Both suites use nonpersistent controller fixtures. UserDefaults bytes were checked unchanged.

## Platform boundaries

Native width units are macOS points. Windows plugin fields, plugin-specific column sets, Windows icon files and drive types are not exposed as working settings. Rules only inspect the current successful directory listing. Full original command/plugin behavior remains outside this UI test evidence; runtime matching and pane rendering have their own suites.
