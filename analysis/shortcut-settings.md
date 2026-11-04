# Native keyboard bindings and command aliases

Original reference: the keyboard remapping and Alias sections of `dlg_configconfirmation.htm`. This implements native command bindings, not Windows external em_ commands or all original key codes.

Configuration strings are semicolon-separated (newlines also accepted):

- Shortcuts: `Ctrl+Shift+C=cm_CopyFullNamesToClip;Option+F3=cm_List`
- Aliases: `ll=cm_SrcLong;new-folder=cm_MkDir`

Modifiers accept Ctrl/Control, Alt/Option/Opt, Shift, Cmd/Command/Super. Keys include letters, digits, F1–F20, Space, Return/Enter, Tab, Escape/Esc, Backspace, Delete/Del, Insert, Home, End, PageUp/PageDown and arrow names. Punctuation uses names such as Slash, Semicolon and Plus. Modifier order is irrelevant; duplicated or unknown modifiers/keys are rejected. Caps Lock and Fn flags do not change matching. macOS-reserved system shortcuts can still be intercepted by the operating system before the app receives them.

A typed explicit allowlist accepts only commands that this build can dispatch natively. Unknown commands, shell text and command parameters are rejected. Aliases match one entire trimmed command-line token, case-insensitively; they never replace a prefix or filenames. Aliases point directly to native commands, so recursive chains/cycles cannot run. Duplicate shortcuts and duplicate aliases (including alternate modifier spellings/case) produce actionable validation errors. Lists are bounded to 16 KiB each and parsed mappings are cached until configuration changes.

Configured key bindings run before default shortcuts, only when the main file list or directory tree has focus. Path/command text editors, modal sheets and other windows retain their normal editing keys. Busy/loading panes consume matched custom keys without starting another action. Existing context restrictions still apply to the dispatched command. Resetting a list to empty restores default bindings or removes aliases.

Focused validation: 26 parser assertions and 9 real NSEvent mapping assertions cover normalization, exact matching, duplicate/cycle/unsafe-command rejection, bounds, function/arrow/punctuation keys and modifier matching. Integrated controller action/focus tests are recorded in the configuration smoke ledger.
