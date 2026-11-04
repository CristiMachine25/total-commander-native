# Display Settings Implementation Plan

**Goal:** Implement custom columns, named view modes and ordered automatic switching in the existing native file manager, then test and package version 0.8.0.

**Architecture:** Codable definitions are stored in the native configuration. Column evaluation is data-only. View modes apply pane-local presentation overrides after successful listings; auto rules inspect the current location and listing without additional I/O. Draft editors validate references before applying changes.

**Tech Stack:** Swift, AppKit, native backend and provider fixtures.

- [x] Custom columns worker: expressions, saved sets, column rendering and sorting, focused tests.
- [x] View modes worker: named modes, deterministic rules, baseline restoration, navigation hooks, focused tests.
- [x] Configuration UI worker: list/subeditors with add, copy, remove, ordering, Apply/Cancel and cross-reference validation.
- [x] Root: configuration schema v3 with v1/v2 migration; manual menus and shortcuts; dependency integration.
- [x] Full backend suite, actual controller integration tests and optimized application smoke.
- [x] Visible mounted fixture verified automatic column/sort application. Further interactive checks and restoration were paused when the user opened Configuration; controller regressions cover navigation/restoration.
- [x] Document exact supported options and remaining original differences; granular commits; package and verify DMG/source, publish release.

Original option reference: local original help pages under work/total-commander/help-extracted. Existing user authorization covers this continuation, tests and release; no additional design approval is needed.
