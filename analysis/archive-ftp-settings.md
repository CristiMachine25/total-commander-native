# Archive and FTP configuration behavior

Source reference: locally extracted original `dlg_configpack.htm`, `dlg_internalzipconfig.htm`, and `dlg_configftp.htm`.

## ZIP/Packer

- Compression is passed to the bundled 7-Zip ZIP writer as levels 0–9. Level 0 stores; higher levels use deflate. New default 6 follows the original documented normal setting (the previous native fixed level was 5).
- Verify after packing runs a full `7zz t` integrity check before publishing the new archive. Turning it off skips this extra check; basic archive listing/metadata validation remains. A failed check keeps the requested destination absent and cleans the temporary archive.
- Set archive date to newest file computes the maximum modification time of selected regular files including nested regular files, then applies it to the newly created archive. Empty-folder-only archives retain creation time.
- Treat archives like directories controls normal Open/Return/double-click for local archives. When disabled the system association opens the file; if no association opens it, internal browsing is the fallback. FTP/nested archives still use internal browsing because their entries are not ordinary local paths.

These packing settings apply to new archives created by Pack Files. Existing archive edit/writeback uses its existing mutation implementation; its compression policy is not controlled by this new page. Windows external packer interfaces, damaged/partial ZIP recovery, Unicode code-page variants, encryption, split archives and alternate creation formats remain outside this implementation.

## FTP

- Passive mode, connection timeout (1–300 seconds) and operation timeout (1–86,400 seconds) are captured into new FTP clients. Existing connections retain their snapshot. Active mode uses curl's interface-selected local address (`ftp-port = "-"`), not user-supplied public port ranges.
- Listing timeout is the lesser of the configured operation timeout and the existing 120-second listing cap. Upload/download operations use the configured operation timeout. Timeouts apply to each curl invocation, not the entire recursive tree operation.
- New connections can open in the active, left, right or inactive pane. The chosen pane is captured when the connect dialog opens.
- TLS certificate verification, protocol restrictions, credential handling, MLSD requirements and binary transfer behavior remain unchanged.

Retry/resume, ASCII/automatic text conversion, proxy profiles, MODE Z, public PORT address/ranges, global credential logging and connection pooling are not implemented by these defaults.

Validation: [archive and FTP tests](0.7-archive-ftp-tests.log).
