# Current interface parity audit — 0.5.0

Reference: Total Commander 11.58.1 KEYBOARD.TXT, WCMD_ENG.MNU, TOTALCMD.INC and locally extracted configuration/help pages. These document intent; paired original/native runtime equivalence is not established.

| Reference area | Implemented native scope | Remaining differences |
|---|---|---|
| Full and Brief | Detailed columns and actual column-major horizontal Brief with shared selection/marking, icons and configured fonts/colors | Fixed Brief column geometry and native cursor/selection behavior; not every original scrolling/selection setting |
| Tree and separate trees | Local directory tree pane; off/one/two separate trees, child expansion/navigation, current-path reveal and configured hidden/ignore filtering | Native outline controls; virtual-provider trees and complete original tree options remain incomplete |
| Thumbnails | Bounded image thumbnails, selection/navigation and configurable size | No complete Lister/OLE provider ecosystem, EXIF custom fields or original persistent database |
| Quick View | Opposite-pane text/hex/image preview follows selection; bounded remote materialization | No multimedia/plugins, recursive directory summary or separate-following Ctrl+Shift+Q window |
| Configuration | 24 category navigation entries, 13 with functional controls; 52 persisted typed settings | Remaining pages explicitly explain gaps. All original settings and original dialog geometry remain incomplete; INI import is a documented subset, not full compatibility |
| Configuration files | Original menu ID 581 opens a native JSON editor; strict full native import/export, reported partial original INI merge, and stale-editor protection | Native JSON rather than original INI direct editing; no complete INI export/roundtrip, redirection, plugin or shortcut configuration |
| Size display | Original ten Tabstops styles, decimal/binary units and independent footer style; native fixed MB/GB options clearly distinguished | Custom separators and independent progress units are incomplete; not every locale/original rounding combination has paired evidence |
| Quick Search and Ignore List | Configured modifier mode and beginning/ending semantics; display filtering including tree children | No complete original Quick Search dialog; ignore does not recursively exclude copy/move/sync contents |
| Provider navigation | Main panes/tabs/history for local, archive and FTP; provider root/parent semantics and display paths; asynchronous archive opening | Complete behavior across every format, shortcut and error context remains unverified |
| Archives | Broad bounded read/extract/test including ZIP64/password ZIP and RAR fixtures; ordinary ZIP edits propagate through nested/FTP origins | Non-ZIP/password sessions read-only; no complete packer/plugin/options/split-archive equivalence |
| Split/combine | Local tools routed from original Files menu IDs 560/561; fixture-tested part/manifest/CRC handling | Full original dialogs and every external part/manifest variant need paired tests |
| Shift+F2 | Marks missing names and newer files on their respective sides using displayed provider lists | Unknown dates and ambiguous case collisions skipped/reported; original tolerance/options not fully reproduced |
| Numeric selection | File/folder defaults are configurable; supported modifier variants and restore exist | Every original selection grammar, focus context and modifier combination not established |
| Context/properties | Native file-action popup and read-only local metadata | No Windows shell-extension menu/property-sheet equivalent |
| Command input | POSIX shell, supported internal symbols and path/name insertion | Windows command semantics, all parameters and every editing action are not implemented |

The original menu hierarchy, order and labels are retained from resources, with unsupported commands visibly disabled. The light two-pane presentation and configurable Tahoma font do not establish pixel identity: macOS chrome, AppKit controls, spacing, dialogs, system icons and focus behavior differ. Original toolbar resource evidence is preserved; not all toolbar customization or original commands are supported.

Unsupported modified destructive shortcuts must not fall through to less-modified operations. Function-key delivery also depends on macOS keyboard/Fn settings. See the shortcut contract suite for dispatch checks; dispatch tests alone do not prove every visible operation.

## Validation boundary

The 0.5 changes have focused configuration, configuration-file, formatter-isolation and pane regression coverage, with local before/after measurements retained in [configuration performance](configuration-performance.md), [pane responsiveness](pane-responsiveness.md), and [directory listing performance](directory-listing-performance.md). These are not paired Windows measurements. First-open configuration latency is essentially unchanged; ordinary local listing remains synchronous.

All 33 distinct test executions passed, including the separately completed final pane/provider checks; see the release ledger for execution details. [TEST-RESULTS.md](../TEST-RESULTS.md) records the final suite and exact packaged-artifact results. Earlier mounted 0.4 checks establish only their named interactions and do not certify new 0.5 changes.

[Configuration coverage](configuration-coverage.md) lists actual settings and gaps. [Native coverage](native-coverage.md) and [remaining requirements](remaining-parity-gaps.md) are synchronized with this scope. None certifies complete Total Commander parity.
