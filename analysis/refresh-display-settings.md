# Refresh and display settings

Implemented from the original extracted `dlg_configrefresh.htm` and date/color configuration scope:

- Refresh local panes after the application becomes active (enabled by default).
- Optional automatic refresh for visible local folders. Background work uses a two-second interval and never overlaps scans. With size/date updates disabled, unchanged directory mtime/ctime skips enumeration. Size/date updates require a nonrecursive listing of each visible local directory; large directories still cost work, so background refresh remains opt-in.
- Foreground-only operation, excluded local directory prefixes (semicolon-separated, component boundaries respected), and optional disk-capacity heading updates.
- Changes preserve all surviving selected rows, marked files and the Full-view scroll origin. Deleted marks are removed. Busy operations, loading panes, modal sheets, hidden windows and path/command-field editing defer refresh rather than replacing active interaction. Stale navigation/configuration results are discarded. Activation/timer observers use weak ownership and are disabled for nonpersistent fixture controllers.
- Alternate Full/Brief row background color with an enable control. Selection colors remain authoritative.
- Literal custom date/time separators and a 12-hour override. Formatters are cached per thread and keyed by every formatting option. Empty overrides retain the previous system-locale behavior; fixed date orders keep their previous 24-hour default. Literal ICU letters and apostrophes in separators do not become formatting patterns.

Validation on 4 November 2026:

- `Tests/DateSettingsTests.swift`: 9 assertions passed (ISO default, independent separators, 12-hour period, century/order, literal pattern characters, apostrophe, default locale behavior, system-order override and cache isolation).
- `Tests/RefreshSettingsTests.swift`: 30 assertions passed against a frozen full-source snapshot (visible local create/delete/size changes, both panes, selection/marks, disabled/activation behavior, busy deferral, path exclusions, disk heading option, and actual row colors/shared Brief policy, and independent scan baselines when one of two same-folder panes temporarily defers).

Limits: no FTP/archive automatic refresh, no recursive tree watching, no filesystem-event stream, no POSIX attribute-change-only detection, no append-new-files-at-end policy, no independent footer-update suppression, and no drive-letter exclusions. The new path-prefix control is the native equivalent for local folders. A two-second polling interval is not the original one-second event-watch mechanism. Current tests prove direct controller scans; visible packaged timer/activation testing is recorded separately by the release operator.
