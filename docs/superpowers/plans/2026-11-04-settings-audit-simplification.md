# Settings audit and simplified shortcuts implementation plan

**Goal:** Deliver the approved action-first Keybindings page and source-backed missing native settings, with an option-level original settings audit.
**Architecture:** Keep typed configuration persistence and staged Preferences Apply/Cancel; add focused runtime policy modules. Audit CSVs distinguish documented behavior from observed native evidence. Preserve original menu/resource references and record unsupported Windows-only capabilities.
**Tech Stack:** Swift/AppKit, native JSON, original Total Commander 11.58.1 help and retained REA exports, shell/Python release tooling.

- [x] Shortcut worker: implement approved spec in KeybindingsEditor.swift, keep serializedBindings(), expose aliases inside Advanced; test recording, defaults/overrides, conflict replacement, multiple bindings and cancellation.
- [x] Display worker: enumerate all options in assigned original configuration help pages; trace native model, UI and runtime; implement source-backed missing display policy with focused tests.
- [x] Operations worker: enumerate remaining original configuration pages including subdialogs; trace model, UI and runtime; implement source-backed missing operational policy with failure tests.
- [x] Root: integrate fields, tolerant persisted migration and strict versioned import; add UI and runtime hooks; verify old versions retain behavior.
- [x] Root: review both inventories for uncovered original pages and unsupported/unknown evidence. Do not equate original field count with implemented coverage.
- [x] Root: run frozen full test.sh plus optimized --smoke-test; visibly verify actual new controls in a mounted read-only DMG using disposable fixtures and restore saved preferences.
- [x] Root: granular commits, package.py, final signature/image/hash/source checks, publish updated development DMG and test ledger.

User approved action-first layout and autonomous multi-agent implementation. Existing settings must survive; no original-equivalence claim without runtime evidence. Missing semantics remain explicitly identified, not hidden behind inert controls.
