import AppKit
import ImageIO

enum PaneViewMode:String {case full,brief,thumbnails,tree}
enum ThumbnailLayout {
    static func columns(width:CGFloat,cellWidth:CGFloat)->Int {max(1,Int(max(0,width)/max(1,cellWidth)))}
    static func rows(count:Int,columns:Int)->Int {(max(0,count)+max(1,columns)-1)/max(1,columns)}
    static func index(column:Int,row:Int,columns:Int,count:Int)->Int? {
        guard row>=0,column>=0,column<max(1,columns) else{return nil}
        let i=row*max(1,columns)+column;return i<count ? i:nil
    }
    static func move(_ index:Int,key:UInt16,columns:Int,count:Int)->Int {
        guard count>0 else{return 0};let i=min(max(0,index),count-1),c=max(1,columns)
        switch key {case 123:return max(0,i-1);case 124:return min(count-1,i+1);case 126:return max(0,i-c);case 125:return min(count-1,i+c);case 115:return 0;case 119:return count-1;default:return i}
    }
}
enum ThumbnailDecoder {
    static let inputLimit:UInt64=33_554_432
    static func image(url:URL,pixels:Int)throws->NSImage? {
        let doc=try ListerDocument(url:url)
        guard doc.size<=inputLimit else {throw ListerError.message("Thumbnail input exceeds 32 MiB.")}
        var data=Data();data.reserveCapacity(Int(doc.size))
        for index in 0..<doc.pageCount {data.append(try doc.page(index))}
        guard let source=CGImageSourceCreateWithData(data as CFData,[kCGImageSourceShouldCache:false] as CFDictionary) else{return nil}
        let options:[CFString:Any]=[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:max(32,min(512,pixels)),kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceShouldCacheImmediately:false]
        guard let image=CGImageSourceCreateThumbnailAtIndex(source,0,options as CFDictionary) else{return nil}
        return NSImage(cgImage:image,size:NSSize(width:image.width,height:image.height))
    }
}
#if !THUMBNAIL_TEST
final class ThumbnailGridView:NSView {
    weak var pane:Pane?
    var pixels=128
    private var generation=0
    private var identity=""
    private var pending=Set<String>(),failed=Set<String>()
    private let cache=NSCache<NSString,NSImage>()
    private let queue:OperationQueue={let q=OperationQueue();q.maxConcurrentOperationCount=2;q.qualityOfService = .userInitiated;return q}()
    private let imageExtensions=Set(["jpg","jpeg","png","gif","tif","tiff","bmp","heic","webp","ico","icns"])
    var cellWidth:CGFloat {CGFloat(pixels+28)}
    var cellHeight:CGFloat {CGFloat(pixels+64)}
    var columns:Int {ThumbnailLayout.columns(width:enclosingScrollView?.contentSize.width ?? 1,cellWidth:cellWidth)}
    override var isFlipped:Bool {true}
    override var acceptsFirstResponder:Bool {true}
    override init(frame:NSRect){super.init(frame:frame);cache.totalCostLimit=64*1024*1024;setAccessibilityLabel("Thumbnail file list");setAccessibilityRole(.list)}
    required init?(coder:NSCoder){fatalError()}
    deinit {queue.cancelAllOperations()}
    override func becomeFirstResponder()->Bool {pane?.onActivate?();return true}
    func invalidateListing() {generation += 1;pending.removeAll();failed.removeAll();queue.cancelAllOperations();updateGeometry()}
    func updateGeometry() {
        guard let pane,let scroll=enclosingScrollView else{return}
        let next=pane.location.identity+"|"+String(pixels)
        if next != identity {identity=next;generation += 1;pending.removeAll();failed.removeAll();queue.cancelAllOperations()}
        let size=NSSize(width:max(1,scroll.contentSize.width),height:max(scroll.contentSize.height,CGFloat(ThumbnailLayout.rows(count:pane.entries.count+1,columns:columns))*cellHeight))
        if frame.size != size {setFrameSize(size)};needsDisplay=true
    }
    func cellRect(_ index:Int)->NSRect {NSRect(x:CGFloat(index%columns)*cellWidth,y:CGFloat(index/columns)*cellHeight,width:cellWidth,height:cellHeight)}
    func revealSelection(){if let pane,pane.table.selectedRow>=0 {scrollToVisible(cellRect(pane.table.selectedRow))};needsDisplay=true}
    private func image(_ entry:FileEntry)->NSImage? {
        guard !entry.isDirectory,!entry.isSymbolicLink,entry.size<=Int64(ThumbnailDecoder.inputLimit),imageExtensions.contains(entry.url.pathExtension.lowercased()),pane?.location.localDirectory != nil else{return nil}
        let key=entry.url.absoluteString+"|\(entry.size)|\(entry.modified?.timeIntervalSince1970 ?? 0)|\(pixels)"
        if let cached=cache.object(forKey:key as NSString){return cached}
        guard !pending.contains(key),!failed.contains(key) else{return nil};pending.insert(key)
        let token=generation,size=pixels,url=entry.url
        queue.addOperation { [weak self] in
            let result=try? ThumbnailDecoder.image(url:url,pixels:size)
            DispatchQueue.main.async { [weak self] in
                guard let self,self.generation==token else{return};self.pending.remove(key)
                if let result {self.cache.setObject(result,forKey:key as NSString,cost:Int(result.size.width*result.size.height*4))} else {self.failed.insert(key)}
                self.needsDisplay=true
            }
        };return nil
    }
    override func draw(_ dirtyRect:NSRect) {
        (pane?.configuration.background.nsColor ?? .white).setFill();dirtyRect.fill();guard let pane else{return}
        let first=max(0,Int(dirtyRect.minY/cellHeight)*columns),last=min(pane.entries.count,Int(dirtyRect.maxY/cellHeight+1)*columns-1)
        guard first<=last else{return}
        let paragraph=NSMutableParagraphStyle();paragraph.alignment = .center;paragraph.lineBreakMode = .byTruncatingMiddle
        for index in first...last {
            let rect=cellRect(index),entry=index==0 ? nil:pane.entries[index-1],selected=pane.table.selectedRowIndexes.contains(index)
            if selected {pane.configuration.selectionBackground.nsColor.setFill();rect.insetBy(dx:2,dy:2).fill()}
            let picture=entry.flatMap{image($0)}
            let icon=picture ?? NSImage(systemSymbolName:index==0 ? "arrow.up.backward":(entry?.isDirectory==true ? "folder.fill":"doc"),accessibilityDescription:nil)
            let imageRect=NSRect(x:rect.midX-CGFloat(pixels)/2,y:rect.minY+6,width:CGFloat(pixels),height:CGFloat(pixels))
            if let icon {
                let scale=min(imageRect.width/max(1,icon.size.width),imageRect.height/max(1,icon.size.height),picture == nil ? 0.5:1)
                let size=NSSize(width:icon.size.width*scale,height:icon.size.height*scale)
                icon.draw(in:NSRect(x:imageRect.midX-size.width/2,y:imageRect.midY-size.height/2,width:size.width,height:size.height),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
            }
            let marked=entry.map{pane.marked.contains($0.url)} ?? false
            let text=index==0 ? "[..]":(marked ? "✓ ":"")+entry!.name
            if let entry,!entry.isDirectory,pane.configuration.visibleColumns.contains("size") {
                (pane.configuration.sizeString(entry.size) as NSString).draw(in:NSRect(x:rect.minX+4,y:rect.minY+CGFloat(pixels)+44,width:rect.width-8,height:18),withAttributes:[.font:NSFont.systemFont(ofSize:10),.foregroundColor:pane.itemColor(marked:marked,selected:selected),.paragraphStyle:paragraph])
            }
            (text as NSString).draw(in:NSRect(x:rect.minX+4,y:rect.minY+CGFloat(pixels)+12,width:rect.width-8,height:32),withAttributes:[.font:pane.configuredFont,.foregroundColor:pane.itemColor(marked:marked,selected:selected),.paragraphStyle:paragraph])
        }
    }
    override func menu(for event:NSEvent)->NSMenu? {
        guard let pane else{return nil}
        let point=convert(event.locationInWindow,from:nil)
        let index=ThumbnailLayout.index(column:Int(floor(point.x/cellWidth)),row:Int(floor(point.y/cellHeight)),columns:columns,count:pane.entries.count+1)
        return pane.contextMenu(forRow:index ?? -1)
    }
    override func rightMouseDown(with event:NSEvent) {if let menu=menu(for:event){NSMenu.popUpContextMenu(menu,with:event,for:self)}}
    override func mouseDown(with event:NSEvent) {
        if event.modifierFlags.contains(.control) {rightMouseDown(with:event);return}
        guard let pane else{return};pane.onActivate?();window?.makeFirstResponder(self)
        let point=convert(event.locationInWindow,from:nil)
        guard let index=ThumbnailLayout.index(column:Int(floor(point.x/cellWidth)),row:Int(floor(point.y/cellHeight)),columns:columns,count:pane.entries.count+1) else{return}
        let extend=event.modifierFlags.contains(.command)
        if extend,pane.table.selectedRowIndexes.contains(index){pane.table.deselectRow(index)}else{pane.table.selectRowIndexes(IndexSet(integer:index),byExtendingSelection:extend)}
        revealSelection();if event.clickCount==2 || (pane.singleClickOpen && event.modifierFlags.intersection([.control,.shift,.option,.command]).isEmpty){pane.onOpen?()}
    }
    @discardableResult func handleNavigation(_ event:NSEvent)->Bool {
        guard event.modifierFlags.intersection([.control,.shift,.option,.command]).isEmpty,[UInt16(123),124,125,126,115,119].contains(event.keyCode),let pane else{return false}
        if pane.isLoading{return true}
        let next=ThumbnailLayout.move(pane.table.selectedRow,key:event.keyCode,columns:columns,count:pane.entries.count+1)
        pane.table.selectRowIndexes(IndexSet(integer:next),byExtendingSelection:false);revealSelection();return true
    }
    override func keyDown(with event:NSEvent){if handleNavigation(event){return};if pane?.onKey?(event)==true{return};super.keyDown(with:event)}
}
#endif
#if !THUMBNAIL_TEST
final class PaneSelectionRow:NSTableRowView {
    var selectionColor=NSColor.selectedContentBackgroundColor
    override func drawSelection(in dirtyRect:NSRect){selectionColor.setFill();bounds.fill()}
}
#endif
