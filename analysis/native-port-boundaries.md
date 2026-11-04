# Recovered native routines and macOS port boundaries

Inspected 2026-11-03 from already exported REA pseudocode. This pass did not open or mutate the active REA session, execute the routines, or modify application implementation.

## Evidence identity and limits

The export identifies Total Commander 11.58.1 `TOTALCMD64.EXE`, SHA-256 `570f455917d991d32329005e259653fb4817716f137297ed82389ec920352f99`. The provider is Hopper, analysis profile `781d139fd1f69dd0455a11fb80bf44950646ddfb455022e1610f594579784075`. REA overview evidence `ev_d5664383fde89d85cfb2e4add192696e5a3eb1ef191e822fa59a147587f062bf` establishes the provider inventory; the per-function export journal establishes the files examined here.

All ten examined files listed below were checked against their SHA-256 records in `work/total-commander/decompiled/decompile-journal.jsonl`; all matched. The index can lag the journal while a batch is still running. Source pointers below refer to the pseudocode export, not original Pascal source.

Each file explicitly says that complete function body ranges are unavailable and results depend on Hopper's static analysis. Register variables, unknown `decomp_var_*` arguments, anonymous globals and repeated branches remain unresolved. Observed means present in the provider output, not independently validated machine-code behavior or runtime execution. No original names, types or complete project have been recovered by this pass. None of these findings establishes that the current native app is a full port of the recovered program.

## 1. Directory-enumeration capability lookup — 0x4c4610

Source: [0x4c4610.c](/Users/cristi/Documents/Codex/2026-10-30/using/work/total-commander/decompiled/functions/0x4c4610.c:11), lines 11–30.

**Observed:** A byte guard prevents repeating an initialization block. When another global byte permits it, the routine obtains a `kernel32` module handle, temporarily changes the error mode, resolves the literal API name `FindFirstFileExW` with `GetProcAddress`, stores the result in `qword_bda620`, then returns whether that pointer is nonzero. When the global gate is false it explicitly stores zero.

**Inference:** This is a cached availability probe for an extended Unicode directory-enumeration entry point. It is not itself the directory-listing routine. The use of the stored pointer by the full listing pipeline was not traced in this pass, so ordering, wildcard matching, retries, hidden/system handling and fallback behavior are unknown.

**Native boundary:** The macOS listing provider can use `FileManager` directory enumeration or POSIX `readdir`/`fstatat`, returning its own capability contract. There is no reason to reproduce a `kernel32` lookup. However, Windows enumeration semantics must be tested separately from the mechanism: name matching, reparse points, file IDs, error reporting and case behavior are not automatically equivalent.

**Required next validation:** Trace callers and the stored pointer's call sites; compare empty, inaccessible, Unicode, hidden, symbolic-link and rapidly changing directories against the original. The current native listing should not be declared equivalent solely because both APIs enumerate files.

## 2. File timestamp access — 0x4d20d0 and 0x4d22a0

Sources: [0x4d20d0.c](/Users/cristi/Documents/Codex/2026-10-30/using/work/total-commander/decompiled/functions/0x4d20d0.c:16), lines 16–32; [0x4d22a0.c](/Users/cristi/Documents/Codex/2026-10-30/using/work/total-commander/decompiled/functions/0x4d22a0.c:16), lines 16–32. Supporting helpers: `0x4d2280.c` and `0x4d2490.c`.

**Observed:** The read routine tests an unknown helper, copies/transforms the incoming path with another helper, opens it using `CreateFileW` with visible access value `0x80` and share value `0x3`, rejects the invalid-handle sentinel, passes the handle and three pointers to `GetFileTime`, converts its success result into a Boolean and calls `sub_4d2490`. The related write routine has the same shape with visible access value `0x100` and calls `sub_4d2280`; that helper directly calls `SetFileTime`. The close helper invokes `CloseHandle` and records either zero or `GetLastError` in global/thread-selected storage.

**Inference:** These are path-based wrappers for reading/writing three Windows timestamp fields with centralized handle/error handling. Microsoft documents `GetFileTime`'s fields as creation, last access and last modification; filesystem support and resolution can vary. [Microsoft GetFileTime documentation](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-getfiletime).

