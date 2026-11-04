# Keyboard contract audit

Reference: bundled Total Commander 11.58.1 `work/total-commander/original/e/KEYBOARD.TXT`. Control stays Control; Windows Alt maps to macOS Option. Physical function/numeric-keypad codes ignore Caps Lock/Fn/numpad event metadata but require an exact match of Control/Shift/Option/Command. Unsupported combinations must not invoke a less-modified destructive operation.

## Changes and API

[KeyboardFeatures.swift](../Sources/KeyboardFeatures.swift) keeps `handleExtendedKey(_:modifiers:)`; it first routes the exact bindings below through `ShortcutContract.action`. The controller consumes busy requests without executing. Parent owns asynchronous navigation via `selectTab(_:pane:)`, `openLocationInNewTab(_:pane:background:)`, `swapPaneTabs()`, `reloadPane(_:)` and `navigate(_:pane:completion:)`. Histories/tabs retain `PaneLocation`, and session persistence stores only local tabs. No fake local fallback may act on a remote/archive panel.

- Shift+F5: one selected local item, prompt for a different valid basename, copy without overwrite. Batch rename-copy is explicitly unsupported. Shift+F7 creates in the captured target local folder with the cursor name as default.
- Ctrl+Shift+U delegates complete tab/location swapping; Ctrl+Shift+A shows the active panel's tab list. Ctrl+Up / Ctrl+Shift+Up open the child/current location in an active/other-panel tab. Ctrl+Left/Right use provider child/current locations instead of fake filesystem URLs. Opening an unopened ZIP through these arrow/tab shortcuts is not yet supported; Enter uses the parent provider integration.
- The configured baseline selection includes files and folders. Shift numeric selection/inversion therefore uses files only; Ctrl+Shift+Minus removes files while preserving marked folders. Alt numeric +/- matches the cursor file's extension. Full original configurable selection semantics remain incomplete.
- Shift+F10 shows a native file-action popup, not Windows shell extension menus.
- Ctrl+Q now toggles a true opposite-main-pane Quick View in [QuickView.swift](../Sources/QuickView.swift), updated from source selection. It preserves the target location and uses asynchronous provider materialization, generation guards, bounded text/hex/image previews and FTP download limits. Its visible behavior is pending validation; the 349 routing checks below do not cover this later addition. Shift+F8, Alt+Shift+F5 and other unsupported destructive variants are not mapped to plain Trash/copy/pack.

## Validation boundary

[ShortcutContractTests.swift](../Tests/ShortcutContractTests.swift): **349 checks passed**, including every modifier combination for these 18 bindings, ignored metadata flags, no unsupported destructive fallthrough, selection-set behavior, filename validation and original-reference presence. This is pure routing/selection validation, not evidence that all UI actions or async navigation completed. Parent integration/UI regression remains required after providers are integrated.

Run: `xcrun swiftc -D SHORTCUT_CONTRACT_TEST -swift-version 5 -framework AppKit Sources/KeyboardFeatures.swift Tests/ShortcutContractTests.swift -o /tmp/tc-shortcut-contract`, then pass the original KEYBOARD.TXT path to the executable. This flag excludes controller-dependent code only in the isolated test build.

## Machine-readable exact added routes

