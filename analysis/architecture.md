# Native macOS implementation architecture

Inspected 2026-11-03. This report covers local source and prior build evidence, not native decompilation findings. Native recovery is a separate lane. No original implementation or build scripts were changed by this review.

## Recommendation

Use a native AppKit application with a deliberate Total Commander command model, backed by platform-neutral operation services. Reuse the existing Swift local-file and editor code where its contracts fit. Rebuild the presentation and keyboard routing against the original Total Commander menu, keyboard and resource inventory. Maintain a machine-readable feature matrix with implemented, tested, partial and missing states.

This is a native reimplementation informed by recovered behavior. It cannot be described as the complete original application merely because it looks similar. Decompiled pseudocode is analysis material, not a recovered Swift source tree. Windows calls and plugin interfaces need explicit replacements.

## Available native starting point

`outputs/ClassicCommander/Sources` contains 909 lines: Main.swift (554), FileService.swift (128), Editor.swift (227). Its build script compiles an arm64 AppKit executable with a macOS 13 deployment target. Existing source implements dual local panes, navigation, marks, view/edit, copy/move, mkdir, rename and Trash. FileService rejects conflicting targets and self/descendant transfers, checks broken symlinks with lstat, and reports partial failure. Editor bounds text reads, detects external modification, and guards unsaved close. Preserve those safeguards and tests.

The old UI is intentionally Norton-like: navy background, cyan selection, monospaced text. Main.swift line 310 currently maps F2 to places and F10 to quit. Those mappings must change: Total Commander F2 refreshes, F9 activates source menu and F10 activates the menu bar. Retaining the old dispatch would break the user's explicit shortcut requirement even after a theme change.

The local-only FileEntry and Pane models do not represent archive members or FTP paths. Do not fabricate file URLs for those entries.

## Separate implementation layers

1. Command catalog: stable command ID, original label, key/modifiers, prerequisites and handler. Use the same dispatcher from the in-window menu row, macOS menu, toolbar, F-key strip and keyboard events. Commands without implementations must be visibly unavailable, not empty handlers.
2. Pane state: location, tabs, history, sort, filters, marks and focused stable entry ID. Parent row remains outside sorting/filtering. Preserve state per tab. Changes to active pane must not alter an operation already submitted.
3. Location providers: local(URL), archive(container/member path), remote(connection/path). Each provider advertises list/read/write/mkdir/rename/remove capabilities. An archive viewer is not writable archive support.
4. Operation coordinator: immutable inputs, serialized mutations, progress/cancellation, collision decisions, completed/failed results and main-thread UI updates. Revalidate before commit; never silently overwrite.
5. Feature services: search, rename preview/apply, compare/sync plan/apply, archive index/extract/create, transfer queues, FTP sessions, viewer/editor and checksums.
6. Persistent configuration: saved panel/tab state, preferences and custom mappings under Application Support. Respect real macOS roots, volumes and permissions. No drive-letter fiction or Wine prefix belongs in this native build.

## Visible interface contract

Use light gray window chrome/toolbars, white lists, black unmarked names, red marked names and a blue active path/selection. Layout includes menu row, icon toolbar, drive/volume buttons, tabs, path bars, Name/Ext/Size/Date/Attr columns, pane status bars, command input and F3–F8/Exit footer. Match spacing, row height and selection behavior from actual reference captures rather than equating macOS system defaults with Total Commander's appearance. Use a split view for adjustable pane sizes.

AppKit can draw this arrangement while still exposing real accessibility controls. Use a dedicated custom table header if necessary for fidelity. Native system dialogs will differ visually unless recreated; declare that in parity coverage rather than assuming identical presentation.

Option should carry original Alt shortcuts; Control should remain Control. Command shortcuts can be additive but must not replace original bindings. Function-key events need `.function` normalized away, while Control/Option/Shift remain significant. macOS can intercept reserved shortcuts; test actual event delivery. Backspace/forward Delete/Insert and numpad selection operations need explicit Mac-key equivalents documented without mislabeling them as exact hardware parity.

## Feature work order

A first buildable increment can meaningfully implement the complete local navigation/selection/transfer loop, correct command routing, table sorting, tabs, history, search, rename previews and a text/hex viewer. It is still partial feature coverage.

Then implement archive and remote providers, operation queues and conflict policies; directory synchronization and multi-rename semantics; broad configuration and command-bar customization; plugin API replacement and specialized Windows feature adaptations. Each increment should use fixture-driven tests and actual menu/keyboard UI verification. Do not mark advanced features done because their dialog or menu entry exists.

Copying arbitrary Mac package directories must preserve their structure. Extended attributes, permissions, symbolic links, case sensitivity and file replacement semantics need explicit tests. Directory trees must avoid symlink cycles. Search scans need cancellation and incomplete-result reporting. Synchronization must not delete anything due to incomplete scans. Archive extraction needs traversal/link/duplicate rejection and expanded-byte limits. Remote credentials must not appear in process arguments or plain settings files.

## Double Commander evidence and alternative

The source checkout at `work/total-commander/doublecmd` is a mature cross-platform native commander and already implements much broader file-manager features. Previous native toolchain/component work is reusable if a Double Commander derivative is intentionally selected.

The recorded release build failed in the optional MacCloud WFX plugin, not in a demonstrated main application link: dc-release-build.log lines 1709–1718 show Apple's linker rejecting a malformed Objective-C method list in uwfxoptionswindow.o. Upstream build.sh calls components, then all plugins, then the application; this failure stopped before the main application phase. Therefore do not report that Double Commander's main app itself was proven unbuildable. Direct application-only build could test that separately. Never use the upstream release script that alters XProtect.

Nevertheless, branding or theme patches to Double Commander would be an alternative application, not a decompilation-derived Total Commander port. Its dialogs, defaults and semantics differ. Using its GPL source also imposes corresponding source obligations. It is the faster route to a broad native feature baseline, but not a shortcut to truthful exact parity. The current user request specifically emphasizes reworking Total Commander; therefore a relabeled fork should not be substituted without clearly identifying that architecture.

## Windows plugin and platform boundary

A Windows x86_64 PE plugin cannot be loaded by an arm64 Mach-O process. Matching exported function names is insufficient: machine code, loader format, calling conventions, OS handles, UI callbacks and Windows APIs differ. Native-compatible plugins need source ports/recompilation or an explicitly separate compatibility process, which the user currently rejects for the application. A plugin loader checkbox does not establish compatibility.

Windows shell extensions, NTFS-specific attributes/streams, registry integration, drive/device drivers and Windows-specific network integrations require separate macOS equivalents or explicit unavailable states. Some have no exact macOS equivalent. Original behaviors should be documented from evidence before designing replacements.

## Build and delivery

Stage native app builds outside the cloud-synced Documents tree, compile with explicit target/frameworks, ad-hoc sign and verify in staging, then package a DMG with an Applications shortcut. Verify the DMG, mount read-only, launch the mounted app, copy it to a different path with spaces and relaunch. Ensure configuration remains writable outside the app and survives relocation. Ad-hoc signing is not notarization. Name the deliverable as a native reconstruction/development build until parity is actually established.

## Current evidence limits

This review did not run native tests, repair the Double Commander build or execute any newly implemented feature. Existing file/editor tests and old Classic app build artifacts establish a useful starting point; they do not validate the forthcoming reconstruction. The separate decompilation lane must report its recovered procedure coverage and gaps before any claim of full recovery.
