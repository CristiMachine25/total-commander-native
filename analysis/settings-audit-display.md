# Original display-settings audit

Source: shipped Total Commander 11.58.1 help, read locally from `work/total-commander/help-extracted`. This is an option-level help-to-source audit, not a paired runtime comparison or complete decompilation. The original pages have no per-option HTML anchors; CSV source_locator names the matching help field or subchoice in normalized readable form; it is a text locator, not an HTML anchor.

Scope: Layout, Display, Icons, Font, Color including Others and linked file-type-colors dialog, Tabstops/Data Formats, Folder Tabs, Thumbnails, Custom Columns including linked detail dialog, View Modes, Auto Switch. Includes their described choices and actions. Excludes unlisted INI-only keys, dynamically installed plugin options, and all other configuration categories handled by the other audit lane. `implemented` means a corresponding native setting and runtime path exist; it is not proof of original visual/default/edge-case identity. `partial` identifies behavior/units/platform differences. Platform-specific entries still count as original features that are not reproduced.

The CSV enumerates 254 rows: implemented: 93, missing: 94, partial: 46, platform-specific: 21. Counts are inventory rows, not an overall parity percentage; some rows are choices within one setting.

## Added in this implementation

Directory bracket and trailing slash settings, directory counts in the footer, independent ascending name order for directories, measured Brief columns with optional width cap, and four sorting-method choices. All relevant main-pane renderers and primary/secondary sorting paths are wired. Slash is a macOS adaptation of the original backslash suffix, explicitly not identical punctuation. Sorting uses macOS locale APIs; exact Windows locale behavior is unverified. Character-code natural sorting handles ASCII decimal runs without integer overflow. Existing case-sensitive sorting remains a native override. Directory ascending-name policy applies when directories are grouped first; the native mixed-files-and-directories option uses one consistent file comparator to avoid non-transitive sorting. Custom-column expression string comparators retain their existing natural/case-sensitive policy; the new four-way selector governs file-name/extension comparisons. Brief width has a native minimum of 80 points, unlike the original font-based minimum.

Defaults preserve prior native preferences: brackets on, trailing slash off, directory count off, directory fixed name order off, no Brief width cap, natural alphabetical sort. The INI reference proves DirBrackets=1 and SortDirsByName=1; the latter differs from the preserved native default false. Brief width is documented in Windows pixels, while the native control uses points. Other original defaults remain unverified. Width uses native points; original Windows DPI semantics are not reproduced.

## Key unresolved groups

Breadcrumbs and drive/button bars; complete-tree load and tree selection policies; Windows overlays/libraries; dialog/main-window fonts and DPI profiles; file-type and specialized-window colors; custom numeric separators; multiline/equal-width/MRU tabs; persistent thumbnail database/providers/captions; original plugin columns and all field formatters; plugin/virtual/search rule predicates; unrestricted auto-run commands. See every individual row for boundaries rather than treating a category heading as completion.

## Evidence boundary

Saved REA native pseudocode evidence is partial (see `decompilation.md`). No new original runtime was executed for this audit. UI settings existence and native test passes do not establish Windows performance, pixel equivalence, or total configuration parity.

## Native regression evidence

`analysis/0.10-display-parity-tests.log`: 26 assertions passed, exit 0, against a frozen full-source snapshot with the final directory-grouping comparator guard. Checks cover four comparison modes and numeric-run overflow, decoration combinations, actual Full-view labels, selected/total footer directory counts, immediate re-sort, secondary-sort directory policy, mixed file/directory comparator consistency, measured Brief caps, and configuration roundtrip. This does not replace the root's visible packaged-app checks or establish original runtime equivalence.