```json
[
  {
    "keycode": 96,
    "modifiers": [
      "shift"
    ],
    "action": "copySameFolder",
    "reference": "SHIFT+F5",
    "status": "implemented_partial; routing tested; visible action test pending"
  },
  {
    "keycode": 98,
    "modifiers": [
      "shift"
    ],
    "action": "mkdirTarget",
    "reference": "SHIFT+F7",
    "status": "implemented_partial; routing tested; visible action test pending"
  },
  {
    "keycode": 109,
    "modifiers": [
      "shift"
    ],
    "action": "contextMenu",
    "reference": "SHIFT+F10",
    "status": "implemented_partial; routing tested; visible action test pending"
  },
  {
    "keycode": 32,
    "modifiers": [
      "control",
      "shift"
    ],
    "action": "swapTabs",
    "reference": "CTRL+SHIFT+U",
    "status": "implemented_partial; routing tested; visible action test pending"
  },
  {
    "keycode": 0,
    "modifiers": [
      "control",
      "shift"
    ],
    "action": "tabList",
    "reference": "CTRL+SHIFT+A",
    "status": "implemented_partial; routing tested; visible action test pending"
  },
  {
    "keycode": 48,
    "modifiers": [
      "control"
    ],
    "action": "nextTab",
    "reference": "CTRL+TAB",
    "status": "implemented_partial; routing tested; visible action test pending"
  },
  {
    "keycode": 48,
    "modifiers": [
      "control",
      "shift"
    ],
    "action": "previousTab",
    "reference": "CTRL+SHIFT+TAB",
    "status": "implemented_partial; routing tested; visible action test pending"
  },
  {
    "keycode": 123,
    "modifiers": [
      "control"
    ],
    "action": "openLeft",
    "reference": "CTRL+left",
    "status": "implemented_partial; routing tested; visible action test pending"
  },
  {
    "keycode": 124,
    "modifiers": [
      "control"
    ],
    "action": "openRight",
    "reference": "CTRL+right",
    "status": "implemented_partial; routing tested; visible action test pending"
  },
  {
    "keycode": 126,
    "modifiers": [
      "control"
    ],
    "action": "childTab",
    "reference": "CTRL+UP",
    "status": "implemented_partial; routing tested; visible action test pending"
  },
  {
    "keycode": 126,
    "modifiers": [
      "control",
      "shift"
    ],
    "action": "childTargetTab",
    "reference": "CTRL+SHIFT+UP",
    "status": "implemented_partial; routing tested; visible action test pending"
  },
  {
    "keycode": 69,
    "modifiers": [
      "shift"
    ],
    "action": "selectPatternFiles",
    "reference": "SHIFT+NUM +",
    "status": "implemented_partial; routing tested; visible action test pending"
  },
  {
    "keycode": 78,
    "modifiers": [
      "shift"
    ],
    "action": "unselectPatternFiles",
    "reference": "SHIFT+NUM -",
    "status": "implemented_partial; routing tested; visible action test pending"
  },
  {
    "keycode": 67,
    "modifiers": [
      "shift"
    ],
    "action": "invertFiles",
    "reference": "SHIFT+NUM *",
    "status": "implemented_partial; routing tested; visible action test pending"
  },
  {
    "keycode": 69,
    "modifiers": [
      "control",
      "shift"
    ],
    "action": "selectFiles",
    "reference": "CTRL+SHIFT+NUM +",
    "status": "implemented_partial; routing tested; visible action test pending"
  },
  {
    "keycode": 78,
    "modifiers": [
      "control",
      "shift"
    ],
    "action": "unselectFiles",
    "reference": "CTRL+SHIFT+NUM -",
    "status": "implemented_partial; routing tested; visible action test pending"
  },
  {
    "keycode": 69,
    "modifiers": [
      "option"
    ],
    "action": "selectExtension",
    "reference": "ALT+NUM +",
    "status": "implemented_partial; routing tested; visible action test pending"
  },
  {
    "keycode": 78,
    "modifiers": [
      "option"
    ],
    "action": "unselectExtension",
    "reference": "ALT+NUM -",
    "status": "implemented_partial; routing tested; visible action test pending"
  }
]
```

## Full reference audit index

Each JSONL record identifies a bundled keyboard row and its documented expectation. `previous_partial` means prior matrix evidence only, not full equivalence or newly tested coverage. `unimplemented_or_unverified` must not be counted as supported. Command-line editing rows are separate contexts and do not inherit file-panel bindings.

