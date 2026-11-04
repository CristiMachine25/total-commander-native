# Original INI display-profile import

This is a data-only, reported subset of `wincmd.ini`, not full Windows configuration compatibility. No redirects, executable commands, DLL icons or content plugins are opened. Imported configuration is staged for review; import itself does not save preferences.

## Evidence

The original extracted English help `inisettings3.htm` documents `[CustomFields]`, `[ViewModes]` and `[ViewModeSwitch]`. `dialog_usercolumns.htm`, `dlg_configviewmode.htm` and `dlg_configautomodeswitch.htm` establish the corresponding option meanings and rule precedence. The actual switch section is **ViewModeSwitch**, not AutoSwitchMode.

Original user-posted INI specimens establish serialized details not enumerated by help: [custom-column sample](https://ghisler.ch/board/viewtopic.php?p=335840), [custom sort sample](https://www.ghisler.ch/board/viewtopic.php?t=49505), [color options sample](https://www.ghisler.ch/board/viewtopic.php?t=45051), and [archive rule sample confirmed by the author](https://www.ghisler.ch/board/viewtopic.php?p=313528). The local original INI contains no saved display profiles, so no claim of paired original-app round-trip verification is made.

## Supported representation

- Custom titles separated by `|`; headers and expressions separated by literal `\n`; comma-separated widths with first two entries reserved for original Name/Ext; negative custom widths mean right alignment. `OptionsN` supplies reference width, horizontal-scroll flag and optional DPI. Native widths are points with a minimum of 32; the report explicitly notes that original font metrics, Name/Ext widths and DPI geometry are not reproduced.
- Stable set/column identifiers preserve links across repeat imports. Existing unrelated native sets remain intact. Reimport replaces only the reserved imported namespace for each present section, so removed source profiles disappear. Absent sections remain unchanged. Empty present sections can clear imported profiles. The shared `default` mode is retained unless explicitly replaced, because it may be native-owned. A native reference to a removed imported profile rejects the transaction. The original Autoload setting is reported separately instead of silently changing the active pane.
- Mode options accept seven-field and nine-field layouts. Proven codes map unchanged (`-1`), Full (`1`), and custom sets (`6` onward); other view codes are reported rather than guessed. Standard/custom sort indices, reversal and signed one-based additional sorts map to native keys. Windows COLORREF values convert to native RGB, including the two optional dark background colors. `-1` retains inheritance.
- Original DLL icon specifications remain unsupported and are reported. Automatic commands must pass the native allowlist; user-defined `em_` commands are rejected.
- Ordered switch rules preserve `|&` and `||`. Archive, FTP, generic/local-directory rules (`A`, `F`, `D`, `L`) map to their native provider equivalents; the import report explicitly notes that Windows drive-letter/UNC classification is not reproduced. `+` rules are accepted only after paths are expressed as native absolute or `~/` paths. Windows drive/UNC paths, drive-type flags, environment variables, file-type encodings and plugin/search/virtual-folder conditions require manual translation and are reported.

All present linked display sections are validated as one transaction. Duplicate keys, malformed syntax, unsupported field expressions, incomplete sets, invalid geometry, unsupported automatic commands or broken references leave the previous native display profiles unchanged. Unrelated supported scalar INI settings may still be staged; the report distinguishes them. Unknown keys and ignored DLL icons are visible in the unsupported report. No original INI export is advertised.

## Tests

[Fixture evidence](0.9-original-display-ini-tests.log) covers original delimiters/indices, signed widths, BGR colors, dark colors, custom sorting references, AND/OR rules, runtime rule matching, idempotent reimport, preservation of unrelated native sets and active selection, unsupported plugin/Windows values, duplicate keys, incomplete profiles, invalid values and syntax, redirects, independent scalar import when a linked profile group rolls back, namespace shrink/empty-section removal, removed-rule behavior, native cross-reference rollback, and redirect protection.
