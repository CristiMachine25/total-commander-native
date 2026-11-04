# Total Commander Native — 0.4.0 development build

Native Swift/AppKit reconstruction for Apple Silicon and macOS 13 or later. It uses your Mac folders and mounted volumes directly, without Wine or a Windows runtime.

**This is not an exact or complete Total Commander port.** All original settings and features remain the requested goal, not an achieved result. REA exported 5,565 pseudocode files from 24,601 provider procedure candidates, with 2 explicit failures and 19,034 unresolved entries. These exports and original resource/help evidence inform an independent implementation; they are not a recovered buildable original source project.

Open the DMG, drag the app to Applications, and open it. This build is ad-hoc signed, not Developer ID notarized. Control remains Control and Option maps supported Alt shortcuts. macOS may intercept combinations, and some keyboards require Fn for function keys.

Implemented scopes include dual panes; Full, horizontal-column Brief, local directory-tree and thumbnail views; one or two separate local trees; tabs/history; selection/filtering; native bounded text/hex/image viewing and editing; queued copy/move with collision handling; copy-only synchronization; multi-rename; checksums; bounded text comparison; FTP/FTPS panes; and local split/combine with CRC verification.

Archive reading, extraction and integrity testing cover ZIP including ZIP64 and supported password ZIP, 7z, TAR, compressed TAR, GZIP, BZIP2, XZ and tested RAR fixtures. Format or encryption variants outside the tested subset can still fail explicitly. Mutation remains limited to supported ordinary ZIP: member add/delete/rename/edit/repack, including nested and FTP-origin writeback with recovery copies. Non-ZIP and password sessions are read-only. Split-file tools do not imply split-archive support.

Configuration now has 52 persistent typed settings across 13 functional categories, within a 24-category navigation list. It includes layout, fonts/colors/icons, columns, file and footer size units, tabs, operation, viewer/editor, thumbnails, history, Quick Search and display-only Ignore List filtering. Size display includes the ten original styles plus clearly labeled native fixed-MB/GB choices and 1000/1024 unit bases. Unsupported categories explain gaps rather than showing inert controls. Settings use native JSON-backed preferences; they do not import or emulate all of wincmd.ini.

FTP requires MLSD and lacks resume, SFTP and complete original connection options. Synchronization does not mirror deletions. Ignore rules hide entries; they do not recursively exclude items from copy/move/synchronization. Windows DLL plugins, full Lister formats, every shortcut and original configuration option, custom columns, branch view, exact dialogs and pixel-identical rendering remain incomplete. See [remaining gaps](analysis/remaining-parity-gaps.md), [coverage](analysis/native-coverage.md), and [configuration details](analysis/configuration-coverage.md).

Command input runs explicit POSIX shell commands with your user privileges or supported internal commands. It is not a Windows command interpreter.

## Build and test

Run `python3 build.py` with Xcode command-line tools, then `bash test.sh`. FTP fixture tests require Python with pyftpdlib and pyOpenSSL; choose it with `FTP_TEST_PYTHON=/path/to/python bash test.sh`. Test servers bind localhost and use disposable fixtures. Bundled 7-Zip is native ARM64. Preferences use `local.totalcommander.native`.

This is an independent reconstruction, not an official Ghisler release. Original resource and archive-tool notices are in [THIRD-PARTY.txt](THIRD-PARTY.txt). The release-specific integrated, mounted-DMG and visible validation ledger is [TEST-RESULTS.md](TEST-RESULTS.md); earlier build checks do not certify every 0.4.0 change.
