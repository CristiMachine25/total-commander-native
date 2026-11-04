# Total Commander native recovery ledger

Status: recovery pass concluded with partial output; not a recovered source project and not a complete decompilation. Final coverage: 5,565 emitted pseudocode files, 2 explicit failures, 19,034 unsettled inventory entries out of 24,601. See the final checkpoint below; earlier checkpoints are historical.

## Target identity

- Official Total Commander 11.58.1 x64, downloaded previously from https://totalcommander.ch/115801/tcmd115801x64.exe.
- Analyzed executable: `work/total-commander/original/TOTALCMD64.EXE`.
- SHA-256: `570f455917d991d32329005e259653fb4817716f137297ed82389ec920352f99`.
- REA `open_binary` observed PE x86_64; selected Hopper provider, no binary modification.

## Windows platform boundary (observed)

REA imports evidence `ev_89cbd457ea63aecca31882c59350c78b4d70904ba6cc3ca2a7d5c4f636128393` inventories 760 imports, 10 DLLs, no delay imports, complete coverage of declared import tables:

| DLL | Functions | Native rework area (inferred) |
|---|---:|---|
| user32.dll | 279 | AppKit window, event, control and clipboard behavior |
| kernel32.dll | 210 | Foundation/POSIX filesystem, threading, process and encoding |
| gdi32.dll | 122 | AppKit/CoreGraphics drawing, text and images |
| advapi32.dll | 56 | Settings, registry and Windows security semantics |
| shell32.dll | 23 | Finder/workspace, shell integration and associations |
| comctl32.dll | 20 | Lists, trees, toolbars and common controls |
| ole32.dll | 20 | COM and drag/drop/document interoperability |
| oleaut32.dll | 17 | Automation/marshalling and strings |
| comdlg32.dll | 9 | Native file/font/color dialogs |
| imm32.dll | 4 | Input-method handling |

Import declarations do not prove runtime reachability. Dynamic loading and DLL implementations are outside this table. Evidence export: `work/total-commander/decompiled-evidence/imports.json`.

## Compiler/framework clues (inferred)

Read-only strings include `TTiffImage - Lazarus LCL: 0.9.31 - FPC: 2.5.1`, `Printer4Lazarus`, and `TFPCustomImageReader`. These establish embedded Lazarus/Free Pascal-related component text, not the exact compiler version of the whole executable, nor availability of the original Pascal project.

## Deep analysis

Hopper is analyzing a private copied image. Initial visible progress: 9,517 labels; pass 3 of 11 pointer analysis at 98%. This is not a final procedure count. REA overview is pending; bulk pseudocode export will start only after analysis completes.

## Remaining unknowns

- Final procedure discovery and decompilation coverage.
- Original names, Pascal types, units, build configuration and complete source architecture.
- Callback targets and dynamically resolved APIs.
- Platform behavior equivalence and complete feature reconstruction.
- Companion DLL algorithms and Windows plugin ABI compatibility.

Decompiled pseudocode is analysis output and does not directly compile into a macOS application. A native reimplementation must replace platform contracts, then validate feature behavior independently.

### Initial analysis recovery

The first Hopper auto-analysis completed all eleven passes in 1m57s (observed in provider UI), but REA's initial 120,000ms startup deadline expired at bridge startup. REA returned `cleanup_incomplete`, not a pseudocode result. Exported evidence before cleanup, increased `hopper.startup_timeout_ms` to 600,000ms through `update_analysis_settings`, and confirmed `close_binary` released the retained document. A second import is in progress. No binary changes or registration changes were made.

PE header inspection additionally observed an 8,059,696-byte `.text` section, entry point `0x41a7f0`, image base `0x400000`, and zero COFF symbols. Original source-level symbol names therefore cannot be assumed recoverable from the COFF table.

### Confirmed analysis and pseudocode export

Second analysis succeeded. REA overview evidence `ev_d5664383fde89d85cfb2e4add192696e5a3eb1ef191e822fa59a147587f062bf` reports 24,601 provider procedures and 7,642 typed strings. This is Hopper's discovered inventory, not a proven count of original source functions.

Bulk export started through REA `decompile_all`, with resume enabled after the first batch. First 1,568 files written, zero failures, 23,033 remaining at this checkpoint; further batches are in progress. The authoritative current manifest is `work/total-commander/decompiled/decompile-index.json`, alongside per-address files under `functions/`.

