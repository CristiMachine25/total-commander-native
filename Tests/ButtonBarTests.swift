import Foundation
@main struct ButtonBarTests {
    static var count=0
    static func check(_ condition:Bool,_ text:String){count += 1;precondition(condition,text)}
    static func main()throws {
        let name="button-bar-tests-"+UUID().uuidString,defaults=UserDefaults(suiteName:"button-bar-tests-"+UUID().uuidString)!
        defer{defaults.removeObject(forKey:CommanderButtonBar.defaultsKey)}
        var bar=CommanderButtonBar();check(bar.items.count==14,"Preserve default toolbar")
        check(CommanderButtonBar.load(from:defaults)==bar,"Missing configuration restores defaults")
        bar.items.reverse();bar.items.insert(.init(title:"",command:"",separator:true),at:1);bar.showLabels=true;bar.iconSize=32
        try bar.save(to:defaults);check(CommanderButtonBar.load(from:defaults)==bar,"Order, separators, labels and size persist")
        bar.items=[];try bar.save(to:defaults);check(CommanderButtonBar.load(from:defaults).items.isEmpty,"Empty bar persists")
        defaults.set(Data("broken".utf8),forKey:CommanderButtonBar.defaultsKey);check(CommanderButtonBar.load(from:defaults)==CommanderButtonBar(),"Corrupt data recovers defaults")
        check(try CommanderButtonBar.arguments("one 'two three' \"four five\" six\\ seven")==["one","two three","four five","six seven"],"Quoted arguments")
        check(try CommanderButtonBar.arguments("'' \"\" $HOME '*.txt'")==["","","$HOME","*.txt"],"Empty arguments and no shell interpolation")
        for invalid in ["'unfinished","trailing\\"] {do{_=try CommanderButtonBar.arguments(invalid);preconditionFailure("Invalid quote accepted")}catch{count += 1}}
        bar=CommanderButtonBar();bar.items[0].command="relative/path";do{try bar.validate();preconditionFailure("Relative path accepted")}catch{count += 1}
        bar.items[0].command="/Applications/Test App.app";try bar.validate();check(true,"App path with spaces accepted")
        bar.items[0].title="";do{try bar.validate();preconditionFailure("Missing label accepted")}catch{count += 1}
        _=name
        print("PASS: \(count) button bar model assertions")
    }
}
