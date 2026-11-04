# Per-pane mounted drive bars

Approved design: a horizontal drive-button bar above each pane, visible by default, showing actual macOS volume names/icons. Each button opens its volume only in its own pane. Mounted USB/external/network volumes update automatically; hidden APFS implementation volumes are excluded. Horizontal scrolling handles narrow panes. Existing drive combobox remains independently configurable.

1. Add DriveBar.swift: mounted inventory, component-aware active volume matching, notification ownership and scrolling buttons. Test matching, deduplication, update notifications and observer cleanup.
2. Integrate Main.swift: place bar above existing drive row, reuse local/tree routing, synchronize selection after navigation, refresh popup without navigation.
3. Add showDriveButtons with backwards-compatible native configuration migration, Layout control and INI import; test round-trip and old versions.
4. Build optimized app, exercise both panes and real disk-image mount/unmount events, preserve user settings. Run regression suite and packaged smoke check.
5. Update release evidence, commit granular changes and package updated DMG. State physical USB test boundary honestly.
