# Native validation ledger

## 0.5.1 validation — 4 November 2026

Targeted interaction update: 24 context-menu regression assertions passed against a frozen full-source snapshot. Coverage includes clicked-pane activation, marked-group preservation/replacement, blank space and parent rows, Full/Brief/thumbnail hit testing, stale-action rejection, busy/loading guards, and FTP/read-only archive action availability. The optimized application passed its configuration/UI smoke including Escape from command/path fields and Space marking nonadjacent rows; see [smoke output](analysis/0.5.1-smoke.log). The complete backend suite was not repeated for this interaction-only update; 0.5.0 results remain separately recorded below.

Visible checks in the mounted optimized 0.5.1 application:

- Right-click and Control-click on a demo file opened the file action menu; View opened the matching file contents in Lister.
- Shift+F10 opened the shared file context menu.
- Escape left the command field; arrows and Space marked two nonadjacent demo files, confirmed by checkmarks and the selected-file footer.
- README screenshots show generated demo files only, plus the configuration size-display page. Both images were visually reviewed. Temporary demo folders were deleted afterward, and the prior pane paths and folder-tab visibility were restored.

These checks establish the listed interactions, not full original application parity.

## 0.5.0 validation — 4 November 2026

All 33 distinct test executions passed. The initial harness run completed through panel tests; removing duplicate test invocations while it was running interrupted the shell's remaining script read. The final PaneView, PanePerformance and ProviderIntegration executions were therefore run explicitly against a frozen source snapshot and all exited 0. The combined evidence is [0.5-final-test-run.log](analysis/0.5-final-test-run.log). Two repeated formatter/file-service runs in that log are not additional coverage.

New/expanded checks: 1,001 formatter isolation assertions, 44 configuration-file assertions, 37 real configuration-dialog assertions including stale-editor rejection, 37 filesystem assertions including directory/file/broken symlinks, 13 large-pane regression assertions, 30 pane-view assertions, and 31 original-menu assertions. The optimized bundled application also passed its configuration and UI smoke, including JSON editor Apply and preference preservation.

Mounted optimized 0.5 UI observations:

- Original Configuration → Change Settings Files Directly opened the editable native JSON window.
- Export through NSSavePanel wrote a valid version 1 JSON file containing the current native settings; its contents were independently checked.
- Importing a disposable INI reported two imported options and one unsupported option, staged the correct size format/unit base, and did not apply without the Apply action.
- Scrolled a 120-file disposable listing, selected a reused row and moved with Down: filename, extension, size, tooltip and white-on-blue selection remained correct.
- Restored the home folder. Existing automatic size units remained intact.

Measured local performance, with scopes and limitations in the linked reports:

- 10k size formats: 208.61 → 13.03 ms; dates: 976.12 → 19.63 ms.
- 80 settings category switches/layouts: 2302.28 → 540.26 ms; first open approximately unchanged.
- 10k-entry directory listing: 144.81 → 121.23 ms; local navigation remains synchronous.
- Single-selection footer over 10k rows: 0.8872 → 0.0042 ms/op. The no-op Apply benchmark is not a measurement of changed settings.

See [settings performance](analysis/configuration-performance.md), [pane performance](analysis/pane-responsiveness.md), and [listing performance](analysis/directory-listing-performance.md). These establish measured improvements on this Mac, not speed equivalence with Windows. Backend FTP tests used disposable localhost servers; this release did not repeat the historical visible production-style FTP workflow. Full original settings/plugin/visual parity remains incomplete. Final artifact identity and signature/image verification are provided in the separate release verification asset.

## 0.4.0 validation — 4 November 2026

The stable-snapshot run completed **all 30 test executions successfully** (exit 0). Evidence: [0.4-final-test-run.log](analysis/0.4-final-test-run.log). This includes the existing filesystem, editor, transfers, synchronization, archive, FTP, provider, keyboard and menu suites, plus the new configuration and view coverage. Counts are assertions within their respective suites, not independent application features.

New or expanded results include:

- Configuration model: 46 assertions; real AppKit configuration dialog: 29; configuration/UI integration smoke also passed.
- Archive formats: 44 assertions covering bounded reading/extraction/integrity for ZIP/ZIP64, supported password ZIP, 7z, TAR/compressed TAR, GZIP, BZIP2, XZ and actual RAR fixtures. These do not establish arbitrary format/encryption variants or non-ZIP writing.
- Pane views: 30 assertions; thumbnails: 16; Quick Search: 11; panel filtering/selection: 13.
- Original resource menus: 28 assertions, 100 original items and 66 supported command IDs. Unsupported entries remain disabled; a visible menu item is not a completed feature.
- Split/combine: 36 assertions in the stable snapshot. A subsequent filename-classification fix and regression test passed **37 assertions**, preventing `file1.aa` / `file1.ab` from being mistaken for a numeric part sequence. See [FileParts supplement](analysis/0.4-fileparts-supplement.md).
- After that follow-up, full latest-source compilation succeeded; `ui-latest --smoke-test` exited 0 and reported both configuration UI integration and UI smoke passing.

