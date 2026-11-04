# Configuration rendering performance

Measured on the local Apple M2/macOS host, 4 November 2026, Swift 5 language mode with `-O`. Baseline source is commit `d45898d`; timings are a local microbenchmark, not a Windows comparison or a promise of a specific frame rate. Other agent compilation was active, so use the repeated measurements and expect scheduling variation.

## Root causes and changes

- Each size cell constructed/configured a NumberFormatter; each date cell constructed/configured a DateFormatter and rewrote the date pattern. The new cache is confined to the calling thread, bounded to 32 number and 32 date formatter instances per thread. Complete locale/time-zone/precision/date-option keys prevent stale formats when settings change.
- Revisiting a configuration category destroyed and rebuilt its controls/constraints. Categories now retain their controls lazily for the lifetime of the dialog. Unsaved edits survive navigation; Restore Defaults discards all cached pages.
- Apply performed an unconditional directory refresh after `applyConfiguration`, which already handles a hidden-files change. Removed this redundant refresh; a visual-only preference change does not request fresh directory I/O from the configuration dialog.

## Measurements

Each value below is milliseconds. Three fresh-process repeats were taken for each binary. Formatter checksum was identical (`282069`) in every baseline and updated run.

| Workload | Baseline runs | Updated runs | Median before → after |
| --- | --- | --- | --- |
| Format 10,000 sizes | 208.61, 224.32, 194.59 | 15.08, 13.03, 10.64 | 208.61 → 13.03 |
| Format 10,000 dates | 976.12, 1020.00, 969.02 | 24.63, 19.63, 18.71 | 976.12 → 19.63 |
| 80 category transitions plus layout | 2302.28, 1988.46, 5010.62 | 721.79, 540.26, 413.66 | 2302.28 → 540.26 |
| First open plus layout | 109.05, 97.19, 99.22 | 265.12, 100.25, 78.89 | 99.22 → 100.25 |

First-open latency is not improved by category reuse; repeated navigation is. Initial preliminary runs (before the repeats) were 170.42 → 12.82 ms for sizes, 811.07 → 24.77 ms for dates, and 1356.37 → 521.74 ms for category transitions, consistent with improvement despite variable CPU load.

Reproduce from the repository root:

```sh
xcrun swiftc -swift-version 5 -O -framework AppKit Sources/ConfigurationModel.swift Tests/ConfigurationFormatBenchmark.swift -o /tmp/tc-format-benchmark
/tmp/tc-format-benchmark
xcrun swiftc -swift-version 5 -O -framework AppKit Sources/ConfigurationModel.swift Sources/Preferences.swift Tests/ConfigurationWindowBenchmark.swift -o /tmp/tc-settings-benchmark
/tmp/tc-settings-benchmark
```

The window benchmark uses a nonpersistent stub controller and creates/layouts real AppKit configuration controls. It does not measure real directory scanning or rendering after Apply. The formatter benchmark formats 10,000 varying values with an explicit locale/time zone; it does not simulate every file list.

## Regression validation

- Existing configuration model: 46 assertions passed.
- Actual configuration controls: 33 assertions passed, including reuse without lost edits, Restore Defaults invalidation, no unconditional refresh, Apply and Cancel.
- Formatter isolation: 1,001 assertions passed across concurrent threads, alternating locale/precision/time zone/date options, exact Int64 bytes, and cache eviction.
