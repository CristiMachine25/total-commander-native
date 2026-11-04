# Tab, appearance and keybindings continuation

Goal: per-tab view settings, independent dark palette/system appearance, validated original display-profile INI import, and a dedicated keybinding editor. Preserve existing settings through native configuration version 4 migration.

- [x] Tab worker: indexed tab snapshots, activation, insertion/closure/swap, local persistence and tests.
- [x] Appearance worker: palette model, resolved rendering, normal/dark/system controls, mode-specific dark colors, tests.
- [x] Import worker: source-backed original INI profile parsing, linked atomic merge and invalid/unsupported reporting.
- [x] Root: schema/migration, Keybindings page and capture/conflicts, command integration, tests.
- [x] Full test suite and optimized build, visible disposable checks, settings restoration, verified DMG and granular release commits.

No Windows plugin/OS integration capability is claimed from a checkbox alone. These are continuations of the approved native implementation.