### Visible mounted-DMG checks

The release operator tested these interactions in the mounted 0.4 build:

- Fixed MB displayed a 1.5 MiB fixture as `1,5 MB`; fixed GB displayed a 3 GiB fixture as `3 GB` under the host locale.
- The GB setting persisted through quit and relaunch.
- Dynamic `x.x k/M/G/T` displayed the fixtures as `1,5 M` and `3 G`; headings/footer updated with the configured display.
- Control+Shift+F1 showed an actual thumbnail grid, confirmed by screenshot.
- Control+F8 showed the directory tree with real root folders.
- Control+Shift+F8 cycled one, two and zero separate trees, confirmed through accessibility inspection.
- A 7z fixture opened in the main pane; F3 displayed its archived `readme.txt` with the exact fixture text.
- Panels were restored to the home directory and automatic size units after testing.
- A release smoke exposed an unintended preference write from a non-persistent test controller. Configuration saves are now gated by persistence mode, with a regression checking stored configuration and window state remain unchanged.

These observations verify the named paths and settings. They do not prove all 52 settings, all original options, exact visual parity or every supported workflow. Earlier 0.3 FTP/editing visible checks below remain historical evidence, not a fresh visible 0.4 production FTP test; the 0.4 automated localhost/provider suites passed separately.

The final optimized ARM64 build compiled successfully and its bundled UI/configuration smoke passed, including preference preservation. Ad-hoc signature verification passed. Final DMG integrity and mount/launch results are recorded alongside SHA256SUMS.txt; ad-hoc signing is not Developer ID notarization.

## Historical validation — 3 November 2026

Reference: Total Commander 11.58.1 x64. Host: Apple M2, macOS. Native app: ARM64 Mach-O, Swift/AppKit. No Wine/Windows runtime in the native bundle.

## Automated checks

- 34 filesystem assertions passed: disposable fixtures, traversal/self-copy/collision and ordinary operations. Trash was not exercised.
- Editor tests passed: UTF-8, binary rejection, file-size boundaries, concurrent-change detection, permissions, read-only mode and symlinks.
- UI smoke tests passed: listing, panel switching, navigation, marking, hidden files, panel swap, tabs, back/forward history, sorting, F2 refresh and menu wiring.
- 18 native operation assertions passed: SHA-256 known vector, wildcard/hidden/symlink search, chunk-boundary text search, cancellation, rename commit/collision/traversal/swap, same-metadata unequal-content comparison, ZIP listing/traversal rejection, real bundled 7zz pack/extract, no-overwrite and symlink packing rejection.

- Lister core: 25 assertions passed (UTF-8/UTF-16LE/UTF-16BE/Latin-1, binary detection, 64 KiB page boundaries, 2 GiB sparse-file final page, symlink/cycle handling, held-inode reads after pathname replacement, bounded text/image input, PNG thumbnail and FIFO rejection).
- Added regression tests for URL-stable selection after sorting and unchanged history after failed navigation.

## Visible interface checks

Disposable root: `/private/tmp/tc-native-ui-test`.

- Navigated both native panels to real Mac folders.
- F5 opened copy confirmation; confirmed copy appeared in destination; bytes matched.
- Option+F7 opened search; `*.txt` returned both fixtures; double-click navigated and selected the matching file.
- Control+M opened rename; literal replacement preview matched expected name; confirmation renamed fixture; bytes unchanged.
- Option+F5 created ZIP through bundled native 7zz.
- Option+F9 extracted ZIP to a new folder; extracted bytes matched original.
- Path text contrast issue found in first visible build; fixed by removing the native bezel and enabling explicit background drawing.

- Final native app launched from the read-only DMG; strict ad-hoc signature verification passed.
- Mounted-build F3 automatically selected hex for a binary fixture; Next page showed offset 65536, page 2/2; Escape closed Lister.
- Both panels restored to the real Mac home directory; path contrast visibly verified.
- Quit succeeded and the DMG unmounted cleanly.

## Historical 0.1 scope

Tests above establish these specific behaviors, not Total Commander feature parity. FTP, Windows plugins, synchronization, all advanced dialogs, shell integration, multimedia Lister, ZIP64/encrypted archive behavior and all original commands are not validated or implemented. The abandoned Wine wrapper's results do not count as native validation.

## 0.2 continuation validation

New automated suites: rename masks 66 checks; transfer engine 35 assertions; synchronization 33 assertions; archive browser 27 assertions; FTP 30 checks using localhost FTP/TLS fixtures. Checksum suite verifies four known digest vectors, four generated-manifest round trips, mismatch detection, path traversal rejection, FIFO rejection, and SFV comment-name rejection. The complete suite is rerun on integrated sources before packaging.

