# Pane responsiveness — 4 November 2026

Observed source causes: selectedEntries reconstructed a URL set and scanned the entire listing for each selection/footer update, even when only one row was selected. Configuration Apply unconditionally refiltered/resorted the whole listing and recreated selection by URL, including appearance-only or unchanged settings. Table cells had no reuse identifiers, reallocated their child views/constraints, and requested system icons repeatedly. Fonts were reconstructed per cell.

Changes:

- Direct selected-row lookup when no explicit marks exist; preserve marks' precedence and listing order. Footer reads the resulting selection once.
- Refilter/resort only for relevant policy changes. Reapplying an identical configuration is a no-op. Presentation-only changes preserve the selected row indexes across AppKit reloadData.
- Register text/icon/row reuse identifiers. Reuse child views and constraints. Cache the configured font and up to 512 file icons per pane; invalidate icon cache on every listing refresh. Brief mode shares that cache.

## Measurements

Optimized Swift (`-O`) on this Apple Silicon host. The fixture contains synthetic FileEntry records, without filesystem listing or a visible window. Baseline is imported 0.4 source at d45898d; after includes pane changes plus the independent formatter-cache change. A discarded build invalidated by concurrent source edits was not measured; successful runs used immutable source snapshots.

| Operation | Entries | Before ms/op | After ms/op |
|---|---:|---:|---:|
| Single-selection footer, 100 iterations | 1,000 | 0.1140 | 0.0033 |
| Single-selection footer, 100 iterations | 10,000 | 0.8872 | 0.0042 |
| Repeated same size-format Apply, 10 iterations | 1,000 | 1.0213 | 0.0250 |
| Repeated same size-format Apply, 10 iterations | 10,000 | 8.1073 | 0.0026 |
| Direct offscreen name-cell factory, 1,000 iterations | 10,000 | 0.0294 | 0.0427 |

The same-format Apply benchmark mostly measures the unchanged-settings fast path, not toggling between distinct settings each iteration. The direct cell factory has no table-managed onscreen reuse pool and did not improve; these figures do not prove scrolling/frame-time gains. First-time system icon lookup and slow filesystem access can still block. No paired Windows benchmark was performed; this is not evidence of Windows speed parity.

Raw results: pane-performance-before.log and pane-performance-after.log. Reproducible benchmark: Tests/PanePerformanceBenchmark.swift, compiled with production sources and only Main.swift's application entry annotation removed in a disposable source copy.

## Regression validation

- PanePerformanceTests: 13 checks passed, including marks/cursor selection precedence, parent-row exclusion, configuration selection preservation, changing filter and sorting policies, restored listings, font/size rendering and reuse identifiers.
- Existing PaneViewTests: 30 checks passed, including actual thumbnail/tree/separate-tree modes.
- An initial regression caught AppKit clearing selection on presentation-only reload; restoring the existing IndexSet fixed it, and the final tests/benchmark include that correction.
