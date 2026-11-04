import AppKit
import UniformTypeIdentifiers

/// Edits a staged native configuration. Imported files are never modified implicitly.
final class ConfigurationFilesController:NSWindowController,NSWindowDelegate {
    private static var retained:[ObjectIdentifier:ConfigurationFilesController]=[:]
    private weak var commander:CommanderController?
    private var baseline:CommanderConfiguration
    let textView=NSTextView()
    private let status=NSTextField(wrappingLabelWithString:"Edit native JSON, or import a native JSON / Windows INI file. Apply saves app preferences; Export writes a portable file.")
    init(_ commander:CommanderController) throws {
        self.commander=commander;baseline=commander.runtimeConfig
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:800,height:620),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.title="Configuration file";window.isReleasedWhenClosed=false;window.minSize=NSSize(width:600,height:400)
        super.init(window:window);window.delegate=self
        textView.isRichText=false;textView.isAutomaticQuoteSubstitutionEnabled=false;textView.isAutomaticDashSubstitutionEnabled=false
        textView.font = .monospacedSystemFont(ofSize:12,weight:.regular)
        textView.string=String(decoding:try ConfigurationFiles.exportNative(baseline),as:UTF8.self)
        let scroll=NSScrollView();scroll.documentView=textView;scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=false
        textView.minSize=NSSize(width:0,height:0);textView.maxSize=NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable=true;textView.isHorizontallyResizable=false;textView.autoresizingMask = .width
        textView.textContainer?.widthTracksTextView=true
        let importButton=NSButton(title:"Import…",target:self,action:#selector(importFile))
        let exportButton=NSButton(title:"Export…",target:self,action:#selector(exportFile))
        let applyButton=NSButton(title:"Apply",target:self,action:#selector(apply))
        let closeButton=NSButton(title:"Close",target:self,action:#selector(closeEditor));closeButton.keyEquivalent="\u{1b}"
        let buttons=NSStackView(views:[importButton,exportButton,NSView(),closeButton,applyButton]);buttons.spacing=10
        let root=NSStackView(views:[status,scroll,buttons]);root.orientation = .vertical;root.alignment = .leading;root.spacing=12
        window.contentView!.addSubview(root);root.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor,constant:16),root.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor,constant:-16),root.topAnchor.constraint(equalTo:window.contentView!.topAnchor,constant:16),root.bottomAnchor.constraint(equalTo:window.contentView!.bottomAnchor,constant:-16),scroll.widthAnchor.constraint(equalTo:root.widthAnchor),status.widthAnchor.constraint(equalTo:root.widthAnchor),buttons.widthAnchor.constraint(equalTo:root.widthAnchor),scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:250)])
    }
    required init?(coder:NSCoder){fatalError("init(coder:) is not supported")}
    static func open(_ commander:CommanderController) throws {
        let controller=try ConfigurationFilesController(commander);retained[ObjectIdentifier(controller)]=controller
        controller.showWindow(nil);controller.window?.center();controller.window?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification:Notification){Self.retained.removeValue(forKey:ObjectIdentifier(self))}
    private func failure(_ text:String)->NSError {NSError(domain:"ConfigurationFile",code:1,userInfo:[NSLocalizedDescriptionKey:text])}
    private func show(_ error:Error){if let window {NSAlert(error:error).beginSheetModal(for:window)}}
    func parsedConfiguration() throws ->CommanderConfiguration {try ConfigurationFiles.importNative(Data(textView.string.utf8))}
    @objc func apply() {
        do {
            guard let commander else{return}
            guard commander.runtimeConfig==baseline else {throw failure("Settings changed while this editor was open. Close and reopen it to avoid overwriting newer changes.")}
            let configuration=try parsedConfiguration()
            if commander.remember {try configuration.save()}
            commander.applyConfiguration(configuration);baseline=configuration
            status.stringValue="Settings applied. Imported source files have not been changed."
        }catch{show(error)}
    }
    @objc private func closeEditor(){close()}
    @objc private func importFile() {
        guard let window else{return}
        let panel=NSOpenPanel();panel.allowsMultipleSelection=false;panel.canChooseDirectories=false
        panel.message="Choose native configuration JSON or wincmd.ini. Unsupported Windows options will be reported."
        panel.beginSheetModal(for:window){[weak self] response in
            guard response == .OK,let self,let url=panel.url else{return}
            do {
                let data=try ConfigurationFiles.readData(from:url)
                if url.pathExtension.lowercased()=="ini" {
                    let report=try ConfigurationFiles.importINI(data,merging:self.baseline)
                    self.textView.string=String(decoding:try ConfigurationFiles.exportNative(report.configuration),as:UTF8.self)
                    self.status.stringValue="Imported \(report.imported.count) options; unsupported: \(report.unsupported.count); invalid: \(report.invalid.count). Review, then Apply."
                    let alert=NSAlert();alert.messageText="INI import review"
                    alert.informativeText="Imported: \(report.imported.joined(separator:", "))\n\nUnsupported: \(report.unsupported.joined(separator:", "))\n\nInvalid: \(report.invalid.joined(separator:", "))"
                    alert.beginSheetModal(for:window)
                } else {
                    let configuration=try ConfigurationFiles.importNative(data)
                    self.textView.string=String(decoding:try ConfigurationFiles.exportNative(configuration),as:UTF8.self)
                    self.status.stringValue="Loaded \(url.lastPathComponent). Review, then Apply."
                }
            }catch{self.show(error)}
        }
    }
    @objc private func exportFile() {
        do {
            let configuration=try parsedConfiguration();guard let window else{return}
            let panel=NSSavePanel();panel.nameFieldStringValue="total-commander-settings.json";panel.allowedContentTypes=[.json]
            panel.beginSheetModal(for:window){[weak self] response in
                guard response == .OK,let self,let url=panel.url else{return}
                do {try ConfigurationFiles.writeNative(configuration,to:url);self.status.stringValue="Exported \(url.path)."}catch{self.show(error)}
            }
        }catch{show(error)}
    }
}

extension CommanderController {
    @objc func configurationFile(){do {try ConfigurationFilesController.open(self)}catch{showError(error)}}
}
