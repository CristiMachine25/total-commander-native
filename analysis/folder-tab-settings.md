# Native folder-tab settings

Evidence: extracted original `dlg_configfoldertabs.htm` and `foldertabs.htm`.

- Close tab on double click: default off; the actual segmented control handles a second click only when enabled and routes the clicked pane/index to the controller.
- Confirm close all tabs: default on; closing other unlocked tabs asks before changing tab state. The current tab and locked tabs remain. This operation never deletes files.
- Show locked tabs with an asterisk: default on; the marker can be hidden without removing the lock.
- Normal locked local tabs: right-click a tab to Lock/Unlock. Navigation away from a locked local tab opens a new tab while retaining its root. Locked tabs cannot be closed until unlocked. Their roots survive local session save/restore, insert/remove operations and pane-tab swaps. New tabs are committed only after successful navigation; failed asynchronous listings do not add phantom tabs.

Locks are supported for local directories only. FTP/archive tabs cannot be locked. The original 'Locked but directory changes allowed' mode, named/custom tabs, multi-row layout, Ctrl+Tab most-recently-used/list policies and all original modifier/middle-click behaviors remain unsupported. Existing archive tabs and FTP connections retain their normal provider lifecycle.

Validation: [22 tab settings assertions](0.7-tab-settings-tests.log). Visible interaction and release-artifact checks are tracked separately in the release validation ledger.
