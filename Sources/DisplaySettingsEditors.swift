import AppKit

private func displaySettingsError(_ text:String)->NSError {NSError(domain:"DisplaySettings",code:1,userInfo:[NSLocalizedDescriptionKey:text])}
private final class DisplayEditorAction:NSObject {
    let body:()->Void
    init(_ body:@escaping ()->Void){self.body=body}
    @objc func invoke(){body()}
}
/// Draft-only reusable list editor. Every navigation/action collects the active form
/// first, so changing selection never silently drops an invalid or unsaved edit.
final class DisplaySettingsListEditor<Value>:NSStackView {
    private(set) var items:[Value]
    let picker=NSPopUpButton(),errorLabel=NSTextField(wrappingLabelWithString:"")
    private let detail=NSStackView()
    private var selected=0,readForm:(()throws->Value)?,targets:[DisplayEditorAction]=[]
    private let title:(Value)->String,make:()->Value,copy:(Value)->Value,build:(Value)->(NSView,()throws->Value)
    var mayDelete:((Value)throws->Void)?
    init(items:[Value],noun:String,title:@escaping(Value)->String,make:@escaping()->Value,copy:@escaping(Value)->Value,build:@escaping(Value)->(NSView,()throws->Value)) {
        self.items=items;self.title=title;self.make=make;self.copy=copy;self.build=build
        super.init(frame:.zero);orientation = .vertical;alignment = .leading;spacing=8
        identifier=NSUserInterfaceItemIdentifier("display.editor."+noun)
        picker.setAccessibilityLabel(noun);addArrangedSubview(picker)
        let target=DisplayEditorAction{[weak self] in self?.changeSelection()};targets.append(target);picker.target=target;picker.action=#selector(DisplayEditorAction.invoke)
        let buttons=NSStackView();buttons.orientation = .horizontal;buttons.spacing=6
        for (name,action) in [("New",0),("Edit",1),("Copy",2),("Delete",3),("Up",4),("Down",5)] {
            let target=DisplayEditorAction{[weak self] in self?.perform(action)};targets.append(target)
            let button=NSButton(title:name,target:target,action:#selector(DisplayEditorAction.invoke));button.setAccessibilityLabel(name+" "+noun);buttons.addArrangedSubview(button)
        }
        addArrangedSubview(buttons);errorLabel.textColor = .systemRed;errorLabel.font = .systemFont(ofSize:11);addArrangedSubview(errorLabel)
        detail.orientation = .vertical;detail.alignment = .leading;detail.spacing=8;addArrangedSubview(detail)
        picker.widthAnchor.constraint(greaterThanOrEqualToConstant:280).isActive=true
        errorLabel.widthAnchor.constraint(equalToConstant:500).isActive=true
        rebuild()
    }
    required init?(coder:NSCoder){fatalError()}
    func values()throws->[Value] {try collect();return items}
    func selectItem(at index:Int) {guard items.indices.contains(index) else{return};picker.selectItem(at:index);changeSelection()}
    private func collect()throws {if items.indices.contains(selected),let readForm{items[selected]=try readForm()}}
    private func changeSelection(){let next=picker.indexOfSelectedItem;do{try collect();selected=next;rebuild()}catch{picker.selectItem(at:selected);errorLabel.stringValue=error.localizedDescription}}
    private func perform(_ action:Int) {
        do {
            if action != 3 {try collect()};errorLabel.stringValue=""
            switch action {
            case 0:items.append(make());selected=items.count-1
            case 1:break
            case 2:if items.indices.contains(selected){items.insert(copy(items[selected]),at:selected+1);selected += 1}
            case 3:if items.indices.contains(selected){try mayDelete?(items[selected]);items.remove(at:selected);selected=max(0,min(selected,items.count-1))}
            case 4:if selected>0 {items.swapAt(selected,selected-1);selected -= 1}
            case 5:if selected+1<items.count {items.swapAt(selected,selected+1);selected += 1}
            default:break
            }
            rebuild()
        } catch {errorLabel.stringValue=error.localizedDescription}
    }
    private func rebuild() {
        picker.removeAllItems();picker.addItems(withTitles:items.map(title));picker.isEnabled = !items.isEmpty
        if items.indices.contains(selected){picker.selectItem(at:selected)}
        for view in detail.arrangedSubviews{detail.removeArrangedSubview(view);view.removeFromSuperview()};readForm=nil
        if items.indices.contains(selected){let (view,read)=build(items[selected]);detail.addArrangedSubview(view);readForm=read}
        else{detail.addArrangedSubview(NSTextField(labelWithString:"No entries. Choose New to create one."))}
    }
}
private final class DisplaySettingsForm:NSStackView {
    var targets:[DisplayEditorAction]=[]
    init(){super.init(frame:.zero);orientation = .vertical;alignment = .leading;spacing=8}
    required init?(coder:NSCoder){fatalError()}
    func row(_ title:String,_ view:NSView){let label=NSTextField(labelWithString:title),row=NSStackView(views:[label,view]);row.spacing=10;label.widthAnchor.constraint(equalToConstant:185).isActive=true;view.widthAnchor.constraint(greaterThanOrEqualToConstant:220).isActive=true;view.setAccessibilityLabel(title);addArrangedSubview(row)}
    func text(_ title:String,_ value:String)->NSTextField {let f=NSTextField(string:value);row(title,f);return f}
    func choice(_ title:String,_ values:[String],_ selected:Int)->NSPopUpButton {let p=NSPopUpButton();p.addItems(withTitles:values);p.selectItem(at:max(0,min(selected,values.count-1)));row(title,p);return p}
    func check(_ title:String,_ value:Bool)->NSButton {let b=NSButton(checkboxWithTitle:title,target:nil,action:nil);b.state=value ? .on:.off;addArrangedSubview(b);return b}
    func optionalColor(_ title:String,_ value:ConfigurationColor?)->(NSButton,NSColorWell) {let enabled=check("Override "+title,value != nil),well=NSColorWell();well.color=(value ?? .white).nsColor;row(title,well);return(enabled,well)}
}

enum DisplaySettingsEditors {
    static func columns(_ items:[CustomColumnSet])->DisplaySettingsListEditor<CustomColumnSet> {
        DisplaySettingsListEditor(items:items,noun:"column set",title:{$0.name},make:{CustomColumnSet(columns:[CustomColumnDefinition()])},copy:{var c=$0;c.id=UUID().uuidString;c.name += " copy";return c}) { original in
            let form=DisplaySettingsForm(),name=form.text("Set name",original.name)
            let adjust=form.check("Adjust name column to window width",original.adjustNameWidth),scroll=form.check("Horizontal scrollbar",original.horizontalScroll)
            let columns=DisplaySettingsListEditor(items:original.columns,noun:"column",title:{$0.title},make:{CustomColumnDefinition()},copy:{var c=$0;c.id=UUID().uuidString;c.title += " copy";return c}) { initial in
                let f=DisplaySettingsForm(),caption=f.text("Caption",initial.title),expression=f.text("Field contents",initial.expression),width=f.text("Width (points)",String(Int(initial.width)))
                let align=f.choice("Align",["Left","Right"],initial.alignment == .right ? 1:0)
                let fields=f.choice("Insert field",["Choose built-in field…"]+CustomColumnExpression.availableFields,0)
                let target=DisplayEditorAction{if fields.indexOfSelectedItem>0 {expression.stringValue += fields.titleOfSelectedItem ?? "";fields.selectItem(at:0)}}
                f.targets.append(target);fields.target=target;fields.action=#selector(DisplayEditorAction.invoke)
                return(f,{
                    var c=initial;c.title=caption.stringValue.trimmingCharacters(in:.whitespacesAndNewlines);c.expression=expression.stringValue
                    guard let w=Double(width.stringValue),w.isFinite,(32...1200).contains(w) else{throw displaySettingsError("Column width must be between 32 and 1,200 points.")}
                    c.width=w;c.alignment=align.indexOfSelectedItem==1 ? .right:.left
                    try CustomColumnExpression.validate(c.expression);return c
                })
            }
            form.addArrangedSubview(columns)
            return(form,{
                var c=original;c.name=name.stringValue.trimmingCharacters(in:.whitespacesAndNewlines);c.columns=try columns.values();c.adjustNameWidth=adjust.state == .on;c.horizontalScroll=scroll.state == .on
                try CustomColumnSettings.validate(sets:[c],activeID:"");return c
            })
        }
    }
    static func modes(_ items:[CommanderViewMode],sets:@escaping()->[CustomColumnSet])->DisplaySettingsListEditor<CommanderViewMode> {
        DisplaySettingsListEditor(items:items,noun:"view mode",title:{$0.name},make:{CommanderViewMode()},copy:{var c=$0;c.id=UUID().uuidString;c.name += " copy";return c}) { original in
            let form=DisplaySettingsForm(),name=form.text("Mode name",original.name)
            let defaultMode=form.check("Use as the default mode when no rule matches",original.id=="default"),ordinaryID=original.id=="default" ? UUID().uuidString:original.id
            let viewValues:[CommanderColumnsView]=[.unchanged,.full,.brief,.thumbnails]
            let view=form.choice("Columns view",["Unchanged","Full","Brief","Thumbnails"],viewValues.firstIndex(of:original.columnsView) ?? 0)
            let custom=sets(),setIDs:[String?]=[nil,""]+custom.map{Optional($0.id)}
            let columns=form.choice("Custom column set",["Unchanged","Standard columns"]+custom.map(\.name),setIDs.firstIndex(of:original.customColumnSetID) ?? 0)
            var sortIDs=["unchanged","name","ext","size","date","unsorted"],sortTitles=["Unchanged","Name","Extension","Size","Date","Unsorted"]
            for set in custom {for column in set.columns {sortIDs.append("custom."+column.id);sortTitles.append(set.name+": "+column.title)}}
            let sort=form.choice("Sort order",sortTitles,sortIDs.firstIndex(of:original.sortColumn) ?? 0)
            let secondary=form.text("Additional sort columns",original.secondarySortColumns.joined(separator:";"))
            secondary.placeholderString="ext;-size (semicolon separated; - reverses)"
            let ascending=form.choice("Direction",["Unchanged","Ascending","Descending"],original.ascending.map{$0 ? 1:2} ?? 0)
            let directories=form.choice("Directories first",["Unchanged","Yes","No"],original.directoriesFirst.map{$0 ? 1:2} ?? 0)
            let maskEnabled=form.check("Override file filter",original.fileMask != nil),mask=form.text("File filter",original.fileMask ?? "*")
            let (backgroundEnabled,background)=form.optionalColor("background",original.background),(foregroundEnabled,foreground)=form.optionalColor("foreground",original.foreground)
            let (alternateEnabled,alternate)=form.optionalColor("alternate background",original.alternatingBackground),(tabColorEnabled,tabColor)=form.optionalColor("tab color",original.tabColor)
            let tabIcon=form.text("Tab icon (SF Symbol)",original.tabIcon),commands=form.text("Auto-run commands",original.autoRunCommands)
            commands.placeholderString="cm_100percent|cm_50percent"
            return(form,{
                var c=original;c.id=defaultMode.state == .on ? "default":ordinaryID;c.name=name.stringValue.trimmingCharacters(in:.whitespacesAndNewlines);c.columnsView=viewValues[view.indexOfSelectedItem];c.customColumnSetID=setIDs[columns.indexOfSelectedItem];c.sortColumn=sortIDs[sort.indexOfSelectedItem]
                c.secondarySortColumns=secondary.stringValue.split(separator:";").map{$0.trimmingCharacters(in:.whitespacesAndNewlines)}
                c.alternatingBackground=alternateEnabled.state == .on ? ConfigurationColor(alternate.color):nil;c.tabColor=tabColorEnabled.state == .on ? ConfigurationColor(tabColor.color):nil;c.tabIcon=tabIcon.stringValue;c.autoRunCommands=commands.stringValue
                c.ascending=ascending.indexOfSelectedItem==0 ? nil:ascending.indexOfSelectedItem==1;c.directoriesFirst=directories.indexOfSelectedItem==0 ? nil:directories.indexOfSelectedItem==1
                c.fileMask=maskEnabled.state == .on ? mask.stringValue:nil;c.background=backgroundEnabled.state == .on ? ConfigurationColor(background.color):nil;c.foreground=foregroundEnabled.state == .on ? ConfigurationColor(foreground.color):nil
                try ViewModeSettings.validate(modes:[c],rules:[],customColumnSets:sets());return c
            })
        }
    }
    static func rules(_ items:[CommanderAutoSwitchRule],modes:@escaping()->[CommanderViewMode])->DisplaySettingsListEditor<CommanderAutoSwitchRule> {
        DisplaySettingsListEditor(items:items,noun:"switch rule",title:{$0.name},make:{CommanderAutoSwitchRule(conditions:[CommanderViewCondition()])},copy:{var c=$0;c.id=UUID().uuidString;c.name += " copy";return c}) { original in
            let form=DisplaySettingsForm(),name=form.text("Rule name",original.name),enabled=form.check("Enable this rule",original.enabled),available=modes()
            let mode=form.choice("Switch to view mode",["Choose a view mode…"]+available.map(\.name),(available.firstIndex{$0.id==original.viewModeID}.map{$0+1}) ?? 0)
            let match=form.choice("Combine conditions",["All (AND)","Any (OR)"],original.match == .any ? 1:0)
            let conditions=DisplaySettingsListEditor(items:original.conditions,noun:"condition",title:{($0.negated ? "NOT ":"")+$0.kind.rawValue+($0.value.isEmpty ? "":": "+$0.value)},make:{CommanderViewCondition()},copy:{$0}) { initial in
                let f=DisplaySettingsForm(),kinds:[CommanderViewConditionKind]=[.path,.local,.archive,.ftp,.fileMask]
                let kind=f.choice("Condition",["Directory path","Local filesystem","Archive","FTP connection","Files matching mask"],kinds.firstIndex(of:initial.kind) ?? 0)
                let join=f.choice("Join with previous condition",["Use rule setting","AND","OR"],initial.conjunction.map{$0 == .all ? 1:2} ?? 0)
                let policies:[CommanderFileMatch]=[.all,.none,.half,.any,.percent]
                let policy=f.choice("File matching policy",["All files","No files","At least half","At least one","At least percentage"],policies.firstIndex(of:initial.fileMatch) ?? 3)
                let path=f.text("Restrict file match to path",initial.path)
                let value=f.text("Path or file masks",initial.value),children=f.check("Include subdirectories for path",initial.includeSubdirectories),percent=f.text("Minimum matching files (%)",String(initial.minimumMatchPercent)),negated=f.check("Negate this condition (NOT)",initial.negated)
                return(f,{
                    var c=initial;c.conjunction=join.indexOfSelectedItem==0 ? nil:(join.indexOfSelectedItem==1 ? .all:.any);c.fileMatch=policies[policy.indexOfSelectedItem];c.path=path.stringValue;c.kind=kinds[kind.indexOfSelectedItem];c.value=value.stringValue;c.includeSubdirectories=children.state == .on;c.negated=negated.state == .on
                    guard let p=Int(percent.stringValue),(0...100).contains(p) else{throw displaySettingsError("Matching percentage must be between 0 and 100. Zero means at least one matching file.")};c.minimumMatchPercent=p;return c
                })
            }
            form.addArrangedSubview(conditions)
            return(form,{
                var c=original;c.name=name.stringValue.trimmingCharacters(in:.whitespacesAndNewlines);c.enabled=enabled.state == .on;c.match=match.indexOfSelectedItem==1 ? .any:.all;c.conditions=try conditions.values()
                guard mode.indexOfSelectedItem>0 else{throw displaySettingsError("Choose a saved view mode for this rule.")};c.viewModeID=available[mode.indexOfSelectedItem-1].id;return c
            })
        }
    }
}