```jsonl
{"id": "K0001", "key": "F1", "expected": "Help", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:7"}
{"id": "K0002", "key": "F2", "expected": "Reread source window", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:8"}
{"id": "K0003", "key": "F3", "expected": "List files", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:9"}
{"id": "K0004", "key": "F4", "expected": "Edit files", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:10"}
{"id": "K0005", "key": "F5", "expected": "Copy files", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:11"}
{"id": "K0006", "key": "F6", "expected": "Rename or move files", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:12"}
{"id": "K0007", "key": "F7", "expected": "Create directory", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:13"}
{"id": "K0008", "key": "F8 or DEL", "expected": "Delete files to recycle bin /delete directly - according to configuration", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:14"}
{"id": "K0009", "key": "F9", "expected": "Activate menu above source window (left or right)", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:15"}
{"id": "K0010", "key": "F10", "expected": "Activate left menu or leave menu", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:16"}
{"id": "K0011", "key": "ALT+F1", "expected": "Change left drive", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:17"}
{"id": "K0012", "key": "ALT+F2", "expected": "Change right drive", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:18"}
{"id": "K0013", "key": "ALT+F3", "expected": "Use alternate (external or internal) viewer", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:19"}
{"id": "K0014", "key": "ALT+SHIFT+F3", "expected": "Start Lister and load file with internal viewer (no plugins or multimedia)", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:20"}
{"id": "K0015", "key": "ALT+F4", "expected": "Exit | Minimize (with option MinimizeOnClose, see help)", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:21"}
{"id": "K0016", "key": "ALT+F5", "expected": "Pack selected files", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:22"}
{"id": "K0017", "key": "ALT+SHIFT+F5", "expected": "Move to archive", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:23"}
{"id": "K0018", "key": "ALT+F6", "expected": "Unpack specified files from archive under cursor, or selected archives (use Alt+F9 on Windows 95)", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:24"}
{"id": "K0019", "key": "ALT+F7", "expected": "Find", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:26"}
{"id": "K0020", "key": "ALT+SHIFT+F7", "expected": "Find in separate process", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:27"}
{"id": "K0021", "key": "ALT+F8", "expected": "Opens the history list of the command line", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:28"}
{"id": "K0022", "key": "ALT+F9", "expected": "Same as ALT+F6 (because ALT+F6 is broken on Windows 95)", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:29"}
{"id": "K0023", "key": "ALT+SHIFT+F9", "expected": "Test archives for integrity", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:30"}
{"id": "K0024", "key": "ALT+F10", "expected": "Opens a dialog box with the current directory tree", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:31"}
{"id": "K0025", "key": "ALT+F11", "expected": "Opens left current directory bar (breadcrumb bar)", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:32"}
{"id": "K0026", "key": "ALT+F12", "expected": "Opens right current directory bar (breadcrumb bar)", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:33"}
{"id": "K0027", "key": "ALT+SHIFT+F11", "expected": "Focus the horizontal button bar to use it with the keyboard", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:34"}
{"id": "K0028", "key": "ALT+SHIFT+F12", "expected": "Focus the vertical button bar to use it with the keyboard", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:35"}
{"id": "K0029", "key": "ALT+left or right", "expected": "Go to previous/next dir of already visited dirs", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:36"}
{"id": "K0030", "key": "ALT+down", "expected": "Open history list of already visited dirs (like the history list in a WWW browser)", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:37"}
{"id": "K0031", "key": "ALT+SHIFT+down", "expected": "Open history list of already visited dirs without history thinning", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:39"}
{"id": "K0032", "key": "SHIFT+F1", "expected": "Custom columns view menu", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:40"}
{"id": "K0033", "key": "SHIFT+F2", "expected": "Compare file lists", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:41"}
{"id": "K0034", "key": "SHIFT+F3", "expected": "List only file under cursor, when multiple files selected", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:42"}
{"id": "K0035", "key": "SHIFT+F4", "expected": "Create new text file and load into editor", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:43"}
{"id": "K0036", "key": "SHIFT+F5", "expected": "Copy files (with rename) in the same directory", "status": "new_partial_route", "evidence": "e/KEYBOARD.TXT:44"}
{"id": "K0037", "key": "SHIFT+CTRL+F5", "expected": "Create shortcuts of the selected files in target directory", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:45"}
{"id": "K0038", "key": "SHIFT+F6", "expected": "Rename files in the same directory", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:46"}
{"id": "K0039", "key": "SHIFT+F7", "expected": "Create directory in target folder, using name under cursor as default", "status": "new_partial_route", "evidence": "e/KEYBOARD.TXT:47"}
{"id": "K0040", "key": "SHIFT+F8/DEL", "expected": "Delete directly / delete to recycle bin - according to configuration", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:48"}
{"id": "K0041", "key": "SHIFT+F10", "expected": "Show context menu", "status": "new_partial_route", "evidence": "e/KEYBOARD.TXT:49"}
{"id": "K0042", "key": "SHIFT+ESC", "expected": "Minimizes Total Commander to an icon", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:50"}
{"id": "K0043", "key": "NUM +", "expected": "Expand selection (configurable: just files or files and folders)", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:51"}
{"id": "K0044", "key": "NUM -", "expected": "Shrink selection", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:52"}
{"id": "K0045", "key": "NUM *", "expected": "Invert selection (also with shift, see help)", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:53"}
{"id": "K0046", "key": "NUM /", "expected": "Restore selection", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:54"}
{"id": "K0047", "key": "SHIFT+NUM +", "expected": "Like NUM +, but files and folders if NUM + selects just files and vice versa", "status": "new_partial_route", "evidence": "e/KEYBOARD.TXT:55"}
{"id": "K0048", "key": "SHIFT+NUM -", "expected": "Always removes the selection just from files (NUM- from files and folders)", "status": "new_partial_route", "evidence": "e/KEYBOARD.TXT:56"}
{"id": "K0049", "key": "SHIFT+NUM *", "expected": "Like NUM *, but files and folders if NUM * inverts selection of just files (and vice versa)", "status": "new_partial_route", "evidence": "e/KEYBOARD.TXT:57"}
{"id": "K0050", "key": "CTRL+NUM +", "expected": "Select all (configurable: just files or files and folders)", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:59"}
{"id": "K0051", "key": "CTRL+SHIFT+NUM +", "expected": "Select all (files and folders if CTRL+NUM + selects only files)", "status": "new_partial_route", "evidence": "e/KEYBOARD.TXT:60"}
{"id": "K0052", "key": "CTRL+NUM -", "expected": "Deselect all (always files and folders)", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:61"}
{"id": "K0053", "key": "CTRL+SHIFT+NUM -", "expected": "Deselect all (always files, no folders)", "status": "new_partial_route", "evidence": "e/KEYBOARD.TXT:62"}
{"id": "K0054", "key": "ALT+NUM +", "expected": "Select all files with the same extension", "status": "new_partial_route", "evidence": "e/KEYBOARD.TXT:63"}
{"id": "K0055", "key": "ALT+NUM -", "expected": "Remove selection from files with the same extension", "status": "new_partial_route", "evidence": "e/KEYBOARD.TXT:64"}
{"id": "K0056", "key": "CTRL+PgUp or BACKSPACE", "expected": "Change to parent directory (corresponds to cd ..)", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:65"}
{"id": "K0057", "key": "CTRL+PgDn", "expected": "Open directory/archive (also self extracting .EXE archives)", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:66"}
{"id": "K0058", "key": "CTRL+<", "expected": "Jump to the root directory (most European keyboards)", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:67"}
{"id": "K0059", "key": "CTRL+\\", "expected": "Jump to the root directory (US keyboard)", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:68"}
{"id": "K0060", "key": "CTRL+left or right", "expected": "Open directory/archive and display it in the target window. If the cursor is not on a directory name, or the other panel is active, then the current directory is displayed instead.", "status": "new_partial_route", "evidence": "e/KEYBOARD.TXT:69"}
{"id": "K0061", "key": "CTRL+F1", "expected": "File display 'brief' (only file names)", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:72"}
{"id": "K0062", "key": "CTRL+SHIFT+F1", "expected": "Thumbnails view (preview pictures)", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:73"}
{"id": "K0063", "key": "CTRL+F2", "expected": "File display 'full' (all file details)", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:74"}
{"id": "K0064", "key": "CTRL+SHIFT+F2", "expected": "Comments view (new comments are created with Ctrl+Z)", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:75"}
{"id": "K0065", "key": "CTRL+F3", "expected": "Sort by name", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:76"}
{"id": "K0066", "key": "CTRL+F4", "expected": "Sort by extension", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:77"}
{"id": "K0067", "key": "CTRL+F5", "expected": "Sort by date/time", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:78"}
{"id": "K0068", "key": "CTRL+F6", "expected": "Sort by size", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:79"}
{"id": "K0069", "key": "CTRL+F7", "expected": "Unsorted", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:80"}
{"id": "K0070", "key": "CTRL+F8", "expected": "Display directory tree", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:81"}
{"id": "K0071", "key": "CTRL+SHIFT+F8", "expected": "Cycle through separate directory tree states: one tree, two trees, off", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:82"}
{"id": "K0072", "key": "CTRL+F9", "expected": "Print file under cursor using the associated program", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:83"}
{"id": "K0073", "key": "CTRL+F10", "expected": "Show all files", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:84"}
{"id": "K0074", "key": "CTRL+F11", "expected": "Show only programs", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:85"}
{"id": "K0075", "key": "CTRL+F12", "expected": "Show user defined files", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:86"}
{"id": "K0076", "key": "TAB", "expected": "Switch between left and right file list", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:87"}
{"id": "K0077", "key": "SHIFT+TAB", "expected": "Switch between current file list and separate tree (if enabled)", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:88"}
{"id": "K0078", "key": "Letter", "expected": "Redirected to command line, cursor jumps to command line", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:89"}
{"id": "K0079", "key": "INSERT", "expected": "Select file or directory", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:90"}
{"id": "K0080", "key": "SPACE", "expected": "Select file or directory (as INSERT). If SPACE is used on an unselected directory under the cursor, the contents in this directory are counted and the size is shown in the 'full' view instead of the string <DIR>. This can be disabled through 'Configuration' - 'Options' - 'Operation' - 'Selection with Space'.", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:91"}
{"id": "K0081", "key": "ENTER", "expected": "Change directory/run program/run associated program/execute command line if not empty. If the source directory shows the contents of an archive, further information on the packed file is given.", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:96"}
{"id": "K0082", "key": "SHIFT+ENTER", "expected": "1. Runs command line/program under cursor via Windows shell and leave the program's window open. Only works if NOCLOSE.EXE is present in the Total Commander directory! 2. With ZIP files: use alternative choice of these (as chosen in Packer config): (Treat archives like directories <-> call associated program, i.e. winzip or quinzip). 3. In the list of last used dirs (History, Ctrl+D), open the directory on a new Tab.", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:99"}
{"id": "K0083", "key": "ALT+SHIFT+ENTER", "expected": "The contents of all directories in the current directory are counted. The sizes of the directories are then shown in the 'full' view instead of the string <DIR>. Abort by holding down ESC key.", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:107"}
{"id": "K0084", "key": "ALT+ENTER", "expected": "Show property sheet. When done on [..] it will show the properties of the current directory.", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:110"}
{"id": "K0085", "key": "CTRL+A", "expected": "Select all", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:112"}
{"id": "K0086", "key": "CTRL+SHIFT+A", "expected": "Show list of all open tabs as a menu (as in the Chrome browser)", "status": "new_partial_route", "evidence": "e/KEYBOARD.TXT:113"}
{"id": "K0087", "key": "CTRL+B", "expected": "Directory branch: Show contents of current dir and all subdirs in one list", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:114"}
{"id": "K0088", "key": "CTRL+SHIFT+B", "expected": "Directory branch for selected directories: show contents of selected dir and all subdirs in one list", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:115"}
{"id": "K0089", "key": "CTRL+C", "expected": "Copy files to clipboard", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:117"}
{"id": "K0090", "key": "CTRL+D", "expected": "Open directory hotlist ('bookmarks')", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:118"}
{"id": "K0091", "key": "CTRL+F", "expected": "Connect to FTP server", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:119"}
{"id": "K0092", "key": "CTRL+SHIFT+F", "expected": "Disconnect from FTP server, port connection, and some file system plugins", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:120"}
{"id": "K0093", "key": "CTRL+I", "expected": "Switch to target directory", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:121"}
{"id": "K0094", "key": "CTRL+L", "expected": "Calculate occupied space (of the selected files)", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:122"}
{"id": "K0095", "key": "CTRL+M", "expected": "Multi-Rename-Tool", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:123"}
{"id": "K0096", "key": "CTRL+SHIFT+M", "expected": "Change FTP transfer mode", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:124"}
{"id": "K0097", "key": "CTRL+N", "expected": "New FTP connection (enter URL or host address)", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:125"}
{"id": "K0098", "key": "CTRL+P", "expected": "Copy current path to command line", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:126"}
{"id": "K0099", "key": "CTRL+Q", "expected": "Show Quick View panel instead of a file list", "status": "implemented_partial_quickview; source inspected; visible pending", "evidence": "e/KEYBOARD.TXT:127"}
{"id": "K0100", "key": "CTRL+SHIFT+Q", "expected": "Separate quick view window (like Lister, but updates with cursor movement)", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:128"}
{"id": "K0101", "key": "CTRL+R", "expected": "Reread source directory", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:129"}
{"id": "K0102", "key": "CTRL+S", "expected": "Open Quick Filter dialog and activate filter (deactivate with ESC or CTRL+F10)", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:130"}
{"id": "K0103", "key": "CTRL+SHIFT+S", "expected": "Open Quick Filter dialog and reactivate last-used filter", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:132"}
{"id": "K0104", "key": "CTRL+T", "expected": "Open new folder tab and activate it", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:133"}
{"id": "K0105", "key": "CTRL+SHIFT+T", "expected": "Open new folder tab, but do not activate it", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:134"}
{"id": "K0106", "key": "CTRL+U", "expected": "Exchange directories", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:135"}
{"id": "K0107", "key": "CTRL+SHIFT+U", "expected": "Exchange directories and tabs", "status": "new_partial_route", "evidence": "e/KEYBOARD.TXT:136"}
{"id": "K0108", "key": "CTRL+V", "expected": "Paste from clipboard to current dir", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:137"}
{"id": "K0109", "key": "CTRL+W", "expected": "Close currently active tab", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:138"}
{"id": "K0110", "key": "CTRL+SHIFT+W", "expected": "Close all open tabs", "status": "previous_partial", "evidence": "e/KEYBOARD.TXT:139"}
{"id": "K0111", "key": "CTRL+X", "expected": "Cut files to clipboard", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:140"}
{"id": "K0112", "key": "CTRL+Z", "expected": "Edit file comment", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:141"}
{"id": "K0113", "key": "CTRL+UP", "expected": "Open dir under cursor in new tab", "status": "new_partial_route", "evidence": "e/KEYBOARD.TXT:142"}
{"id": "K0114", "key": "CTRL+SHIFT+UP", "expected": "Open dir under cursor in other window (new tab)", "status": "new_partial_route", "evidence": "e/KEYBOARD.TXT:143"}
{"id": "K0115", "key": "CTRL+TAB", "expected": "Jump to next tab", "status": "new_partial_route", "evidence": "e/KEYBOARD.TXT:144"}
{"id": "K0116", "key": "CTRL+SHIFT+TAB", "expected": "Jump to previous tab", "status": "new_partial_route", "evidence": "e/KEYBOARD.TXT:145"}
{"id": "K0117", "key": "ALTGR+Letter(s) or", "expected": "Quick search for a file name (starting with specified letters) in the", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:146"}
{"id": "K0118", "key": "CTRL+ALT+Letter(s)", "expected": "current directory (Support hotkeys Ctrl+X, Ctrl+C, Ctrl+V and Ctrl+A; use Ctrl+S for search filter on/off)", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:147"}
{"id": "K0119", "key": "ENTER", "expected": "The command line is executed, if it contains at least one character (otherwise, the program under the cursor in the source window is started). If the command is cd, md or rd, it is executed internally. If it is an internal DOS command, DOS will be executed with this command. Otherwise, a program with the given name is executed.", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:156"}
{"id": "K0120", "key": "SHIFT+ENTER", "expected": "Like ENTER, but via Windows shell. After the called DOS program is terminated, its window is not automatically closed. This will only work if the file NOCLOSE.EXE is in the Total Commander directory.", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:161"}
{"id": "K0121", "key": "CTRL+ENTER", "expected": "The file under the cursor in the source directory is added to the end of the command line.", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:164"}
{"id": "K0122", "key": "CTRL+SHIFT+ENTER", "expected": "The file under the cursor including its path is added to the end of the command line.", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:166"}
{"id": "K0123", "key": "CTRL+CURSORDOWN or", "expected": "A list with the latest command lines (history-list) is opened. Use", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:168"}
{"id": "K0124", "key": "ALT+F8", "expected": "the up and down cursor keys (with or without the CTRL key) to select an entry. By pressing the left or right key, you can edit the command line. This automatically closes the list.", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:169"}
{"id": "K0125", "key": "TAB", "expected": "Puts the cursor back to the source directory.", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:172"}
{"id": "K0126", "key": "Cursor keys", "expected": "Cursor left and cursor right move the cursor through the command line, even if the cursor was in the source directory before. If Brief view is selected, these keys move the cursor through the source directory. You then have to hold down SHIFT to move it inside the command line. Cursor up and cursor down move the cursor bar inside the source window, even if it was inside the command line.", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:173"}
{"id": "K0127", "key": "ESC", "expected": "Clears the command line, put cursor back in file window.", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:179"}
{"id": "K0128", "key": "CTRL+A", "expected": "Select entire command line", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:180"}
{"id": "K0129", "key": "CTRL+Y", "expected": "Clears the command line, cursor stays in command line.", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:181"}
{"id": "K0130", "key": "CTRL+C", "expected": "Copy selected text to clipboard", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:182"}
{"id": "K0131", "key": "CTRL+X", "expected": "Cut selected text to clipboard", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:183"}
{"id": "K0132", "key": "CTRL+V", "expected": "Paste text from clipboard to command line.", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:184"}
{"id": "K0133", "key": "CTRL+E", "expected": "Copy previous command to command line", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:185"}
{"id": "K0134", "key": "CTRL+K", "expected": "Delete to end of line", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:186"}
{"id": "K0135", "key": "CTRL+W", "expected": "Delete the word to the left of the cursor", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:187"}
{"id": "K0136", "key": "CTRL+T", "expected": "Delete the word to the right of the cursor", "status": "unimplemented_or_unverified", "evidence": "e/KEYBOARD.TXT:188"}
```
