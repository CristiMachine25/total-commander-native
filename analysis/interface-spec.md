# Total Commander 11.58.1 native reconstruction baseline

This is an evidence inventory and implementation contract, not a claim that a native clone is complete. The current target is a native macOS application with no Wine dependency. Earlier Double Commander and Wine packaging reports are historical and are not parity evidence for this rebuild.

## Exact inputs and evidence boundary

The official extracted `TOTALCMD64.EXE` is 10,704,608 bytes, SHA-256 `570f455917d991d32329005e259653fb4817716f137297ed82389ec920352f99`.

| Bundled input | SHA-256 | What it establishes |
|---|---|---|
| `TOTALCMD.INC` | `cf25d733d8605283e62b68118ca0ec1e0b0a5de70c2144e7a1385bcd6ee4e713` | Declared command names, numeric identifiers, grouping and short descriptions |
| `LANGUAGE/WCMD_ENG.MNU` | `d400b02173508b4a78f12eee523dee8e248a09ced5ad58eb19b6ca4e99d73b02` | English menu hierarchy, mnemonic markers, command selectors and displayed accelerators |
| `e/KEYBOARD.TXT` | `cfeddacec4bc2e94fadd55e3c650d41d51b7dacf910d1245252dfc57788d7b39` | Documented key bindings, context distinctions and several conditional behaviors |

REA evidence `ev_565731903aca5f839c0fbd4f1324f3591aade55a3a95a03538bc903c82a21716`, retained in `outputs/TotalCommanderMac/docs/rea-totalcmd-resources.json`, contains 528 PE resource records, 539 resource directories and 62 icon groups for this exact executable. Its payloads other than icon-group relationships remain opaque. This evidence does **not** establish dialog layout, pixel-perfect rendering, command logic or runtime state transitions. Those need resource decoding, function recovery and controlled original-vs-native tests.

## Inventory

`feature-matrix.csv` has **857 evidence rows**: **621 command declarations**, **100 English menu actions**, and **136 keyboard-documentation records**. These are not 857 independent user features: aliases, pane-specific variants and overlapping menu/keyboard declarations occur. Every menu selector resolves to a bundled command declaration. Each row includes an exact source line, evidence type, proposed native requirement and unresolved validation.

The 621 declarations include 27 parameter-command entries with negative numbers. The file explicitly says these are translation IDs and **cannot be dispatched as numeric commands**. Sorting, custom views, tabs and view modes also describe ranges beyond the literal listed examples; the literal row count is not an exhaustive count of legal runtime command values.

| Command group | Literal declarations |
|---|---:|
| Source / Left / Right | 22 / 24 / 24 |
| File operations | 37 |
| Configuration | 36 |
| Network / FTP / Parallel port / Security | 6 / 9 / 3 / 3 |
| Miscellaneous / Print / Clipboard | 33 / 3 / 15 |
| Mark / Navigation | 46 / 37 |
| Help / Window / Command line / Tools | 6 / 4 / 7 / 15 |
| View / User menu / Tabs | 51 / 10 / 69 |
| Sorting / Custom column views / View modes | 44 / 49 / 41 |
| Parameter commands | 27 |

The top-level menu order is **Files, Mark, Commands, Net, Show, Configuration, Start, Help**. Start is a dynamic `STARTMENU` declaration, not a fixed set of actions. Files includes a Print submenu; Show includes Separate Tree states 0, 1 and 2. Preserve mnemonic markers as metadata separately from displayed labels.

## High-priority behavioral contracts

