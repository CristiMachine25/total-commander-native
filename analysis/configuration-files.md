# Configuration file exchange

Native version 1 JSON files export and restore the entire `CommanderConfiguration` schema. The envelope identifies `total-commander-native-configuration`, version 1, and a `configuration` object. Export uses atomic replacement. Import is data-only and returns a configuration without changing saved preferences. UI callers choose when to apply/save it.

Strict native import rejects unknown versions, missing/unknown settings, wrong field types, enum values, values that would be clamped or normalized, and duplicate JSON keys. The file must contain a complete exported configuration rather than a partial patch. This intentionally differs from the tolerant local-persistence migration decoder. Native exports include configured external application paths but never launch them during import.

The 1 MiB bounded reader opens files without following symbolic links or blocking on FIFOs, validates the opened descriptor as a bounded regular file, and limits the actual read. INI text supports UTF-8, BOM-marked UTF-16, and Windows-1252. Imports do not follow `RedirectSection`/`AlternateUserIni`, resolve Windows paths, load DLLs, import credentials, or execute commands. Reports contain section/key names and reasons, not input values. Duplicate INI keys are invalid rather than silently overriding one another. Unspecified, invalid, and unsupported settings preserve the current native values.

## Partial original wincmd.ini import

This is a supported subset, not full wincmd.ini compatibility. Original source evidence is the extracted Total Commander 11.58.1 English help retained in `work/total-commander/help-extracted` in the investigation workspace.

| Original section/key | Mapping | Original help evidence |
|---|---|---|
| Configuration / SizeStyle, SizeFooter | All original values 0–9 mapped to the native byte/kbyte/dynamic G/T-limited styles | inisettings2.htm lines 216–219 |
| Configuration / SizeStyle1000 | Binary 1024 vs decimal 1000 units | inisettings2.htm lines 220–222 |
| Configuration / ShowHiddenSystem | 0 hides, 2 shows hidden; 1 shows hidden and reports unavailable system-attribute behavior; 3 is invalid/unsupported | inisettings2.htm lines 199–202 |
| Configuration / ShowIcons | 0 none, 1 standard, 2 native system icons | inisettings2.htm line 203 |
| Configuration / DirTabLimit | Native 8–100 character limit; unsupported out-of-range values reported | inisettings1.htm line 271 |
| Configuration / DirTabOptions | Flags 1 (always visible) and 128 (new tabs near current); any remaining flags explicitly reported unsupported | inisettings1.htm lines 274–285 |
| Configuration / QuickSearchMatchBeginning, QuickSearchExactMatch | Native beginning/ending matching controls | inisettings2.htm lines 104–108 |
| Layout / ButtonBar, CmdLine, CurDir, DirectoryTabs, DriveCombo, KeyButtons, StatusBar, TabHeader | Eight direct visibility booleans | inisettings3.htm lines 204–220 |
| AllResolutions / FontName, FontSize, FontWeight | Native file-list font; size 9–36, weights 400/700 only | inisettings3.htm lines 42–43, 70–75 |

Fonts not installed on macOS fall back through normal native font handling. Windows font-size/DPI rendering equivalence is not established. Resolution-specific font sections and semibold/custom weight values remain unsupported and are reported. All other sections/keys (including shortcuts, aliases, plugin paths, FTP credentials, editor command lines, packers, and redirects) are reported unsupported rather than inferred or executed.

## Verification

`ConfigurationFilesTests.swift` has 44 assertions covering full native/default round trips, strict rejection, duplicate keys, all ten original size-style mappings, independent footer units, layout, fonts, tab flags, preservation of unspecified/invalid options, unsupported-command reporting without values, UTF-16 input, atomic replacement, and symlink/FIFO/directory/oversized-file rejection.

Focused command:

```
xcrun swiftc -swift-version 5 -framework AppKit Sources/ConfigurationModel.swift Sources/ConfigurationFiles.swift Tests/ConfigurationFilesTests.swift -o /tmp/tc-config-files-tests
/tmp/tc-config-files-tests
```
