# Editable button bar

Follow the existing classic interface requested by the user. Replace the fixed strip with a persisted ordered model and a horizontal scroller. Configuration → Button Bar (original command 498) and right-click → Change open one staged editor per main window.

Implementation:
1. Add a versioned Codable button-bar model with defaults, validation, quoted executable arguments, icon size and text-label preferences. Keep this independent from the existing 52-setting configuration schema.
2. Add toolbar rendering/dispatch and a native editor with add/delete/reorder/separator, internal-command chooser, program/folder/icon browsers, label, parameters and working directory. Apply persists and immediately redraws. Cancel discards pending edits; Restore Defaults remains staged until Apply.
3. Enable the original menu command and command-line alias. Preserve existing default buttons and hidden-bar preference.
4. Test persistence, ordering, validation, parameter parsing, actual toolbar actions, editor Apply/Cancel and defaults using disposable preferences/files. Build optimized, test visible editor, restore user configuration, package and publish.

Scope: one horizontal native bar. Windows .bar import, nested bars, Windows executable/DLL icons and TC parameter macros are not included in this change; describe this explicitly. External launches use argument arrays, not shell interpolation.
