# Local directory listing metadata

Measured on Apple M2/macOS, 4 November 2026, optimized Swift 5 build. `FileService.list` already asks `contentsOfDirectory` to prefetch directory metadata, but previously repeated `fileExists(isDirectory:)` for every item. Ordinary entries now use the prefetched `isDirectory`; symbolic links (and missing metadata) still resolve the target so links to folders remain navigable.

Benchmark uses two disposable directories containing 1,000 and 10,000 actual empty files. Each result is the mean of three complete `FileService.list` calls, including metadata, URL/name handling and sorting. Baseline and updated binaries ran alternately three times against the same fixtures; creation time is excluded. Output count checksums were 3,000 and 30,000 respectively in every run.

| Entries | Baseline runs (ms) | Updated runs (ms) | Median |
| --- | --- | --- | --- |
| 1,000 | 16.440, 16.511, 15.505 | 14.561, 14.722, 13.961 | 16.440 → 14.561 |
| 10,000 | 144.806, 143.332, 145.305 | 120.068, 124.916, 121.232 | 144.806 → 121.232 |

This reduces local listing work, but listing remains synchronous on ordinary navigation. The benchmark does not measure network volumes, Finder icon lookup, painting, cold filesystem caches or Total Commander on Windows. It is not evidence that all navigation now meets a frame-time budget.

Build the reproducible benchmark:

```sh
xcrun swiftc -swift-version 5 -O Sources/FileService.swift Tests/DirectoryListingBenchmark.swift -o /tmp/tc-directory-benchmark
/tmp/tc-directory-benchmark /path/to/fixture-root
```

The fixture root must have `1000/` and `10000/` subdirectories containing the corresponding number of files. The benchmark reads those fixtures without modifying them.

Regression coverage extends existing filesystem tests with ordinary file/directory classification, file symlinks and broken links; existing tests already verify directory symlinks and their preservation during copy.
