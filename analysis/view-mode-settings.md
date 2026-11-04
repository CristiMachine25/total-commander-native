# Named view modes and automatic switching

## Source and behavior

The original bundled Total Commander help was inspected directly: `dlg_configviewmode.htm` and `dlg_configautomodeswitch.htm` from the extracted official `TOTALCMD.CHM`. It specifies named/reordered modes, unchanged/full/brief/custom columns, sort and additional sorts, background colors, tab decoration, enter/leave commands, and ordered automatic rules with AND precedence over OR. This implementation follows those meanings where the native pane has an equivalent.

Configuration stores named modes and ordered rules in the version 3 native settings file. `<Default>` has the reserved ID `default`; absent an explicit default mode, no-match restoration returns to the captured manual pane settings. Disabled rules do not participate. The first matching enabled rule wins. Rules are evaluated from the committed directory listing, never by recursive filesystem scans or new network requests. Failed/stale navigation does not change modes. Tab selection, both pane-swap paths, startup restoration, and configuration Apply reevaluate the applicable mode. Automatic refresh alone does not change modes; this follows the documented directory-change trigger.

Modes support unchanged/full/brief/thumbnails, custom-column sets, primary direction and up to eight additional sorts, directory ordering, filename mask, foreground/background and alternate-row colors, tab color swatch and SF Symbol, and a bounded native automatic-command allowlist. Selecting a mode changes only its pane. A thumbnails mode on a remote provider falls back to Full. Tree is deliberately not offered as an automatic mode: the native tree is a navigation surface rather than the source file listing.

Rules support local folder/archive/FTP predicates; directory paths with `*` and `?`, optional subdirectories; all, none, half, at least one, or percentage file-name matches; a separate path restriction for file-type rules; negation; and mixed AND/OR sub-rules with AND taking precedence. Masks accept spaces/semicolons and exclusions after `|`; only file names participate, not subdirectories. Empty folders do not count as all/half/percentage matches. Pattern matching is case-insensitive, consistent with the original Windows rule behavior. Native paths use `/`; Windows paths are not translated.

Auto-run commands support comma-separated enter commands, leave commands following `|`, `*` to repeat on each actual directory change, and `-` to suppress command execution on tab switches. Only supported, non-destructive view/sort/filter commands and 50%/100% pane sizing are allowed. Shell commands, user-command expansion, file operations, navigation, plugin commands and modal commands are rejected. Modes still switch on a tab change when `-` suppresses their commands.

Manual named-mode and custom-column choices persist per pane when Save on exit is enabled. Explicit Save Settings stores these choices even when exit-saving is disabled. Automatic rules do not overwrite the manual choice. Default restoration preserves a selected-only filter only in the folder where it was captured, avoiding stale file URLs hiding unrelated folders.

## Explicit remaining differences

- Windows drive-letter/device/UNC/virtual/plugin/search-result predicates have no equivalent implemented native provider. They are not presented as working rules.
- The native segmented tab control renders a color swatch and symbol, not an original full-tab color and Windows icon-resource path. There are no competing custom-icon providers, so no inert priority option is exposed.
- Separate normal/dark palettes and arbitrary `cm_`/`em_` commands are not implemented.
- Per-tab view overrides and original `wincmd.ini` view-mode/rule import/export are not implemented; the native JSON representation is validated and round-trippable.
- A custom sort with an explicit column-set ID must belong to that set. With columns unchanged, a missing current custom column falls back to the native name comparator; this is a bounded native behavior, not a full original plugin sorting implementation.

## Verification

Actual controller tests cover pattern/exclusion matching, boundary paths, all/none/half/percentage rules, mixed logical precedence, disabled-rule ordering, unsafe command rejection, primary and secondary sorting, matching folder transitions, independent panes, no-match restoration, manual/default command routing, automatic commands, startup layout restoration, pane swaps, tab-decoration width stability, cross-set sort rejection, custom-column choice after Apply, Full mode clearing custom columns, selected-only restoration, and Codable round trips. See `0.8-view-settings-tests.log` for the final run result. All fixtures are temporary and removed on completion; no saved user preferences are modified by these tests.