| Area | Bundled evidence / required behavior | Original behavior still requiring observation |
|---|---|---|
| Focus and selection | Tab changes active pane; source/target follow focus. Cursor and marked files are distinct. Insert/Space select; Space on an unselected directory calculates size, subject to settings. `KEYBOARD.TXT:87–95` | Mark-vs-multirow-selection precedence, exact cursor movement, selection after cancellation/errors |
| Copy / move | F5 copies; F6 moves/renames. Shift+F5 copies with rename in same directory; Shift+F6 renames in place. `KEYBOARD.TXT:11–12,44–46` | Overwrite/skip/replace/merge dialogs, cross-volume semantics, queued jobs, partial failures, metadata retention, cancellation |
| Deletion | F8/Delete uses configured recycle-bin/direct-delete mode; Shift reverses the configured behavior. `KEYBOARD.TXT:14,48` | Confirmation wording, Trash edge cases, remote/archive deletion, recoverability |
| Navigation | Backspace or Ctrl+PgUp goes parent; Ctrl+PgDn opens directory/archive; Ctrl+arrow navigates target; Alt+arrow history; Alt+Down history menu. `KEYBOARD.TXT:36–38,65–70` | Symlink, archive, unavailable-volume, permission-error and history-thinning behavior |
| File viewing/editing | F3 Lister, F4 editor; Shift+F3 only cursor file; alternate/internal-only viewer variants are separate. `KEYBOARD.TXT:9–10,19–20,42–43` | Encoding detection, binary/hex modes, large-file behavior, plugin dispatch and edit-save conflicts |
| Search | Alt+F7 find, Alt+Shift+F7 separate process, Ctrl+S quick filter, Ctrl+Shift+S previous filter. `KEYBOARD.TXT:26–27,130–133` | Complete search dialog controls, wildcard/regex grammar, content encodings, recursion and archive semantics, result feeding |
| Bulk rename | Ctrl+M opens multi-rename; parameter command `MULTIRENAME` opens a stored operation. `KEYBOARD.TXT:122`, `TOTALCMD.INC:655` | Mask grammar, counters, extension handling, presets, collision resolution, undo and preview semantics |
| Comparison/sync | Shift+F2 compares lists; separate content comparison and directory synchronization commands exist. `WCMD_ENG.MNU:6,47,57` | Matching algorithm, timestamp tolerance, recursion, directional actions, empty directories and safe preview/apply model |
| Archives | Alt+F5 pack; Alt+Shift+F5 move to archive; Alt+F6/F9 extract; Alt+Shift+F9 integrity test. `KEYBOARD.TXT:22–30` | Formats/options, encryption, split archives, archive paths, unsafe entry handling, atomic writes, nested browsing |
| Tabs | Ctrl+T foreground, Ctrl+Shift+T background, Ctrl+W close, Ctrl+Shift+W close all, Ctrl+U swap paths, Ctrl+Shift+U swap tabs too. `KEYBOARD.TXT:134–144` | Lock/reset states, session format, tab order/focus restoration, duplicate close behavior |
| Command line | Letter input redirects to command line; Enter executes nonempty command. Ctrl+A/C/X/V/W/T have text-editing meanings here that differ from panel meanings. `KEYBOARD.TXT:89,150–188` | DOS command translation, process output/exit handling, quoting, internal command grammar, external tool parameters |
| Menus | F9 activates menu above source window; F10 activates left menu or leaves menu. **Neither is Quit.** `KEYBOARD.TXT:15–16` | Menu placement, keyboard traversal and OS-reserved key delivery |
| Appearance | English menu and icons are retained, but the static resource inventory does not establish actual theme metrics. | Fonts, color values, row heights, borders, scaling, selection colors, icons, dialog spacing, dark-mode transitions |

## Native architecture implications (design inference)

Use a command dispatcher keyed by the recovered command identities, with explicit active/left/right/source/target routing. Keep file cursor, marked set, filter and tab history separate. Test focus-context routing before adding broad shortcut aliases: Ctrl+W closes a tab in panels but deletes a word in the command line. Use Control for documented Ctrl and Option for Alt; document any macOS-reserved combinations rather than silently changing originals.

Native file paths must be actual POSIX paths and mounted volumes, not Wine drive mappings. Native copy/move/delete should use a cancellable job model with per-item results and preserve available metadata; staging or preflight must not hide partial completion. Search and checksums must run off the UI thread and disclose unreadable files instead of silently treating them as absent. Archive extraction must reject traversal outside its chosen destination. Multi-rename requires a complete preview and collision check before committing changes.

AppKit can reproduce the classic in-window menu and pane layout while retaining normal macOS window lifecycle. AppKit defaults alone do not prove visual parity. A specific original light-theme capture, screen scale and preferences snapshot must anchor pixel comparisons.

## Explicit Windows boundaries

- Windows executable/plugin PE binaries cannot become native ARM64 code merely by loading them from an AppKit process. Each plugin API and required implementation needs a port or an explicitly incompatible replacement. Third-party plugin parity is not implied by core app parity.
- NTFS permissions, auditing and ownership dialogs (`cm_EditPermissionInfo`, `cm_EditAuditInfo`, `cm_EditOwnerInfo`) are not equivalent to POSIX mode bits and macOS ACLs.
- Windows share administration, admin shares, modern-share UI, shell associations and “open as different user” need explicit native behavior decisions.
- Parallel-port driver installation/removal commands target Windows NT through 11 and have no established direct macOS equivalent.
- DOS command execution and `NOCLOSE.EXE` behavior must be reworked for macOS process APIs and shell semantics; claiming identical command compatibility would be false.
- Original product registration/help/update entries are part of the documented menu, but a new implementation must not pretend to be an official Ghisler build or implement a registration bypass.

## Completion criteria

The matrix began with every row unassessed. It now marks a limited subset as **partial native implementation**, with implementation pointers and explicit validation boundaries; see `native-coverage.md`. Unassessed rows must not be treated as implemented. No row claims full original-vs-native conformance. Recovering a function body establishes recovered pseudocode, not feature completion. A menu item that displays a message is not an implemented operation. A buildable dual-pane app is a first implementation slice, not the full 621-declaration surface.

Required remaining work includes dialog/resource decoding, command-to-procedure mapping, executable behavior tests, native operation implementation, visual comparison at a fixed scale, archive/network/plugin coverage and packaging on a machine without Wine. Final reports must state exact pass/fail/untested coverage and retain unsupported Windows-specific behavior explicitly.
