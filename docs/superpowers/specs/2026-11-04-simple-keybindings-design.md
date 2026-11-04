# Simplified Keybindings page — proposed design

Replace the command-oriented editor with a searchable Action / Shortcut list. Show readable action names (Copy files, Move files, Brief view) and the supported default shortcuts, rather than an initially empty override table. Keep stored overrides and command identifiers unchanged.

Selecting an action exposes one Record shortcut button and a Restore default action. Capture previews the change; the existing settings Apply/OK saves it and Cancel discards it. Conflicts name the affected action and require explicit replacement. Escape cancels recording. Preserve multiple bindings per action rather than silently collapsing existing custom settings.

Move command IDs, manual chord entry and command-line aliases into a collapsed Advanced area. Keep unsupported/OS-reserved shortcut explanations in a short help note. Avoid a separate command-search field, five competing action buttons, and long instructional paragraphs in the main flow.

Default shortcut labels must come from the actual native command/shortcut contracts. Show only mappings verified for the relevant pane context; do not invent defaults from command names. Existing parser validation, text-field focus isolation, busy/loading guards and persistence semantics remain unchanged.

Validation: existing shortcut/editor tests plus readable-label mapping, search, default/custom differentiation, multiple-binding preservation, conflict replacement, recording cancellation, staged Apply/Cancel, and actual file-pane dispatch. Check the visible page with disposable data and preserve user settings.

Alternative considered: only shorten the existing labels and hide aliases. This is smaller but leaves the empty-table and command-ID learning burden. Recommended: action-first list above.

Status: user approved. Implemented in 0.10.0; see analysis/keybindings.md and test ledger.
