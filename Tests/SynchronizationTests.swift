import Foundation
import Darwin

@main struct SynchronizationTests {
    static var assertions = 0
    static func check(_ condition: @autoclosure () throws -> Bool, _ label: String) throws {
        assertions += 1
        if try !condition() { throw NSError(domain: "SyncTests", code: assertions, userInfo: [NSLocalizedDescriptionKey: label]) }
    }
    static func rejects(_ label: String, _ action: () throws -> Void) throws {
        var rejected = false; do { try action() } catch { rejected = true }; try check(rejected,label)
    }
    static func write(_ root: URL, _ path: String, _ text: String) throws {
        let url=root.appendingPathComponent(path); try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try Data(text.utf8).write(to:url)
    }
    static func text(_ root: URL,_ path:String) throws -> String { try String(contentsOf:root.appendingPathComponent(path),encoding:.utf8) }
    static func main() throws {
        let fm=FileManager.default, base=URL(fileURLWithPath:"/private/tmp").appendingPathComponent("native-sync-tests-"+UUID().uuidString)
        try fm.createDirectory(at:base,withIntermediateDirectories:true); defer { try? fm.removeItem(at:base) }
        func pair(_ name:String) throws -> (URL,URL) {
            let a=base.appendingPathComponent(name+"/left"),b=base.appendingPathComponent(name+"/right")
            try fm.createDirectory(at:a,withIntermediateDirectories:true);try fm.createDirectory(at:b,withIntermediateDirectories:true);return(a,b)
        }
        let (a,b)=try pair("basic")
        try write(a,"nested/left.txt","left payload");try write(b,"right.txt","right payload")
        try fm.createDirectory(at:a.appendingPathComponent("empty"),withIntermediateDirectories:false)
        var plan=try NativeSynchronization.compare(left:a,right:b)
        try check(plan.differences.contains { $0.path == "nested/left.txt" && $0.direction == .leftToRight },"Left-only default direction")
        try check(plan.differences.contains { $0.path == "right.txt" && $0.direction == .rightToLeft },"Right-only default direction")
        let result=try NativeSynchronization.apply(plan)
        try check(result.completed == 4,"Nested file, empty directory, parent directory and reverse file copied")
        try check(try text(b,"nested/left.txt") == "left payload" && text(a,"right.txt") == "right payload","Both directions preserve bytes")
        try check(fm.fileExists(atPath:b.appendingPathComponent("empty").path),"Empty directory created")
        try check(try NativeSynchronization.compare(left:a,right:b).differences.isEmpty,"Content equal after synchronization")
        try check(try NativeSynchronization.compare(left:a,right:b,byContent:false).differences.isEmpty,"File timestamps preserved for metadata comparison")
        let (c,d)=try pair("content")
        try write(c,"file","AAA");try write(d,"file","BBB")
        let date=Date(timeIntervalSince1970:100000)
        try fm.setAttributes([.modificationDate:date],ofItemAtPath:c.appendingPathComponent("file").path)
        try fm.setAttributes([.modificationDate:date],ofItemAtPath:d.appendingPathComponent("file").path)
        try check(try NativeSynchronization.compare(left:c,right:d,byContent:false).differences.isEmpty,"Metadata mode explicitly accepts equal size/date")
        plan=try NativeSynchronization.compare(left:c,right:d)
        try check(plan.differences.count == 1 && plan.differences[0].direction == .skip,"Content conflict with equal times requires explicit direction")
        plan.differences[0].direction = .leftToRight
        let replacement=try NativeSynchronization.apply(plan)
        try check(try text(d,"file") == "AAA","Explicit replacement copies selected direction")
        try check(replacement.recoveryFiles.count == 1 && (try String(contentsOfFile:replacement.recoveryFiles[0],encoding:.utf8)) == "BBB","Replaced original retained exactly")
        try check(try NativeSynchronization.compare(left:c,right:d).differences.isEmpty,"Owned recovery files excluded from future synchronization")
        let (e,f)=try pair("newer")
        try write(e,"file","old");try write(f,"file","new")
        try fm.setAttributes([.modificationDate:Date(timeIntervalSince1970:100)],ofItemAtPath:e.appendingPathComponent("file").path)
        try fm.setAttributes([.modificationDate:Date(timeIntervalSince1970:200)],ofItemAtPath:f.appendingPathComponent("file").path)
        try check(try NativeSynchronization.compare(left:e,right:f).differences[0].direction == .rightToLeft,"Newer right file suggested")
        try check(try NativeSynchronization.compare(left:e,right:f,preferNewer:false).differences[0].direction == .skip,"Newer preference off requires explicit decision")
        let (g,h)=try pair("stale")
        try write(g,"file","before");let stale=try NativeSynchronization.compare(left:g,right:h);try write(g,"file","after!")
        try rejects("Stale source rejects all changes") { _=try NativeSynchronization.apply(stale) }
        try check(!fm.fileExists(atPath:h.appendingPathComponent("file").path),"Stale plan did not write destination")
        let fresh=try NativeSynchronization.compare(left:g,right:h);try write(h,"file","unrelated")
        try rejects("Destination appeared rejects all changes") { _=try NativeSynchronization.apply(fresh) }
        try check(try text(h,"file") == "unrelated","Stale destination preserved")
        try rejects("Incomplete scan never returns a plan") { _=try NativeSynchronization.compare(left:g,right:h,beforeRead:{ url in if url.lastPathComponent == "file" { throw NSError(domain:"Unreadable",code:1) } }) }
        try rejects("Cancelled scan never returns a plan") { _=try NativeSynchronization.compare(left:g,right:h,cancelled:{true}) }
        let (i,j)=try pair("links")
        let outside=base.appendingPathComponent("outside");try fm.createDirectory(at:outside,withIntermediateDirectories:false);try write(outside,"secret","untouched")
        try fm.createSymbolicLink(at:i.appendingPathComponent("link"),withDestinationURL:outside)
        plan=try NativeSynchronization.compare(left:i,right:j)
        try check(plan.differences.count == 1 && plan.differences[0].direction == .skip && !plan.differences[0].allows(.leftToRight),"Symbolic links not followed or copied")
        plan.differences[0].direction = .leftToRight
        try rejects("Forged link action rejected") { _=try NativeSynchronization.apply(plan) }
        try rejects("Symbolic link root rejected") { _=try NativeSynchronization.compare(left:i.appendingPathComponent("link"),right:j) }
        try rejects("Overlapping roots rejected") { _=try NativeSynchronization.compare(left:base,right:j) }
        let (k,l)=try pair("cancel")
        try write(k,"a","a");try write(k,"b","b");plan=try NativeSynchronization.compare(left:k,right:l)
        var stop=false
        let cancelled=try NativeSynchronization.apply(plan,cancelled:{stop},progress:{_,_,_ in stop=true})
        try check(cancelled.cancelled && cancelled.completed == 1,"Cancellation stops remaining work")
        try check(fm.fileExists(atPath:l.appendingPathComponent("a").path) && !fm.fileExists(atPath:l.appendingPathComponent("b").path),"Completed copy remains and pending copy absent")
        let (m,n)=try pair("race")
        try write(m,"a","first");try write(m,"b","second");plan=try NativeSynchronization.compare(left:m,right:n)
        try rejects("Changed source after first commit detected") {
            _=try NativeSynchronization.apply(plan,progress:{done,_,_ in if done == 1 { try? fm.removeItem(at:m.appendingPathComponent("b"));try? fm.createSymbolicLink(at:m.appendingPathComponent("b"),withDestinationURL:outside.appendingPathComponent("secret")) } })
        }
        try check(!fm.fileExists(atPath:n.appendingPathComponent("b").path) && (try text(outside,"secret")) == "untouched","Symlink race does not copy or mutate outside target")
        let (o,p)=try pair("types");try write(o,"item","file");try fm.createDirectory(at:p.appendingPathComponent("item"),withIntermediateDirectories:false)
        plan=try NativeSynchronization.compare(left:o,right:p)
        try check(plan.differences[0].direction == .skip && !plan.differences[0].allows(.leftToRight),"File-directory conflict is non-destructive")
        let (fifoLeft,fifoRight)=try pair("fifo-race")
        try write(fifoLeft,"a","first");try write(fifoLeft,"b","second")
        let fifoPlan=try NativeSynchronization.compare(left:fifoLeft,right:fifoRight)
        let started=Date()
        try rejects("FIFO replacement after first commit rejects without blocking") {
            _=try NativeSynchronization.apply(fifoPlan,progress:{done,_,_ in
                if done == 1 {
                    let path=fifoLeft.appendingPathComponent("b").path
                    _=unlink(path);_ = mkfifo(path,0o600)
                }
            })
        }
        try check(Date().timeIntervalSince(started)<5,"FIFO race returns promptly")
        try check(!fm.fileExists(atPath:fifoRight.appendingPathComponent("b").path),"FIFO replacement not copied")
        let (caseLeft,caseRight)=try pair("case-collision");try write(caseLeft,"Name.txt","left");try write(caseRight,"name.txt","right")
        try rejects("Cross-root case collision rejected before plan") { _=try NativeSynchronization.compare(left:caseLeft,right:caseRight) }
        print("PASS: \(assertions) synchronization assertions")
    }
}
