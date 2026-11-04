import AppKit

/// Flat index 0 is the parent row; columns are filled vertically.
enum BriefLayout {
    static func rows(height:CGFloat,rowHeight:CGFloat)->Int { max(1,Int(max(0,height)/max(1,rowHeight))) }
    static func columns(count:Int,rows:Int)->Int { max(1,(max(0,count)+max(1,rows)-1)/max(1,rows)) }
    static func index(column:Int,row:Int,rows:Int,count:Int)->Int? {
        guard column >= 0,row >= 0,row < max(1,rows) else {return nil}
        let index=column*max(1,rows)+row
        return index < count ? index : nil
    }
    static func move(_ index:Int,key:UInt16,rows:Int,count:Int)->Int {
        guard count > 0 else {return 0}
        let old=min(max(0,index),count-1),r=max(1,rows)
        switch key {
        case 123:return old < r ? old : old-r
        case 124:return old/r >= (count-1)/r ? old : min(count-1,old+r)
        case 125:return min(count-1,old+1)
        case 126:return max(0,old-1)
        case 115:return 0
        case 119:return count-1
        case 116:return max(0,old-r)
        case 121:return min(count-1,old+r)
        default:return old
        }
    }
}

#if !BRIEF_LAYOUT_TEST
final class BriefGridView:NSView {
    weak var pane:Pane?
    var columnWidth:CGFloat {max(80,CGFloat(pane?.configuration.columnWidths["name"] ?? 220))}
    var rowsPerColumn=1
    var rowHeight:CGFloat { max(18,pane?.table.rowHeight ?? 21) }
    private var shiftAnchor:Int?
    private var shiftCursor:Int?
    private let folderIcon=NSImage(systemSymbolName:"folder.fill",accessibilityDescription:"Folder")
    private let fileIcon=NSImage(systemSymbolName:"doc",accessibilityDescription:"File")
    private let upIcon=NSImage(systemSymbolName:"arrow.up.backward",accessibilityDescription:"Parent")
    override var isFlipped:Bool {true}
    override var acceptsFirstResponder:Bool {true}
    override func becomeFirstResponder()->Bool {pane?.onActivate?();return true}
    override init(frame:NSRect) {super.init(frame:frame);setAccessibilityLabel("Brief file list");setAccessibilityRole(.list)}
    required init?(coder:NSCoder) {fatalError()}
    func updateGeometry() {
        guard let pane,let scroll=enclosingScrollView else{return}
        let height=max(1,scroll.contentSize.height)
        rowsPerColumn=BriefLayout.rows(height:height,rowHeight:rowHeight)
        let width=max(scroll.contentSize.width,CGFloat(BriefLayout.columns(count:pane.entries.count+1,rows:rowsPerColumn))*columnWidth)
        if frame.size != NSSize(width:width,height:height) {setFrameSize(NSSize(width:width,height:height))}
        needsDisplay=true
    }
    func resetSelectionAnchor() {shiftAnchor=nil;shiftCursor=nil}
    func cellRect(_ index:Int)->NSRect {NSRect(x:CGFloat(index/rowsPerColumn)*columnWidth,y:CGFloat(index%rowsPerColumn)*rowHeight,width:columnWidth,height:rowHeight)}
    func revealSelection() {if let pane,pane.table.selectedRow >= 0 {scrollToVisible(cellRect(pane.table.selectedRow))};needsDisplay=true}
    override func draw(_ dirtyRect:NSRect) {
        (pane?.configuration.background.nsColor ?? .white).setFill();dirtyRect.fill()
        guard let pane else{return}
        let font=pane.configuredFont
        let paragraph=NSMutableParagraphStyle();paragraph.lineBreakMode = .byTruncatingMiddle
        let first=max(0,Int(dirtyRect.minX/columnWidth)),last=min(BriefLayout.columns(count:pane.entries.count+1,rows:rowsPerColumn)-1,Int(dirtyRect.maxX/columnWidth))
        guard first <= last else{return}
        for column in first...last {
            for row in 0..<rowsPerColumn {
                guard let index=BriefLayout.index(column:column,row:row,rows:rowsPerColumn,count:pane.entries.count+1) else{continue}
                let rect=cellRect(index);guard rect.intersects(dirtyRect) else{continue}
                let selected=pane.table.selectedRowIndexes.contains(index)
                let entry=index == 0 ? nil : pane.entries[index-1]
                let marked=entry.map{pane.marked.contains($0.url)} ?? false
                if selected { pane.configuration.selectionBackground.nsColor.setFill();rect.fill() }
                var icon=index == 0 ? upIcon : (entry?.isDirectory == true ? folderIcon : fileIcon)
                if pane.configuration.iconMode == .none {icon=nil}
                else if pane.configuration.iconMode == .system,let entry,pane.location.localDirectory != nil {icon=NSWorkspace.shared.icon(forFile:entry.url.path)}
                let iconSize=CGFloat(pane.configuration.iconSize)
                icon?.draw(in:NSRect(x:rect.minX+4,y:rect.minY+(rowHeight-iconSize)/2,width:iconSize,height:iconSize),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
                let name=index == 0 ? "[..]" : ((marked ? "✓ " : "")+(entry!.isDirectory ? "[\(entry!.name)]" : entry!.name))
                let color=pane.itemColor(marked:marked,selected:selected)
                (name as NSString).draw(in:NSRect(x:rect.minX+(icon == nil ? 4:iconSize+9),y:rect.minY+max(0,(rowHeight-font.pointSize-3)/2),width:columnWidth-(icon == nil ? 8:iconSize+14),height:rowHeight),withAttributes:[.font:font,.foregroundColor:color,.paragraphStyle:paragraph])
            }
            NSColor.separatorColor.setFill();NSRect(x:CGFloat(column+1)*columnWidth-1,y:0,width:1,height:bounds.height).fill()
        }
    }
    override func mouseDown(with event:NSEvent) {
        guard let pane else{return}
        pane.onActivate?();window?.makeFirstResponder(self)
        let point=convert(event.locationInWindow,from:nil)
        guard let index=BriefLayout.index(column:Int(floor(point.x/columnWidth)),row:Int(floor(point.y/rowHeight)),rows:rowsPerColumn,count:pane.entries.count+1) else{return}
        let mods=event.modifierFlags.intersection([.shift,.command,.control,.option])
        if mods == [.shift] {
            let anchor=shiftAnchor ?? max(0,pane.table.selectedRow);shiftAnchor=anchor
            shiftCursor=index
            pane.table.selectRowIndexes(IndexSet(integersIn:min(anchor,index)...max(anchor,index)),byExtendingSelection:false)
        } else if mods == [.command] {
            if pane.table.selectedRowIndexes.contains(index) {pane.table.deselectRow(index)} else {pane.table.selectRowIndexes(IndexSet(integer:index),byExtendingSelection:true)}
            shiftAnchor=index;shiftCursor=nil
        } else {pane.table.selectRowIndexes(IndexSet(integer:index),byExtendingSelection:false);shiftAnchor=index;shiftCursor=nil}
        revealSelection()
        if event.clickCount == 2 || (pane.singleClickOpen && mods.isEmpty) {pane.onOpen?()}
    }
    @discardableResult func handleNavigation(_ event:NSEvent)->Bool {
        let mods=event.modifierFlags.intersection([.control,.shift,.option,.command])
        guard mods.isEmpty || mods == [.shift],[UInt16(123),124,125,126,115,119,116,121].contains(event.keyCode),let pane else{return false}
        if pane.isLoading {return true}
        let current=mods == [.shift] ? (shiftCursor ?? max(0,pane.table.selectedRow)) : max(0,pane.table.selectedRow)
        let destination=BriefLayout.move(current,key:event.keyCode,rows:rowsPerColumn,count:pane.entries.count+1)
        if mods == [.shift] {
            let anchor=shiftAnchor ?? current;shiftAnchor=anchor;shiftCursor=destination
            pane.table.selectRowIndexes(IndexSet(integersIn:min(anchor,destination)...max(anchor,destination)),byExtendingSelection:false)
        } else {shiftAnchor=destination;shiftCursor=nil;pane.table.selectRowIndexes(IndexSet(integer:destination),byExtendingSelection:false)}
        revealSelection();return true
    }
    override func keyDown(with event:NSEvent) {
        if handleNavigation(event) {return}
        if pane?.onKey?(event) == true {return}
        super.keyDown(with:event)
    }
    override func performKeyEquivalent(with event:NSEvent)->Bool {if pane?.onKey?(event) == true {return true};return super.performKeyEquivalent(with:event)}
}
final class BriefViewport:NSView {
    var resized:(()->Void)?
    override func layout() {super.layout();resized?()}
}
#endif
