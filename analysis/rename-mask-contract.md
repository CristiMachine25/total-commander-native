# Native multi-rename mask contract

## Evidence

The implementation follows the **shipped Total Commander 11.58.1 English help**, extracted read-only with the bundled 7zz from `work/total-commander/original/e/TOTALCMD.CHM` (SHA-256 `ac88512d1e474f49993c90f2f21f1f296e696fce1fabb0623e566ef2a0d82087`). This is behavioral specification evidence, not an algorithm recovered from pseudocode.

- `work/total-commander/help-extracted/dialog_box___multi_rename_tool.htm`, SHA-256 `6f73d7229c2c1503d4ee47f07429ba84b35347d5b6c2f984ffd6f5180d8bb0b1`.
- `work/total-commander/help-extracted/reg_ex.htm`, SHA-256 `f249cd6e321ef64e3f335d9c69519607bc92f39af07d6b80d1c3662fadbebf93`.
- Original application download: https://www.ghisler.com/download.htm
- Official feature overview: https://www.ghisler.com/screenshots/en/06.html

## Callable API

`RenameMaskEngine.render(input:index:total:options:)` returns one name with no filesystem access. `RenameMaskEngine.preview(sources:options:)` reads metadata, validates the complete plan and returns `[RenameMaskPreview]` with `source` and `destination`. It never renames files. Preserve caller order for counters. Parent integration should map entries to the existing `RenameItem` and use `NativeOperations.applyRename`, which revalidates before commit.

`RenameMaskOptions` has separate `nameMask` / `extensionMask`, counter start / step / optional digits (`nil` means automatic), search / replacement / regex / case-sensitive / first-only / include-extension / substitute-entire-name controls, final case conversion, opened/changed timestamps, locale and time zone. `CaseConversion.allCases` can populate a picker.

## Implemented behavior

- `[N]`, `[E]`, `[A]`, `[P]`, `[G]`; one-based indices, inclusive ranges, comma lengths, negative/end-relative ranges, open-ended ranges, zero/space left padding. Examples in the shipped help are table-tested.
- `[I]` toggles directory-extension handling and persists between the name/extension masks. `[S]` inserts metadata size.
- `[C]`, numeric inline counter parameters, grouped increments, auto-width and `[c]` / `[c1]` / `[c2]` / `[c3]`. Inline parameters reset the external counter settings. Integer arithmetic detects overflow.
- Modification/opened/changed date selection through `[T1]`, `[T2]`, `[T3]`; combined or single `Y y M D h H i m s v d t` tokens; `[i1]`. Date/time values use the chosen time zone. Locale date/time separators are filename-safe.
- Stateful `[U]`, `[L]`, `[F]`, `[n]`, leading `[u]`; bracket escapes `[[]` and `[]]`.
- Masks run first, replacement second, whole-name case conversion last. Regex captures `$0`–`$n` and replacement `\U`, `\L`, `\F` work. Plain search defaults to case insensitive. Extension exclusion protects the separate extension-mask result.
- Preview rejects disappeared sources, duplicate sources/results, existing unrelated targets, nested parent/child renames, path traversal, invalid/oversized names and unsupported placeholders. Existing source cycles are allowed for the existing transactional apply layer.

## Explicit limitations and native choices

This is a **subset**, not complete TC mask parity. Unsupported placeholders throw errors: content plugins, environment/clipboard fields, `[B...]`, full-path slices, EXIF `[T4]`, time offsets, alphabetic counters and English-title `[f]`. Subfolder moves via backslash are rejected. Plain-mode wildcard or multiple-pair searches (`*`, `?`, `|`) are rejected instead of being silently treated with different semantics.

Regex uses Foundation/ICU rather than TC's TRegExpr. Shared syntax and documented capture examples are tested, but engine-wide parity is not claimed; unsupported expressions throw Foundation parser errors. Unicode slicing uses Swift extended grapheme clusters, preserving emoji/combining sequences. macOS leading-dot names stay intact. Name limit is conservatively 255 UTF-8 bytes, mask/text bounds 4,096 characters, counter width 1–32. Automatic width covers first/last counter values; negative sign consumes width. These native choices are explicit and not binary-observed TC edge cases.

No live original-app differential testing of these edge cases has been performed. The tests verify this declared contract and exact examples from shipped help.

## Validation

Compile and run:

```
xcrun swiftc -swift-version 5 Sources/RenameMasks.swift Tests/RenameMasksTests.swift -o /private/tmp/tc-rename-mask-tests
/private/tmp/tc-rename-mask-tests
```

65 checks pass, including documented substring examples, Unicode boundaries, counters/overflow, date switches, regex group transforms, invalid tokens and filesystem preview collision/non-mutation checks. No other source files were changed by this lane.

Native filename handling preserves a terminal dot as part of the basename (for example `report.`), so the default masks round-trip valid macOS names. Regression tested.