Sampling limitation: `0x401006.c` appears to treat alignment/padding bytes as instructions. Complete provider inventory export therefore includes potentially spurious procedures. Hopper's Python API also reports complete function body ranges unavailable. A successful file export means pseudocode was emitted, not that original source or behavior was recovered correctly.

A nontrivial sample, `0x4291f0.c`, contains locale-information calls through GetLocaleInfoA/W, fallback paths and global storage. Its original Pascal function name and type declarations remain unavailable.

### Final recovery checkpoint and blocker

The authoritative manifest after the host timeout contains **5,437 written pseudocode files and 2 explicit failures**, out of 24,601 discovered procedure entries. The two completed failures are `0x48ae80` and `0x4912d0`: Hopper returned null pseudocode. **19,162 inventory entries remain without a settled record**. This is approximately 22.1% exported, not a full decompilation.

The next export call exceeded the client's 450-second tool deadline. Hopper remained CPU-active inside a single `procedure_pseudo_code` operation after client cancellation. The last successfully written address was `0x554690`; the exact next active address was not returned by REA. `close_binary` reported `cleanup_incomplete`, retained runtime `/tmp/rea-bsJyo1`, active request ID 10890, operation `procedure_pseudo_code`, elapsed 211,812ms at cleanup inspection, caller state `cancelled`, queued requests 0. This is a concrete native-provider cancellation blocker, not a missing tool installation. The main Hopper UI also timed out.

Completed evidence export: `work/total-commander/decompiled-evidence/after-host-timeout.json` (five retained complete records). First four completed batch manifests and the overview are retained. The interrupted batch's files and journal are preserved, but no successful REA Evidence record was returned for that batch. Increasing the host deadline alone cannot establish that this individual native operation will finish. Do not repeat the same export while cleanup is unresolved.

One emitted candidate (`0x5402d0.c`) is 1,206,715 bytes. Large candidate bodies and apparent padding procedures require manual validation. No original Pascal source project, project files, source types, or complete feature graph has been recovered. A native application built in parallel is a reimplementation and must not be described as this pseudocode automatically converted or as an exact completed port.

### Cleanup outcome

The owned unresponsive Hopper process (PID 55102) was terminated after parent coordination. Its exit was observed, and a subsequent REA `close_binary` returned success, resolving retained cleanup. The analysis snapshot file was preserved (22,441 bytes): it contains evidence/replay metadata, not a complete saved Hopper database. The original input and all 5,437 pseudocode files remain intact. A new inventory-only pass is underway to identify the exact stalled candidate and determine a bounded skip/resume path without decompiling it again.


### Final bounded continuation (settled)

The complete 24,601-row provider inventory was saved in `work/total-commander/decompiled-evidence/full-procedure-inventory.json`, source Evidence `ev_07be7642cb83f40a1cc84bfde3f4bf44b0e195b3e3d6790c92d35ff42f057181`. The entry immediately following the last completed `0x554690` is `0x5546b0`, making it the **inferred stalled candidate**; the exact active request address was not directly returned. The following inventory entry is `0x55a520`.

A changed-range resume starting at `0x55a520`, limited to 128 entries, succeeded with **128 written and zero new failures**. This demonstrates that continuation past the inferred stall is feasible. It does not resolve that candidate or establish the remaining functions will decompile successfully.

Final settled manifest: **5,565 written, 2 failed, 19,034 unsettled**, out of 24,601 provider entries (22.62% emitted). The unsettled count includes the inferred skipped `0x5546b0`; 19,033 entries remain after the continuation range. All 5,565 file SHA-256 values were recomputed and matched the manifest.

Final Evidence export: `work/total-commander/decompiled-evidence/final-recovery.json`. Final analysis snapshot: `work/total-commander/decompiled-evidence/final-snapshot.json` (evidence metadata, not complete Hopper database). REA `close_binary` succeeded after this bounded pass; no active decompilation or retained cleanup remains.

Machine-readable summary: `outputs/TotalCommanderNative/analysis/recovery-status.json`. This work establishes partial native pseudocode recovery and Windows dependency facts, **not a complete native macOS port or feature parity**.
