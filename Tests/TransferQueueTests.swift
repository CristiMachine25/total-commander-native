import Foundation
import Darwin

@main struct TransferQueueTests {
    static var count = 0
    static let fm = FileManager.default
    static func check(_ value: @autoclosure () throws -> Bool, _ message:String) throws {
        count += 1
        if try !value() { throw NSError(domain:"TransferTests",code:count,userInfo:[NSLocalizedDescriptionKey:message]) }
    }
    static func write(_ value:String,_ url:URL) throws { try Data(value.utf8).write(to:url) }
    static func read(_ url:URL) throws -> String { try String(contentsOf:url,encoding:.utf8) }
    static func main() throws {
        let root = URL(fileURLWithPath:"/private/tmp").appendingPathComponent("transfer-tests-" + UUID().uuidString)
        try fm.createDirectory(at:root,withIntermediateDirectories:false)
        defer { try? fm.removeItem(at:root) }
        func directory(_ name:String) throws -> URL { let url=root.appendingPathComponent(name);try fm.createDirectory(at:url,withIntermediateDirectories:true);return url }
        let source = try directory("source"), destination = try directory("destination")
        let file=source.appendingPathComponent("file.txt"),target=destination.appendingPathComponent("file.txt")
        try write("new",file);try write("old",target)
        var result=NativeTransferEngine(move:false,policy:.skip).run(sources:[file],destination:destination)
        try check(result.errors.isEmpty && result.progress.skippedItems==1 && read(target)=="old","Skip preserves existing file")
        result=NativeTransferEngine(move:false,policy:.rename).run(sources:[file],destination:destination)
        try check(result.errors.isEmpty && read(destination.appendingPathComponent("file (2).txt"))=="new" && read(target)=="old","Keep both chooses new leaf")
        result=NativeTransferEngine(move:false,policy:.replace).run(sources:[file],destination:destination)
        try check(result.errors.isEmpty && read(target)=="new" && read(file)=="new","Replace copies without removing source")
        try write("third",file)
        var conflicts=0
        result=NativeTransferEngine(move:false,policy:.ask,resolve:{ _ in conflicts += 1;return .skip }).run(sources:[file],destination:destination)
        try check(conflicts==1 && result.progress.skippedItems==1 && read(target)=="new","Ask invokes resolver and respects skip")
        result=NativeTransferEngine(move:false,policy:.ask).run(sources:[file],destination:destination)
        try check(result.cancelled && read(target)=="new","Ask without resolver cancels rather than overwrites")
        let folder=source.appendingPathComponent("folder"),merge=destination.appendingPathComponent("folder")
        try fm.createDirectory(at:folder,withIntermediateDirectories:false);try fm.createDirectory(at:merge,withIntermediateDirectories:false)
        try write("incoming",folder.appendingPathComponent("shared"));try write("new child",folder.appendingPathComponent("new"))
        try write("existing",merge.appendingPathComponent("shared"));try write("keep",merge.appendingPathComponent("extra"))
        result=NativeTransferEngine(move:false,policy:.skip).run(sources:[folder],destination:destination)
        try check(result.errors.isEmpty && read(merge.appendingPathComponent("new"))=="new child","Merge copies missing child")
        try check(try read(merge.appendingPathComponent("shared"))=="existing" && read(merge.appendingPathComponent("extra"))=="keep","Merge keeps collisions and unrelated children")
        result=NativeTransferEngine(move:false,policy:.replace).run(sources:[folder],destination:destination)
        try check(result.errors.isEmpty && read(merge.appendingPathComponent("shared"))=="incoming" && read(merge.appendingPathComponent("extra"))=="keep","Replace policy merges folders without deleting extras")
        let broken=source.appendingPathComponent("broken")
        try fm.createSymbolicLink(atPath:broken.path,withDestinationPath:"missing-target")
        result=NativeTransferEngine(move:false,policy:.skip).run(sources:[broken],destination:destination)
        try check(result.errors.isEmpty && fm.destinationOfSymbolicLink(atPath:destination.appendingPathComponent("broken").path)=="missing-target","Broken symlink preserved without traversal")
        let victim=root.appendingPathComponent("victim");try write("untouched",victim)
        let linkTarget=destination.appendingPathComponent("linked"),linkSource=source.appendingPathComponent("linked")
        try fm.createSymbolicLink(at:linkTarget,withDestinationURL:victim);try write("replacement",linkSource)
        result=NativeTransferEngine(move:false,policy:.replace).run(sources:[linkSource],destination:destination)
        try check(result.errors.isEmpty && read(victim)=="untouched" && read(linkTarget)=="replacement","Replacing destination symlink does not modify target")
        result=NativeTransferEngine(move:false,policy:.replace).run(sources:[file],destination:source)
        try check(!result.errors.isEmpty && read(file)=="third","Self copy rejected before mutation")
        let inside=folder.appendingPathComponent("inside");try fm.createDirectory(at:inside,withIntermediateDirectories:false)
        result=NativeTransferEngine(move:false,policy:.replace).run(sources:[folder],destination:inside)
        try check(!result.errors.isEmpty,"Descendant destination rejected")
        let fifo=source.appendingPathComponent("fifo");try check(mkfifo(fifo.path,0o600)==0,"FIFO fixture")
        result=NativeTransferEngine(move:false,policy:.skip).run(sources:[fifo],destination:destination)
        try check(!result.errors.isEmpty && !fm.fileExists(atPath:destination.appendingPathComponent("fifo").path),"Special files rejected without blocking")
        let moveFile=source.appendingPathComponent("move.txt");try write("move me",moveFile)
        result=NativeTransferEngine(move:true,policy:.skip).run(sources:[moveFile],destination:destination)
        try check(result.errors.isEmpty && !fm.fileExists(atPath:moveFile.path) && read(destination.appendingPathComponent("move.txt"))=="move me","Move commits then removes source")
        let cancelDest=try directory("cancel"),a=source.appendingPathComponent("a"),b=source.appendingPathComponent("b")
        try write("A",a);try write("B",b)
        let cancellation=TransferCancellation()
        result=NativeTransferEngine(move:true,policy:.skip,cancellation:cancellation,update:{ value in if value.completedItems==1 { cancellation.cancel() } }).run(sources:[a,b],destination:cancelDest)
        try check(result.cancelled && result.progress.completedItems==1,"Cancellation reports partial progress")
        try check(!fm.fileExists(atPath:a.path) && read(cancelDest.appendingPathComponent("a"))=="A" && read(b)=="B" && !fm.fileExists(atPath:cancelDest.appendingPathComponent("b").path),"Cancelled move retains unfinished source and committed first item")
        let cancelledBefore=TransferCancellation();cancelledBefore.cancel()
        result=NativeTransferEngine(move:true,policy:.replace,cancellation:cancelledBefore).run(sources:[b],destination:cancelDest)
        try check(result.cancelled && read(b)=="B","Pre-cancelled transfer changes nothing")
        let typeFolder=source.appendingPathComponent("type");try fm.createDirectory(at:typeFolder,withIntermediateDirectories:false)
        try write("child",typeFolder.appendingPathComponent("child"));try write("old file",destination.appendingPathComponent("type"))
        result=NativeTransferEngine(move:true,policy:.replace).run(sources:[typeFolder],destination:destination)
        try check(result.errors.isEmpty && read(destination.appendingPathComponent("type/child"))=="child" && !fm.fileExists(atPath:typeFolder.path),"Move directory replaces conflicting file after staged copy")
        let queuedA=try directory("queued-a"),queuedB=try directory("queued-b"),queuedDest=try directory("queued-dest")
        let qa=queuedA.appendingPathComponent("same"),qb=queuedB.appendingPathComponent("same")
        try write("one",qa);try write("two",qb)
        let queue=NativeTransferQueue(),callbacks=DispatchQueue(label:"test.transfer.callbacks"),done=DispatchSemaphore(value:0)
        var results:[TransferResult]=[]
        queue.enqueue(sources:[qa],destination:queuedDest,move:false,policy:.replace,callbackQueue:callbacks,completion:{results.append($0);done.signal()})
        queue.enqueue(sources:[qb],destination:queuedDest,move:false,policy:.replace,callbackQueue:callbacks,completion:{results.append($0);done.signal()})
        try check(done.wait(timeout:.now()+10) == .success && done.wait(timeout:.now()+10) == .success,"Asynchronous queue completes both jobs")
        try check(results.count==2 && results.allSatisfy{$0.errors.isEmpty} && read(queuedDest.appendingPathComponent("same"))=="two","Queue serializes conflicting transfers in submission order")
        try check(!queue.hasPendingJobs,"Queue settles pending state")
        try check(try fm.contentsOfDirectory(at:destination,includingPropertiesForKeys:nil).allSatisfy{!$0.lastPathComponent.hasPrefix(".transfer-")},"No staged files remain after success")
        let linkedFolder = source.appendingPathComponent("linked-folder"), outside = try directory("outside")
        try fm.createDirectory(at:linkedFolder,withIntermediateDirectories:false)
        try write("inside",linkedFolder.appendingPathComponent("child"));try write("outside-safe",outside.appendingPathComponent("safe"))
        try fm.createSymbolicLink(at:destination.appendingPathComponent("linked-folder"),withDestinationURL:outside)
        result=NativeTransferEngine(move:false,policy:.skip).run(sources:[linkedFolder],destination:destination)
        try check(result.progress.skippedItems==1 && !fm.fileExists(atPath:outside.appendingPathComponent("child").path),"Directory merge never follows destination symlink")
        result=NativeTransferEngine(move:false,policy:.replace).run(sources:[linkedFolder],destination:destination)
        try check(result.errors.isEmpty && read(outside.appendingPathComponent("safe"))=="outside-safe" && read(destination.appendingPathComponent("linked-folder/child"))=="inside","Directory replacement replaces link itself")
        let largeSource=source.appendingPathComponent("large"),largeTarget=destination.appendingPathComponent("large")
        fm.createFile(atPath:largeSource.path,contents:nil)
        let largeHandle=try FileHandle(forWritingTo:largeSource);try largeHandle.truncate(atOffset:134_217_728);try largeHandle.close()
        try write("original",largeTarget)
        let midCancel=TransferCancellation(),watchDone=DispatchSemaphore(value:0)
        DispatchQueue.global().async {
            let deadline=Date().addingTimeInterval(5)
            while Date()<deadline {
                if let children=try? fm.contentsOfDirectory(at:destination,includingPropertiesForKeys:nil),children.contains(where:{$0.lastPathComponent.hasPrefix(".transfer-")}) { midCancel.cancel();break }
                Thread.sleep(forTimeInterval:0.001)
            }
            watchDone.signal()
        }
        result=NativeTransferEngine(move:true,policy:.replace,cancellation:midCancel).run(sources:[largeSource],destination:destination)
        _=watchDone.wait(timeout:.now()+6)
        try check(result.cancelled && read(largeTarget)=="original" && fm.fileExists(atPath:largeSource.path),"Mid-copy cancellation preserves original destination and source")
        try check(try fm.contentsOfDirectory(at:destination,includingPropertiesForKeys:nil).allSatisfy{!$0.lastPathComponent.hasPrefix(".transfer-")},"Mid-copy cancellation removes private stage")
        let blockedQueue=NativeTransferQueue(),conflictReady=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0),blockedDone=DispatchSemaphore(value:0)
        var blockedResults:[TransferResult]=[]
        blockedQueue.enqueue(sources:[qa],destination:queuedDest,move:false,policy:.ask,resolve:{_ in conflictReady.signal();_ = release.wait(timeout:.now()+5);return .skip},callbackQueue:callbacks,completion:{blockedResults.append($0);blockedDone.signal()})
        try check(conflictReady.wait(timeout:.now()+5) == .success,"Queue fixture reached first conflict")
        let pending=blockedQueue.enqueue(sources:[qb],destination:queuedDest,move:true,policy:.replace,callbackQueue:callbacks,completion:{blockedResults.append($0);blockedDone.signal()})
        blockedQueue.cancel(pending);release.signal()
        try check(blockedDone.wait(timeout:.now()+5) == .success && blockedDone.wait(timeout:.now()+5) == .success,"Cancelled pending job completes callback")
        try check(blockedResults.count==2 && blockedResults[1].cancelled && read(qb)=="two" && read(queuedDest.appendingPathComponent("same"))=="two","Cancelled queued move leaves both locations intact")
        let swapRoot=try directory("swap-root"), escaped=try directory("escaped"), movedRoot=root.appendingPathComponent("swap-root-original")
        let swapFile=source.appendingPathComponent("swap-file");try write("safe bytes",swapFile)
        var didSwap=false
        result=NativeTransferEngine(move:false,policy:.replace,update:{ value in
            if value.state == "Copying" && !didSwap {
                didSwap=true
                try! fm.moveItem(at:swapRoot,to:movedRoot)
                try! fm.createSymbolicLink(at:swapRoot,withDestinationURL:escaped)
            }
        }).run(sources:[swapFile],destination:swapRoot)
        try check(didSwap && !result.errors.isEmpty && !fm.fileExists(atPath:escaped.appendingPathComponent("swap-file").path),"Destination root swap to symlink is rejected before writing outside")
        let midRoot=try directory("mid-swap-root"),midMoved=root.appendingPathComponent("mid-swap-original")
        var midSwapped=false
        result=NativeTransferEngine(move:true,policy:.replace,update:{ value in
            if value.state == "Moving" && !midSwapped {
                if value.copiedBytes > 0 {
                    midSwapped=true
                    try! fm.moveItem(at:midRoot,to:midMoved)
                    try! fm.createSymbolicLink(at:midRoot,withDestinationURL:escaped)
                } else { Thread.sleep(forTimeInterval:0.12) }
            }
        }).run(sources:[largeSource],destination:midRoot)
        try check(midSwapped && !result.errors.isEmpty && fm.fileExists(atPath:largeSource.path) && !fm.fileExists(atPath:escaped.appendingPathComponent("large").path),"Mid-copy parent swap refuses commit and retains move source")
        try check(try fm.contentsOfDirectory(at:midMoved,includingPropertiesForKeys:nil).isEmpty,"Private stage cleaned through original parent FD after ancestor swap")
        let mergeSource=try directory("nested-swap-source/branch"),mergeDestination=try directory("nested-swap-destination"),mergeParent=mergeDestination.appendingPathComponent("branch")
        try fm.createDirectory(at:mergeParent,withIntermediateDirectories:false)
        try write("new",mergeSource.appendingPathComponent("child"));try write("old",mergeParent.appendingPathComponent("child"));try write("outside",escaped.appendingPathComponent("child"))
        result=NativeTransferEngine(move:false,policy:.ask,resolve:{_ in
            try! fm.moveItem(at:mergeParent,to:mergeDestination.appendingPathComponent("original-branch"))
            try! fm.createSymbolicLink(at:mergeParent,withDestinationURL:escaped)
            return .replace
        }).run(sources:[mergeSource],destination:mergeDestination)
        try check(!result.errors.isEmpty && read(escaped.appendingPathComponent("child"))=="outside" && read(mergeDestination.appendingPathComponent("original-branch/child"))=="old","Nested parent swapped during collision prompt refuses outside write and preserves existing item")
        let fifoSwap=source.appendingPathComponent("fifo-swap"),fifoTarget=destination.appendingPathComponent("fifo-swap")
        try write("source",fifoSwap);try write("original",fifoTarget)
        result=NativeTransferEngine(move:false,policy:.ask,resolve:{_ in
            try! fm.removeItem(at:fifoSwap);precondition(mkfifo(fifoSwap.path,0o600)==0);return .replace
        }).run(sources:[fifoSwap],destination:destination)
        try check(!result.errors.isEmpty && read(fifoTarget)=="original","Source changed to FIFO in conflict prompt is rejected without blocking or replacing destination")
        // Copy settings operate on private staged data and cannot bypass safe commit.
        let settingsSource=try directory("settings-source"),settingsDest=try directory("settings-dest")
        let settingsFile=settingsSource.appendingPathComponent("configured")
        try write("verified contents",settingsFile)
        let oldDate=Date(timeIntervalSince1970:946684800)
        try fm.setAttributes([.modificationDate:oldDate,.posixPermissions:0o751],ofItemAtPath:settingsFile.path)
        var options=NativeTransferOptions();options.verifyAfterCopy=true;options.bufferSizeKB=64
        var verificationObserved=false
        result=NativeTransferEngine(move:false,policy:.replace,options:options,update:{if $0.state=="Verifying"{verificationObserved=true}}).run(sources:[settingsFile],destination:settingsDest)
        let settingsTarget=settingsDest.appendingPathComponent("configured")
        let attrs=try fm.attributesOfItem(atPath:settingsTarget.path)
        try check(result.errors.isEmpty && verificationObserved && read(settingsTarget)=="verified contents","Verification reads the staged copy and commits matching bytes")
        try check((attrs[.posixPermissions] as? NSNumber)?.intValue==0o751,"Preserve permissions retains source mode")
        try check(abs((attrs[.modificationDate] as! Date).timeIntervalSince(oldDate))<1,"Preserve file dates retains modification date")
        options.preserveFileDates=false;options.preservePermissions=false
        result=NativeTransferEngine(move:false,policy:.replace,options:options).run(sources:[settingsFile],destination:settingsDest)
        let fresh=try fm.attributesOfItem(atPath:settingsTarget.path)
        try check(result.errors.isEmpty && (fresh[.modificationDate] as! Date).timeIntervalSince(oldDate)>60,"Disabled file dates gives the copied file a new modification date")
        try check((fresh[.posixPermissions] as? NSNumber)?.intValue==0o600,"Disabled permissions retains private new-file mode instead of source executable bits")
        let datedFolder=settingsSource.appendingPathComponent("dated");try fm.createDirectory(at:datedFolder,withIntermediateDirectories:false)
        try write("child",datedFolder.appendingPathComponent("child"));try fm.setAttributes([.modificationDate:oldDate],ofItemAtPath:datedFolder.path)
        result=NativeTransferEngine(move:false,policy:.replace,options:NativeTransferOptions()).run(sources:[datedFolder],destination:settingsDest)
        try check(result.errors.isEmpty && abs((try fm.attributesOfItem(atPath:settingsDest.appendingPathComponent("dated").path)[.modificationDate] as! Date).timeIntervalSince(oldDate))<1,"New directory timestamps preserved by default")
        let noDates=try directory("no-directory-dates");options.preserveDirectoryDates=false
        result=NativeTransferEngine(move:false,policy:.replace,options:options).run(sources:[datedFolder],destination:noDates)
        try check(result.errors.isEmpty && (try fm.attributesOfItem(atPath:noDates.appendingPathComponent("dated").path)[.modificationDate] as! Date).timeIntervalSince(oldDate)>60,"Directory timestamp option is effective")
        try write("old destination",settingsTarget)
        var corrupted=false
        result=NativeTransferEngine(move:true,policy:.replace,options:options,update:{value in
            if value.state=="Verifying",!corrupted {
                corrupted=true
                let stage=try! fm.contentsOfDirectory(at:settingsDest,includingPropertiesForKeys:nil).first{$0.lastPathComponent.hasPrefix(".transfer-")}!
                try! write("corrupted",stage)
            }
        }).run(sources:[settingsFile],destination:settingsDest)
        try check(corrupted && !result.errors.isEmpty && read(settingsTarget)=="old destination" && read(settingsFile)=="verified contents","Verification failure preserves source and old destination on move")
        try check(try fm.contentsOfDirectory(at:settingsDest,includingPropertiesForKeys:nil).allSatisfy{!$0.lastPathComponent.hasPrefix(".transfer-")},"Failed verification cleans private staged file")
        let cancelVerify=TransferCancellation()
        result=NativeTransferEngine(move:true,policy:.replace,options:options,cancellation:cancelVerify,update:{if $0.state=="Verifying"{cancelVerify.cancel()}}).run(sources:[settingsFile],destination:settingsDest)
        try check(result.cancelled && read(settingsFile)=="verified contents" && read(settingsTarget)=="old destination","Cancel verification retains source and existing destination")
        try check(NativeTransferOptions(bufferSizeKB:1).bufferSize==65536 && NativeTransferOptions(bufferSizeKB:Int.max).bufferSize==16777216,"Transfer buffer clamps safely before allocation")
        print("PASS: \(count) transfer assertions")
    }
}