**Native boundary:** Use file-descriptor-based metadata reads or Foundation resource values. macOS stat metadata includes birth/access/modification times; access/modification writes can use POSIX timestamp APIs, while creation-time updates require an explicit supported macOS metadata route. Do not substitute status-change time for Windows creation time. [Apple Stat documentation](https://developer.apple.com/documentation/system/stat).

**Unresolved semantics:** Several `CreateFileW` arguments are unidentified. Whether directories, symlink targets, unavailable timestamps, preservation flags or special sentinel values are accepted is not established. The precheck and path helper require analysis. The native build's file-date display is not equivalent to complete timestamp-editing support.

## 3. Locale-dependent separator setup — 0x427730

Source: [0x427730.c](/Users/cristi/Documents/Codex/2026-10-30/using/work/total-commander/decompiled/functions/0x427730.c:11), lines 11–35.

**Observed:** A global selects `GetLocaleInfoW` versus `GetLocaleInfoA`, both with visible locale `0x400` and type `0x1e`. Failed calls take fallback branches through string-copy helpers. The ANSI result is converted through another helper. The first 16-bit value is saved; zero or character `0` is replaced with `:`. It then performs apparent byte conversion and round-trip validation. On mismatch the byte value becomes `:` and two additional globals are cleared.

**Inference:** This is a locale-dependent separator initializer, strongly consistent with time formatting because of the locale query and colon fallback. The conversion helpers' exact code-page behavior and the cleared globals' purpose were not established. It would be an overclaim to label it the whole date/time formatter.

**Native boundary:** Use a locale-aware formatter and Unicode strings rather than reproducing ANSI/Wide dual paths. If exact Total Commander formatting is required, derive an explicit formatter configuration from original behavior and saved preferences; AppKit's default locale rendering may differ. Preserve fallback behavior only after identifying which conditions are actually reachable in supported macOS locales.

**Required next validation:** Compare 12/24-hour locales, localized digits, separators outside ASCII, manual date preferences and formatting errors. Trace readers of the stored globals before assigning user-visible semantics.

## 4. Toolbar configuration path selection — 0x483e90

Source: [0x483e90.c](/Users/cristi/Documents/Codex/2026-10-30/using/work/total-commander/decompiled/functions/0x483e90.c:20), specifically lines 20–40 and subsequent visible configuration/path branches. The full export is 674 lines; this pass examined the path-selection segment and selected branches rather than validating every duplicated pseudocode branch.

**Observed:** The routine obtains a module filename with `GetModuleFileNameA`, searches for a backslash through a helper, selects literal `\vertical.bar` or `\default.bar` based on an argument, calls configuration/string helpers, and reads `[options] redirect` using `GetPrivateProfileIntA`. Later branches contain `%ProgramFiles%` and attempted file opening, showing that install-path/configuration handling is more than a fixed resource lookup.

**Inference:** This participates in resolving horizontal/vertical toolbar configuration files, including a redirection policy. It is not sufficient evidence for all button-bar loading, icon handling or customization semantics. Some branch predicates in the pseudocode appear redundant; they require validation rather than literal translation.

**Native boundary:** Keep bundled default button definitions in app resources, and writable customization in the user's Application Support directory. A native port may parse compatible `.bar` configuration, but must explicitly define how Windows commands, icon DLL references, environment expansion and path redirection translate. Writing mutable toolbar configuration inside a signed/read-only app would be a packaging error.

**Required next validation:** Recover the configuration helpers and test default/vertical bar selection, custom bar files, redirects, missing files, read-only installation paths and imported commands. The current toolbar UI is not proof of original `.bar` compatibility.

## 5. Windows directory links and reparse points — 0x4c63b0

Source: [0x4c63b0.c](/Users/cristi/Documents/Codex/2026-10-30/using/work/total-commander/decompiled/functions/0x4c63b0.c:15), notably lines 15–65 and repeated later branches. Supporting routines: `0x4c6050.c` and `0x4c61d0.c`.

**Observed:** The routine examines two path arguments, several platform/helper flags and a colon at the second character of one path. One branch invokes `qword_bda630` with third argument `1`; `0x4c6050` resolves `CreateSymbolicLinkW` into that exact global. The preceding `0x4c61d0` helper requests `SeCreateSymbolicLinkPrivilege` once through another helper. Other branches open a path, prepare a buffer whose first value is `0xa0000003`, call `DeviceIoControl` with control `0x900a4`, obtain errors and close the handle.

**Inference:** This contains directory-symbolic-link creation and a mount-point/junction reparse path, selected by platform/path conditions. The API constants match `FSCTL_SET_REPARSE_POINT` and `IO_REPARSE_TAG_MOUNT_POINT` in the Go project's Windows system-call definitions. [Go Windows reparse definitions](https://go.dev/src/internal/syscall/windows/reparse_windows.go). Exact helper predicates, buffer structure correctness and all path forms remain unverified.

**Native boundary:** POSIX symbolic links can cover many user intents, but a Windows junction/reparse record is not a POSIX symlink or a Finder alias. The native application must distinguish these concepts rather than silently representing all three as the same object. Directory links need explicit target semantics, relative/absolute path preservation and safe handling of broken links. Windows privilege activation has no direct one-to-one port.

**Required next validation:** Identify all caller commands, source/target order and relative-path branches. Test broken targets, cross-volume links, nested directory links, permissions and copy behavior. Do not claim arbitrary Windows reparse-point preservation on APFS.

## Implications for the current reconstruction

These five examples establish useful platform-rework questions from actual recovered pseudocode, beyond an import inventory. They do not establish complete source recovery, UI parity, or that the current Swift implementations were translated from these exact routines. The current app has independent native services. Future implementation can use this report as a contract-recovery checklist, pairing each proposed replacement with original-runtime tests and explicitly retaining unknowns until resolved.
