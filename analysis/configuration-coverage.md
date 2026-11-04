# Native configuration coverage

This is a native macOS settings implementation informed by the shipped Total Commander help. It is not a recovered original configuration dialog and does not implement every original option. Version 0.5 adds complete native JSON configuration exchange and a documented partial `wincmd.ini` importer; it does not implement full original INI roundtrip or redirection semantics.

## Evidence and defaults

Source evidence is the locally extracted original help under `work/total-commander/help-extracted/`:

| Page | Original evidence | Native functional controls |
|---|---|---|
| Layout | `dlg_config.htm` | Main button bar, drive combobox, folder tabs, current path, tabstop headers, status bars, command line, function buttons; vertical pane arrangement from the original Show menu |
| Display | `dlg_display.htm` | Hidden files; explicit directory-first and case-sensitive sorting controls. The latter two are native sorting controls, not a claim that the original four sort-method choices were reproduced. |
| Icons | `dlg_configicons.htm` | Associated macOS icons, standard icons, no icons; icon size |
| Font | `dlg_configfont.htm` | File font name, size and bold; explicit native row height |
| Color | `dlg_configcolor.htm` | File foreground/background, marked text, selected background/foreground |
| Tabstops/Data Formats | `dlg_configtabs.htm` | Name/extension/size/date/attributes widths and visibility, extension alignment, all ten documented size styles, independent header/footer style (or inherit file list), locale separators, date ordering, century and seconds |
| Folder Tabs | `dlg_configfoldertabs.htm` | Show single tab header, tab-title length, insertion beside current tab |
| Thumbnails | `dlg_configthumbs.htm` | Thumbnail pixel size (64–256) |
| Operation | `dlg_config2.htm` | Save location/tabs on exit, single-click opening, including directories in Select All |
| Edit/View | `dlg_configedit.htm`, `lister_menuoptions.htm` | F3 viewer application, F4 editor application, internal viewer font/size and viewport word wrapping. Remote/archive F4 retains the controlled save-back editor rather than silently launching an untracked external editor. |
| Quick Search | `dlg_configquicksearch.htm` | Disabled, letters, Alt+letters and Ctrl+Alt+letters invocation; beginning/exact-before-dot matching. The dialog variant is not exposed. |
| Ignore List | `dlg_configignorelist.htm` | Explicitly labeled **display filtering only** with semicolon-separated name patterns. The original recursive transfer/sync exclusions are NOT implemented by this control. |
| History | `dlg_confighistory.htm` | Maximum retained directory-history entries (1–200) |

Original help explicitly states bytes as the default size style, describes 1 kbyte as 1024 bytes unless `SizeStyle1000` overrides it, and states that the tab header is normally hidden for a single tab. Those defaults are source-supported. Other numeric defaults preserve the pre-existing native build's visual baseline or are explicit native choices: Tahoma 13 (system fallback when unavailable), row height21, 16-pixel icons, 128-pixel thumbnails, 32-character tab titles and 100 history items. Quick search defaults to disabled to preserve the prior native command-line typing behavior; the help enumerates invocation modes but does not establish this as the original default. Native classic selection colors are chosen for readability; they are not asserted to be recovered original INI defaults. Viewer Menlo12 and viewport wrapping off preserve the native viewer baseline.

## Size choices

The original Tabstops help lists:

1. bytes
2. kbytes
3. dynamic integer k/M/G
4. dynamic one-decimal k/M/G
5. dynamic integer k/M
6. dynamic one-decimal k/M
7. dynamic integer k/M/G/T
8. dynamic one-decimal k/M/G/T
9. dynamic two-decimal k/M/G
10. dynamic two-decimal k/M/G/T

All are implemented. Fixed MB and fixed GB are clearly labeled **native additions**, because they are not listed in the original help. `useDecimalUnits` exposes the documented `SizeStyle1000` behavior. File sizes remain exact `Int64` bytes internally; formatting changes presentation only. Directory cells continue to render directory markers instead of a fictional byte size. System locale controls grouping and decimal symbols. Negative/unknown sizes format as zero only when a caller passes a negative numeric value; provider-specific unknown-size presentation remains the caller's responsibility.

## Persistence and application

`CommanderConfiguration` is a typed Codable schema stored as JSON data in UserDefaults key `commander.configuration.v1`. It imports the previous native `fileFontSize`, `fileRowHeight`, `showHidden`, and `externalEditor` keys when no valid typed record exists. Unknown/malformed individual fields fall back independently. Numeric limits, column identifiers, mandatory Name column and finite RGB values are normalized.

