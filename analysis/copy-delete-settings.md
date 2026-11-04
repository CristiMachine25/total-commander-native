# Copy/Delete and confirmation settings

Reference: original extracted `dlg_configcopydelete.htm` and `dlg_configconfirmation.htm` describe directory timestamps, read-back verification, delete-to-recycle-bin, and confirmation controls. This native implementation uses macOS filesystem APIs; it does not claim Windows CopyFileEx, Explorer copy/delete, drive-letter grouping, or cache-bypass equivalence.

Implemented local-to-local transfer controls:

- Preserve dates of newly created destination directories. Existing merged directories retain their existing metadata policy.
- Preserve file date/stat metadata and source permissions/ACLs; both default on, preserving the prior all-metadata copy path. With permission preservation off, regular files retain their private creation mode (0600) rather than source executable bits/ACLs. Extended attributes continue to be copied.
- Verify copied regular-file contents through bounded read-back of the private staged destination and source before commit. Verification is an exact byte comparison, not the original MD5/BLAKE3 algorithm; cache bypass is not promised. Failed/cancelled verification does not replace the old target or remove a move source. The queue dialog provides a per-job verification checkbox.
- Copy buffer size, clamped to 64–16384 KiB.
- Default collision action: ask, skip existing, replace, keep both. Overwrite confirmation forces replacement collisions to prompt; disabling it lets the ask default replace automatically. Existing directory merge and race-safe commit rules remain in effect.
- Optional initial copy/move destination and queue-policy confirmation; with it disabled, the other pane is the destination and configured defaults apply.

Local delete controls choose Trash or permanent deletion. Routine confirmation can be disabled for recoverable Trash only. Permanent deletion always confirms the actual selected files. Remote/archive deletions keep their existing explicit confirmation and provider semantics. Symbolic links are removed themselves, not their destinations.

These settings do not alter provider transfer collision refusal, archive extraction collision behavior, synchronization policies, remote timestamps/permissions, or Windows read-only/system attributes. Windows-specific methods are not exposed as working controls.

Validation on 4 November 2026: 46 transfer assertions passed (11 new covering metadata options, buffer bounds, verification success, staged-data corruption, cancellation and retained originals); 42 FileService checks passed (5 new permanent-delete tests including symbolic-link destination protection, missing-source preflight, nonempty directory removal and root refusal). Tests use disposable fixtures; Trash was not exercised by those backend tests. UI/runtime configuration and final packaged verification are recorded by the integration run separately.
