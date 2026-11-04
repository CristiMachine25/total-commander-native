# Original settings audit: operations and integration

Reference: shipped English help from Total Commander 11.58.1, extracted under work/total-commander/help-extracted. Original TOTALCMD64.EXE SHA-256: 570f455917d991d32329005e259653fb4817716f137297ed82389ec920352f99. The CSV links each option to the exact help filename and a normalized option label (some combine the choices of one setting; these are semantic locators, not fabricated HTML anchors).

Scope: Operation, Edit/View and its Lister General/Multimedia/Player dialog, Quick Search, Ignore List, History, Copy/Delete, Misc./Confirmation, Refresh, FTP global configuration, Packer, ZIP, 7-Zip, Plugins, Language, Logfile, and Button Bar/Choose Command/Viewer Associations including documented command/parameter families. Buttons such as browsing an application path are grouped with their corresponding path setting except where a distinct behavior matters. Mutually exclusive choices are grouped where they comprise one setting; documented parameter families are listed separately. Cross-references to operation dialogs are not an inventory of all options in those operational dialogs or every undocumented INI key.

Evidence boundary: original help plus source inspection, not a paired Windows/native runtime pass. Existing fixture tests prove their bounded native behaviors, not full Windows parity. `implemented` means the documented setting has an active native equivalent; `partial` explicitly describes narrower semantics. Platform-specific is a missing original capability, not a pass. No complete settings parity is claimed.

Inventory: 347 option/behavior rows. Status counts: implemented=15, missing=254, partial=47, platform-specific=31. These are not independent features or a completeness percentage.

## Priorities and implementation this release

History is a cohesive native gap: separate visible-item limit, optional provider-type icons, and saved local history controls. New history persistence intentionally excludes remote/archive identities so FTP credentials cannot leak. Save/Delete now operate on saved history; turning off save-on-exit does not clear an existing record. Per-side current navigation remains intact when saved history is deleted. Native default persistence is disabled to preserve the existing behavior; this is not asserted as an original recovered default.

Remaining high-impact work includes recursive Ignore List operation semantics, independent save-state controls, retry/resume FTP policies, original packer and Lister options, operation logging, and Windows plugin equivalents. These require real runtime implementations and failure-path tests; adding checkboxes alone would not close the audit.

The original decompilation evidence remains partial (see decompilation.md and recovery-status.json). This audit reuses source-bound shipped help and does not claim that native code was recovered from the entire original settings implementation.