Saving mirrors legacy keys during migration, but typed settings are authoritative. Turning off an external editor clears the legacy active application path while retaining the configured path in the typed schema. The UI requires existing `.app` applications for enabled external tools. It never sends configured paths to a shell.

Preferences starts from the live controller configuration and keeps that baseline to detect intervening edits. Both the regular dialog and configuration-file editor refuse Apply if settings have changed elsewhere while they were open, preventing silent overwrite. Preferences lazily retains visited category controls; Restore Defaults invalidates those cached pages. Visual-only Apply does not unconditionally rescan directories.

Preferences starts from the live controller configuration. Apply/OK validate every edited page, save only in a persistent user session, and call `CommanderController.applyConfiguration`. Cancel discards un-applied edits. Defaults resets the draft, requiring Apply/OK to persist. Non-persistent smoke sessions apply runtime changes without touching user settings.

The parent controller owns layout, external-tool dispatch, session/history behavior and calls `Pane.applyConfiguration`; pane implementations own fonts/colors, columns, row/icon geometry, tabs, sorting, date/size display and thumbnail sizing. Viewer fonts/wrapping are applied on opening new viewers. Existing open viewer settings are not promised to live-update.

## Configuration files

**Configuration → Change Settings Files Directly…** (original command 581, `cm_ConfigChangeIniFiles`) opens a staged native JSON editor. This preserves the original menu entry but uses native JSON rather than invoking Notepad on original INI files. Apply strictly validates and saves preferences; Close leaves unapplied text unused. Export atomically writes the validated native settings, while Import stages a native JSON file or merges the supported Windows INI subset for review before Apply. Source files are not rewritten by import.

Native JSON uses a versioned envelope and all 52 typed settings. Missing, unknown, malformed, duplicate, wrong-type and out-of-range settings are rejected instead of using the tolerant persistence decoder's fallback behavior. INI import reports imported/unsupported/invalid keys, keeps unspecified current settings, and never follows redirected paths, imports credentials, loads plugins or executes commands. The supported mappings, source references and tested boundaries are listed in [configuration files](configuration-files.md). Windows font names can fall back when unavailable; DPI-equivalent rendering is not established.

Size/date formatting now uses bounded per-thread caches keyed by relevant locale, time zone and formatting options. Repeated category navigation reuses controls. See [measured configuration performance](configuration-performance.md) for before/after data and limits; these do not establish Windows speed parity.

## Explicit remaining gaps

The category list exposes unsupported original areas as explanatory pages, without working-looking toggles. Page footers identify remaining limitations:

- Layout: vertical second button bar, drive-button bars, breadcrumb navigation and Windows themes.
- Display: separate Windows system attribute, DOS 8.3 modes, original four-way sort policy and plugin/comment tooltips.
- Icons: Windows EXE/LNK extraction, shell overlays, icon libraries and resolution profiles.
- Fonts: dialog DPI scaling and separate main-window/dialog/resolution profiles.
- Colors: alternating backgrounds, file-type rules, dark-mode palettes and all specialized viewer/compare/sync colors.
- Tabstops: configurable custom separators, 12-hour override and independent progress units.
- Tabs: locking, multiline layout, double-click closing, per-tab filters and full original Ctrl+Tab policies.
- Thumbnails: Lister/OLE providers, EXIF custom fields and persistent database management.
- Operation: tray behavior, file comments and all original mouse/confirmation options.
- Edit/View: per-extension associations, original encoding presets, Lister plugin ecosystem, fixed-column wrapping, parameter placeholders and unattended remote re-upload.
- History: thinning, frequent-folder ranking, fonts/icons and custom persistence locations.
- Custom Columns, View Modes, Copy/Delete options, Refresh policies, complete Quick Search dialog options, global FTP policy, external packers, Windows plugins, language packs and complete Ignore List semantics remain incomplete. Existing functional FTP/copy/search tools are not evidence that all of their configuration pages exist.

## Validation

`Tests/ConfigurationTests.swift` exercises legacy migration, durable typed round trips, field-level corruption recovery, imported range/color/column validation, enabled/path separation, every size-style persistence value, binary and decimal M/G/T boundaries, locale formatting, rounding precision, and date order/year/seconds behavior. Configuration dialog behavior and actual pane changes require integrated UI smoke checks in addition to these model tests.

The real AppKit configuration-window fixture additionally navigates every category, checks usable scroll geometry, changes the size-format popup, applies runtime settings without touching user defaults, and verifies Cancel leaves unapplied changes unapplied.

The configuration-file service has 44 focused assertions covering native schema validation, original size-style mappings, INI merge/report behavior, encodings, atomic writes and bounded regular-file reads. Expanded integrated and packaged-build validation is tracked separately in [TEST-RESULTS.md](../TEST-RESULTS.md).
