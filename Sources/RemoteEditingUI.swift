import AppKit

private final class RemoteEditingCoordinator {
    let session: FTPRemoteEditSession
    private var uploading = false
    private let didUpload: () -> Void
    init(session: FTPRemoteEditSession, didUpload: @escaping () -> Void) { self.session = session; self.didUpload = didUpload }
    func saved() {
        guard !uploading, session.hasPendingChanges else { return }
        let alert = NSAlert(); alert.messageText = "Upload saved changes to the FTP server?"
        alert.informativeText = "The remote file will be checked for changes before replacement. FTP cannot lock out other writers during upload. Your local copy remains available if upload fails."
        alert.addButton(withTitle: "Upload"); alert.addButton(withTitle: "Keep Local")
        if alert.runModal() == .alertFirstButtonReturn { upload() }
    }
    private func upload() {
        guard !uploading else { return }; uploading = true
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let result = Result { try session.uploadSavedChanges() }
            DispatchQueue.main.async { [self] in
                uploading = false
                switch result {
                case .failure(let error):
                    let alert = NSAlert(error: error)
                    alert.informativeText += "\nLocal recovery copy: " + session.localURL.path
                    alert.runModal()
                case .success:
                    didUpload()
                    let alert = NSAlert(); alert.messageText = "Remote file updated and verified."
                    alert.informativeText = session.hasPendingChanges ? "Newer local edits remain to be uploaded." : session.remotePath
                    alert.runModal()
                }
            }
        }
    }
    func shouldClose() -> Bool {
        if uploading {
            let alert = NSAlert(); alert.messageText = "Wait for the remote upload to finish before closing."; alert.runModal(); return false
        }
        guard session.hasPendingChanges else { return true }
        let alert = NSAlert(); alert.messageText = "Local changes have not been uploaded."
        alert.informativeText = "Keep editing, export a local copy, or explicitly discard these pending changes."
        alert.addButton(withTitle: "Keep Editing"); alert.addButton(withTitle: "Export Local Copy"); alert.addButton(withTitle: "Discard")
        switch alert.runModal() {
        case .alertSecondButtonReturn:
            let panel = NSSavePanel(); panel.nameFieldStringValue = session.localURL.lastPathComponent
            guard panel.runModal() == .OK, let url = panel.url else { return false }
            do { try FileManager.default.copyItem(at: session.localURL, to: url); return true }
            catch { NSAlert(error: error).runModal(); return false }
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }
    func closed() { session.discardAndClose() }
}

extension CommanderController {
    private func refreshRemoteEditedLocation(client: FTPClient, folder: String) {
        let matching = [left, right].filter { pane in
            if case .ftp(let current, let path) = pane.location {
                return current === client && (try? FTPClient.normalizedPath(path)) == (try? FTPClient.normalizedPath(folder))
            }
            return false
        }
        guard !matching.isEmpty else { return }
        if busy || matching.contains(where: { $0.isLoading }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.refreshRemoteEditedLocation(client: client, folder: folder) }
        } else { matching.forEach { reloadPane($0) } }
    }
    func openRemoteEditor(entry: FileEntry) {
        guard !busy, !entry.isDirectory, !entry.isSymbolicLink,
              case .ftp(let client, _) = activePane.location else { NSSound.beep(); return }
        let location = activePane.location
        do {
            let path = try location.selectedPath(entry)
            runOperation("Download remote text for editing", success: "Remote editor opened") { [weak self] in
                let session = try FTPRemoteEditSession.prepare(client: client, remotePath: path)
                DispatchQueue.main.async {
                    let coordinator = RemoteEditingCoordinator(session: session) { [weak self] in
                        self?.refreshRemoteEditedLocation(client: client, folder: (path as NSString).deletingLastPathComponent)
                    }
                    do {
                        try EditorController.open(url: session.localURL, editable: true,
                            onSaved: { _ in coordinator.saved() }, shouldClose: { coordinator.shouldClose() }, onClosed: { coordinator.closed() })
                    } catch { session.discardAndClose(); self?.showError(error) }
                }
            }
        } catch { showError(error) }
    }
}
