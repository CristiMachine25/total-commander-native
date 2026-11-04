# Directory history configuration

Original reference: dlg_confighistory.htm from shipped Total Commander 11.58.1 help. Implemented native options: save history on exit, maximum items to show, icons, Save now, Delete saved history. The existing historyLimit supplies the independent saved-item cap (1–200); the visible cap does not alter the live back/forward stacks.

A versioned UserDefaults record stores independent left/right local path arrays, newest entries bounded by the saved cap. No FTP or archive identities/credentials are persisted. Invalid types, relative/URI/NUL paths, oversized records and oversized path strings are rejected. Loading is independent of the save-on-exit option; turning that option off does not erase saved history. Delete saved history removes only the saved record. Current live navigation remains available and will be saved again on exit if automatic saving remains enabled, matching the original warning.

History saving runs before the independent directory/tab save guard, so disabling directory restoration does not disable history saving. Explicit Save Settings and Save history now save even when automatic history saving is off. Nonpersistent controllers have no default history store, and tests inject an isolated UserDefaults suite.

Icons use native folder/archive/network symbols. This is not Windows filesystem-plugin icon support. History thinning, frequently used folders, custom fonts, initial scroll positioning, all-provider persistence and original INI history sections remain absent. Default automatic saving and icons stay disabled to preserve the previous native configuration; no original default is claimed from these choices.

27 focused assertions passed in 0.10-history-tests.log, including actual saveSession with tab saving disabled, explicit save while automatic save is disabled, restore while automatic save is disabled, saved-only deletion, provider exclusion, malformed data bounds, menu icons/show limits, tabs and back/forward navigation, and configuration roundtrip. Test compilation used -whole-module-optimization -Onone against an immutable source snapshot. Visible packaging checks belong to the release ledger.
