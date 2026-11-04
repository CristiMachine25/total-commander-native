import AppKit
import ObjectiveC

private var customColumnCacheKey:UInt8=0
private final class CustomColumnCache:NSObject {
    var set:CustomColumnSet?
    var expressions:[String:CustomColumnExpression]=[:]
}
extension Pane {
    var currentCustomColumnSet:CustomColumnSet? {configuration.customColumnSets.first{$0.id==configuration.activeCustomColumnSetID}}
    private var customColumnCache:CustomColumnCache {
        if let value=objc_getAssociatedObject(self,&customColumnCacheKey) as? CustomColumnCache{return value}
        let value=CustomColumnCache();objc_setAssociatedObject(self,&customColumnCacheKey,value,.OBJC_ASSOCIATION_RETAIN_NONATOMIC);return value
    }
    func applyCustomColumnLayout() {
        let set=currentCustomColumnSet,cache=customColumnCache
        if cache.set != set {
            for column in table.tableColumns where column.identifier.rawValue.hasPrefix("custom."){table.removeTableColumn(column)}
            cache.set=set;cache.expressions=[:]
            for definition in set?.columns ?? [] {
                let column=NSTableColumn(identifier:.init("custom."+definition.id))
                column.title=definition.title;column.width=definition.width;column.minWidth=32;column.maxWidth=1200
                column.headerCell.font=NSFont(name:"Tahoma-Bold",size:12) ?? .systemFont(ofSize:12,weight:.semibold)
                table.addTableColumn(column);cache.expressions[definition.id]=try? CustomColumnExpression(definition.expression)
            }
            if sortColumn.hasPrefix("custom."),customColumnDefinition(sortColumn)==nil {sortColumn="name"}
        }
        for column in table.tableColumns {
            let key=column.identifier.rawValue
            if key.hasPrefix("custom."){column.isHidden=false}
            else if set != nil {column.isHidden = key != "name" && key != "ext"}
        }
        table.columnAutoresizingStyle=set?.adjustNameWidth == false ? .noColumnAutoresizing:.firstColumnOnlyAutoresizingStyle
        table.enclosingScrollView?.hasHorizontalScroller=set?.horizontalScroll ?? false
    }
    func customColumnDefinition(_ identifier:String)->CustomColumnDefinition? {
        guard identifier.hasPrefix("custom.") else{return nil}
        return currentCustomColumnSet?.columns.first{$0.id==String(identifier.dropFirst(7))}
    }
    func customColumnText(_ identifier:String,entry:FileEntry)->String? {
        guard let definition=customColumnDefinition(identifier),let expression=customColumnCache.expressions[definition.id] else{return nil}
        return expression.text(entry:entry,local:location.localDirectory != nil,dateText:{self.configuration.dateString($0)},sizeText:{self.configuration.sizeString($0)})
    }
    func compareCustomColumn(_ identifier:String,_ lhs:FileEntry,_ rhs:FileEntry)->ComparisonResult? {
        guard let definition=customColumnDefinition(identifier),let expression=customColumnCache.expressions[definition.id] else{return nil}
        return expression.compare(lhs,rhs,local:location.localDirectory != nil,caseSensitive:configuration.caseSensitiveSort,dateText:{self.configuration.dateString($0)},sizeText:{self.configuration.sizeString($0)})
    }
}

private final class CustomColumnMenuAction:NSObject {
    let action:()->Void
    init(_ action:@escaping ()->Void){self.action=action}
    @objc func invoke(){action()}
}
extension CommanderController {
    func customColumnsMenu()->NSMenu {
        let menu=NSMenu(title:"Custom Columns");menu.autoenablesItems=false
        func item(_ title:String,_ id:String){
            let target=CustomColumnMenuAction{[weak self] in self?.selectCustomColumns(id)}
            let item=NSMenuItem(title:title,action:#selector(CustomColumnMenuAction.invoke),keyEquivalent:"")
            item.target=target;item.representedObject=target;item.state=activePane.configuration.activeCustomColumnSetID==id ? .on:.off
            item.isEnabled = !busy && !activePane.isLoading;menu.addItem(item)
        }
        item("Standard columns","")
        for set in runtimeConfig.customColumnSets where !set.name.isEmpty {item(set.name,set.id)}
        return menu
    }
    func selectCustomColumns(_ id:String) {
        guard !busy,!activePane.isLoading,id.isEmpty || runtimeConfig.customColumnSets.contains(where:{$0.id==id}) else{return}
        var config=activePane.configuration;config.activeCustomColumnSetID=id
        activePane.applyConfiguration(config);activePane.setBriefMode(false)
        recordManualViewChange(in:activePane)
        window.makeFirstResponder(activePane.fileResponder)
    }
}