Expanded UI smoke: original Ctrl+F1/F2 view toggles, Ctrl+F4/F5 sort mappings, filter clear, Ctrl+Tab/Shift+Tab, background tab creation, close-all-tabs and letter-to-command-line routing. F2/Ctrl+R now refresh the source pane.

Visible continuation fixtures: /private/tmp/tc-parity-ui. F5 queued copy with Ask → Keep both preserved old collision.txt and wrote exact new bytes to collision (2).txt. Ctrl+M preview [N1-5]-[C] with three digits produced photo-001.txt and confirmed rename preserved bytes. Synchronization compared four differences, reviewed directions, applied four actions, and preserved the replaced original in .tc-sync-original-*. All expected copies and the recovery-file bytes were checked outside the UI.

A visible layout issue (initial divider positioned unevenly) was corrected by centering the divider at first display. Final mounted-build inspection remains recorded below after packaging.

Final mounted 0.2 checks: app launched from read-only DMG; equal initial pane widths and native home paths visibly inspected. Ctrl+F opened FTP; localhost listing and download completed, with downloaded bytes equal to fixture. Enter opened ZIP virtual folders; integrity check passed; nested F3 viewer displayed expected text; selected extraction preserved nested/member.txt and exact bytes. Both panes restored to /Users/cristi. Quit and disk unmount succeeded; strict bundle signature verification passed. No personal files were mutated by these checks.


## 0.3 main-pane continuation

Visible disposable fixtures: `/private/tmp/tc-pane-visible`, `/private/tmp/tc-ftp-visible`; FTP bound only to 127.0.0.1 on a dynamically allocated port.

- Enter on a ZIP opened its root and nested folder in the main pane. F4 opened a member, Save/Update ZIP completed, and Python ZIP extraction verified the changed bytes in the original ZIP.
- Ctrl+F connected to the local FTP fixture and populated the main pane. F5 downloaded the selected server file to the opposite local pane; the destination row appeared and bytes matched.
- F4 on the remote main-pane file opened the native editor. Save/Upload completed and reported verified success; server filesystem bytes matched the edited text. A stale main-pane size/date refresh bug was found and corrected afterward; its final UI recheck remains pending.
- Ctrl+F1 displayed real horizontally arranged Brief columns. Ctrl+Q displayed the selected text in the opposite pane; moving selection updated the preview, and a second Ctrl+Q restored the underlying pane.

These observations precede final integration of original menus, archive write-back and the latest shortcut fixes. Final integrated test and mounted-artifact results are recorded separately below when completed.


## Integrated 0.3 release checks

The frozen-source full suite passed on 3 November 2026. Counts: filesystem34, operations18, Lister25, rename66, local transfer35, synchronization33, archive browser27, FTP44, pane locations28, archive mutations35, archive editing18, remote editing20, provider transfers27, Brief layout21, shortcut contract349, file-list comparison8, original menu parser28, archive writeback26. Editor, checksum, native UI smoke and live localhost main-pane integration suites also passed. The original keyboard resource is supplied to the shortcut tests. The tests exercise stale destinations, changed originals, failed remote commits, source retention, cancellation, malformed paths and provider navigation races; these are scoped fixture results, not exhaustive equivalence.

Packaged app checks:

- ARM64 Mach-O executable; strict ad-hoc bundle signature verification passed.
- Bundle-aware smoke passed: original top-level menu ordering, unsupported command disabling and selection/busy-dependent enabled-state updates.
- Read-only DMG mounted and launched successfully. Full-view icons and original Files menu structure were inspected.
- Ctrl+Up opened a selected ZIP in a new tab. Enter opened the nested ZIP with its logical original path displayed. F4/Save/Update propagated the edit into the outer ZIP; independent extraction verified exact member bytes.
- Ctrl+F opened the compact connection dialog and populated the main pane from the localhost FTP server. Enter opened an FTP-hosted ZIP; F4/Save/Update changed the real remote ZIP. Independent extraction verified edited bytes, and the retained remote original contained the pre-edit bytes.
- F4 plain remote editing refreshed the main pane to the new26-byte size and modification time after verified upload, confirming the earlier metadata refresh bug is fixed.
- F5 from FTP to the opposite local pane completed through the final provider service; both displayed sizes and independent byte comparison matched.
- Both displayed panes restored to the real Mac home directory. App quit, DMG unmounted and disposable local server stopped.

The final packaging step updates reports and signatures only; the executable is unchanged from the mounted build tested above. Full Total Commander feature/interface equivalence is not achieved; see analysis/remaining-parity-gaps.md and analysis/current-parity.md.
