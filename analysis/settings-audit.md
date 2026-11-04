# Original settings audit — 0.10.0

The original target is Total Commander 11.58.1, TOTALCMD64.EXE SHA-256 `570f455917d991d32329005e259653fb4817716f137297ed82389ec920352f99`.

Two independent option-level audits cover all original help files matching dlg_config*.htm, plus Display, Logfile, Lister, ZIP and 7-Zip, and linked dialogs identified by the workers. The combined index contains **601 rows across 32 source pages**. Rows can be options, choices or documented actions; these are not unique-setting counts or a parity percentage.

- [Display audit](settings-audit-display.csv): layout, display, colors, fonts, tabstops, tabs, thumbnails, columns and view modes.
- [Operations audit](settings-audit-operations.csv): operation, copy/delete, history, refresh, FTP, packers, viewers, plugins, language, logging and button bar.
- [INI inventory](original-ini-inventory.csv): 847 declaration occurrences extracted from five shipped help pages, explicitly unverified. Templates/examples can overlap. This expands discovery beyond the configuration dialog; it does not classify every hidden INI behavior as implemented.
- [Source hashes and counts](settings-audit-summary.json) make the help-to-source audit reproducible.

`implemented` means a native field/control/runtime equivalent exists. It does not certify original defaults, visuals, all edge cases or observed Windows execution. `partial`, `missing` and `platform-specific` identify remaining differences, not optional exclusions from the user's parity requirement.

## Reverse-engineering evidence

A fresh REA PE resource inspection examined 1,066 resource-directory entries and identified 528 resources: Evidence `ev_565731903aca5f839c0fbd4f1324f3591aade55a3a95a03538bc903c82a21716`, retained in [resource metadata](original-settings-resource-evidence.json). Named dialog/raw-data resources include the History form, but the resource tree alone does not expose or prove all runtime-created settings controls. No original code was executed by this inspection.

Earlier Hopper/REA recovery emitted 5,565 pseudocode files from 24,601 provider procedure entries; [recovery status](recovery-status.json) remains incomplete. This pass reused that evidence and the shipped help; it did not complete binary decompilation or run a paired Windows/macOS settings comparison.

## Implemented in this release

Simplified action-first Keybindings with readable defaults, recording, explicit conflict replacement and collapsed Advanced controls. Nine new typed settings cover directory brackets/trailing separator, directory counts, grouped-directory name order, four-way filename sorting, Brief width cap, history saving, displayed history limit and icons. History Save/Delete now act on saved local history independently of current navigation. Version 5 native configuration imports older versions; documented supported INI mappings are explicit, with slash adaptation reported.

Remaining gaps are substantial: see the CSVs and [remaining requirements](remaining-parity-gaps.md). No finished exact Total Commander parity claim is made.
