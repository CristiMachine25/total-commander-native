# Per-tab view settings

The original bundled `foldertabs.htm` documents preserved sort order, Brief/Full details and selections. `dlg_configfoldertabs.htm` separately documents “Save displayed file types separately for each tab”. The native implementation now retains these settings with each tab rather than a single left/right pane state.

Each tab retains its manual named mode, custom-column set, Full/Brief/Thumbnails/Tree layout, primary and secondary sort/direction, directory ordering, filename mask/program filter, substring filter, selected-only filter, cursor selection and marked filenames. Selection data is scoped to the exact location; it cannot select or hide names inherited from another directory. When automatic rules match, their effective view is applied after restoring that tab's manual view. The automatic view is never saved over the manual baseline. A separate pre-mode default snapshot ensures choosing Default after a tab change still restores the original layout/filter/sort and global palette, rather than the named mode itself.

The Folder Tabs page has a broad native “Remember view settings separately for each tab” switch and the original-style separate displayed-file-types switch. Disabling the broad switch retains pane-wide behavior. Disabling only file-type persistence retains the current pane's file mask and program-only filter while switching the other tab settings.

Foreground/background new tabs inherit the current manual view. Locked-tab navigation preserves the original state. Index maps shift during insertion, deletion and retaining tabs; whole-pane swaps move the maps with their tabs. Tab changes commit their index and view only after the new listing succeeds, leaving failed/stale loads unable to replace the active view. Archived new tabs use the same transaction path. Mode enter/leave commands execute once for the actual effective source and target modes, respecting the dash prefix on tab changes; the target tab's inactive saved manual mode does not spuriously run leave commands. Startup uses this same restoration transaction. Multi-row highlights and marks are restored after automatic mode application, with linear-time set membership.

Local sessions store a versioned, bounded JSON value with records paired by saved local-tab index and standardized path. Remote tabs and provider/client objects are excluded; inherited remote location identities and selections are scrubbed before a local background tab is encoded. Invalid records, malformed data, unsupported versions, path mismatches, missing mode/set IDs, invalid sorts and unsafe selection names are rejected or fall back to ordinary columns/name sorting. The existing Save on exit gate and explicit Save Settings force path govern persistence.

Manual header sorting and Show/filter commands record a manual baseline, including when entered while an automatic mode was active. Same-directory Refresh does not reapply automatic rules over these edits; rule evaluation remains tied to navigation/tab activation and explicit configuration application.

Limitations: the original `.tab` import/export format, custom tab labels, MRU traversal, multiline bars, drag reordering and provider session reconnection remain separate features. This adds per-tab view state, not all original folder-tab options.

Fixture evidence is recorded in `0.9-tab-view-settings-tests.log`. Tests run actual controllers against temporary directories without saving user preferences.

## Reverse tab shortcut regression

Visible testing found that AppKit consumed Control+Shift+Tab in Full view as backward focus traversal before `NSTableView.keyDown`. The Full table now forwards the two Control+Tab chords from its focused key-equivalent path, and the existing local key monitor claims them before native traversal only when the active file pane owns focus. Text fields, dialogs and unrelated modifiers retain native handling; configured custom shortcuts retain precedence. Focused responder evidence is in `0.9-pane-tab-shortcuts-tests.log`.
