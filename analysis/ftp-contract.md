# Native FTP implementation contract

The native AppKit connection browser uses the macOS-supplied `/usr/bin/curl`, not Wine or Windows networking. Entry point: `FTPBrowserWindow(downloadDirectory: URL, onConnect: ((FTPClient, String) -> Void)?).display()`. Callback mode validates the connection and transfers it into the main pane, then closes the connection window.

Supported: saved connection profiles, anonymous or username/password sessions, passive FTP, explicit TLS (default), implicit TLS, MLSD directory browsing, binary download/upload, mkdir, rename, bounded recursive upload/download, confirmed permanent remote deletion, cancellation. Profiles contain host, port, username, security mode and initial path; passwords remain session-only. Local file choices use native panels.

Credential handling: curl receives only `--disable --config -` as process arguments. Quoted configuration, including credentials, goes over stdin. Ambient curl configuration is disabled; inherited proxy settings are cleared. Passwords are absent from environment, profile JSON, temporary configuration files and app logs. Curl errors redact the supplied password. TLS requires encryption and retains certificate/hostname verification; no insecure option is exposed. Profile files are saved with mode0600.

Directory listings require RFC3659 MLSD and UTF-8. Parse errors are reported; a heuristic legacy LIST parser is not used. Names containing control characters, separators or traversal components are rejected. Downloads go to a private temporary sibling, then move to the chosen new destination; existing local files are refused. Uploads check remote collisions first. FTP STOR has no portable exclusive-create primitive, so another client can race the check; an interrupted upload can leave a partial remote file. Rename likewise has a remote check/use race. No claim of transactional remote operations is made.

Not implemented: SFTP, proxies, legacy server encodings/LIST-only servers, transfer resume, connection pooling, synchronized directories or full Total Commander FTP parity. Successfully trusted real-world FTPS and implicit TLS transfers remain untested; tests verify mandatory encryption and rejection of an untrusted TLS certificate. The parent integrates the connection callback with main panes. Visible verification is tracked separately.

Primary protocol/tool references:
- https://www.rfc-editor.org/rfc/rfc3659.html (MLSD machine-readable facts)
- https://curl.se/docs/manpage.html (stdin config, FTP quote/upload, TLS certificate verification)

Validation: `Tests/FTPTests.swift` runs table checks and disposable localhost pyftpdlib servers. Requires a Python interpreter with pyftpdlib and pyOpenSSL as its argument; no user server/accounts are used. Fixture credentials are temporary test constants. Covers binary transfer, Unicode/spaces/percent filenames, listing, mkdir, rename, collision refusal, partial-download cleanup, cancellation, profile permissions, injection rejection, TLS downgrade refusal and self-signed certificate rejection.

Tree transfers inventory at most20,000 items and64 nested levels, reject reported symlinks/unknown types, and refuse an existing destination leaf. A directory download stages into a private sibling then moves into place. Upload failures can leave a partial remote tree. Delete inventories before mutation and removes children before directories; nonrecursive deletion refuses a nonempty directory. Root deletion is prohibited. A reported symbolic link is deleted as a link without traversal. Some servers report followed symlink targets as ordinary files/directories; MLSD cannot reliably identify such server-side links, and remote server changes after preflight cannot be excluded. These operations are bounded, not a transactional filesystem snapshot.

Review: host fields reject credentials/URL separators/control injection. User/password values are sent only in quoted stdin configuration. Raw credentials are not included in display URLs or service diagnostics. Recursive deletion never guesses unknown MLSD types. The UI caller must obtain explicit confirmation before permanent deletion.

Remote text editing uses a private local file (4MiB editor limit), compares original metadata and complete original bytes before replacement, then downloads and verifies uploaded content. FTP offers no atomic compare-and-swap: another writer can race the final comparison and STOR. Upload consent explicitly states this limitation. Failures preserve the local copy; close hooks prevent accidental discard of pending uploads. Unsupported text is rejected by the existing editor. Symlinks are rejected when identified by the server.

Validation:44 FTP checks pass against disposable localhost servers;20 remote-edit checks exercise injectable transport conflicts, cancellation, upload failure and verification. These are development tests, not a claim of full Total Commander parity.

Bounded downloads accept optional maxBytes, require known MLSD size within the bound, pass curl max-filesize, and check the actual temporary file size before committing. Remote editing applies a4MiB bound.
