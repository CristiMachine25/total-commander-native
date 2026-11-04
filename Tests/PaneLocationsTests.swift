import Foundation

@main struct PaneLocationsTests {
    static var checks=0
    static func check(_ value:@autoclosure () throws -> Bool,_ message:String)throws {checks += 1;if try !value(){throw NSError(domain:"PaneLocationsTests",code:checks,userInfo:[NSLocalizedDescriptionKey:message])}}
    static func rejects(_ message:String,_ work:()throws->Void)throws {var rejected=false;do{try work()}catch{rejected=true};try check(rejected,message)}
    static func main()throws {
        let fm=FileManager.default,base=URL(fileURLWithPath:"/private/tmp").appendingPathComponent("pane-location-tests-"+UUID().uuidString)
        try fm.createDirectory(at:base,withIntermediateDirectories:false);defer{try? fm.removeItem(at:base)}
        func directory(_ name:String)throws->URL {let path=base.appendingPathComponent(name);try fm.createDirectory(at:path,withIntermediateDirectories:true);return path}
        func write(_ name:String,_ text:String)throws->URL {let path=base.appendingPathComponent(name);try Data(text.utf8).write(to:path);return path}
        let folder=try directory("folder"),export=try directory("export")
        _=try write("folder/file.txt","zip contents");_=try write("folder/.hidden","hidden")
        let local=PaneLocation.local(folder),localEntries=try local.list(showHidden:false)
        try check(local.localDirectory==folder && localEntries.count==1 && localEntries[0].url.isFileURL,"Local provider uses real file URLs and hidden filtering")
        try check(local.parent == .local(base),"Local parent navigation")
        try check(PaneLocation.local(URL(fileURLWithPath:"/")).parent==nil,"Filesystem root has no parent")
        let localView=try local.readableMaterialization(localEntries[0])
        try check(try String(contentsOf:localView.url,encoding:.utf8)=="zip contents","Local materialization retains original file")
        let forged=FileEntry(url:base.appendingPathComponent("elsewhere"),name:"elsewhere",isDirectory:false,isSymbolicLink:false,size:0,modified:nil)
        try rejects("Reject local entry outside current directory"){_=try local.readableMaterialization(forged)}
        let archive=base.appendingPathComponent("fixture.zip"),tool=URL(fileURLWithPath:CommandLine.arguments.count>1 ? CommandLine.arguments[1] : "/opt/homebrew/bin/7zz")
        try NativeOperations.pack(sources:[folder],archive:archive,tool:tool)
        var session:ArchiveBrowserSession?=try ArchiveBrowserSession(archive:archive,tool:tool)
        var archiveRoot:PaneLocation? = .archive(session!,path:"")
        let roots=try archiveRoot!.list(showHidden:false)
        try check(roots.count==1 && roots[0].name=="folder" && roots[0].isDirectory && !roots[0].url.isFileURL,"ZIP root lists implicit virtual directories")
        var nested:PaneLocation?=try archiveRoot!.child(roots[0]);let files=try nested!.list(showHidden:false)
        try check(files.count==1 && files[0].name=="file.txt" && files[0].url.scheme=="tc-archive","ZIP subdirectory listing and virtual scheme")
        try check(try nested!.list(showHidden:true).count==2,"Archive hidden files filter")
        try check(nested!.parent==archiveRoot && archiveRoot!.parent == .local(base),"Archive parent returns to host directory at root")
        try check(nested!.displayPath.hasSuffix("fixture.zip!/folder") && nested!.localDirectory==nil,"Virtual path display and no fake local directory")
        try check(try nested!.export(files,to:export)==1 && String(contentsOf:export.appendingPathComponent("file.txt"),encoding:.utf8)=="zip contents","Export from nested ZIP flattens selected leaf into target pane")
        try rejects("Archive export refuses overwrites"){_=try nested!.export(files,to:export)}
        try rejects("Archive folders cannot be mutated"){try nested!.makeDirectory(name:"new")}
        try rejects("Virtual members cannot be sent to local Trash"){try nested!.trash(files)}
        let otherSession=try ArchiveBrowserSession(archive:archive,tool:tool),other=PaneLocation.archive(otherSession,path:"folder")
        try rejects("Reject member from another archive session"){_=try other.readableMaterialization(files[0])}
        var archiveLease:PaneReadableMaterialization?=try nested!.readableMaterialization(files[0])
        let leasedURL=archiveLease!.url
        session=nil;archiveRoot=nil;nested=nil
        try check(fm.fileExists(atPath:leasedURL.path),"Read-only archive lease keeps session backing files alive")
        archiveLease=nil
        try check(!fm.fileExists(atPath:leasedURL.path),"Archive temporary files cleaned after final session lease")
        let mock=try write("mock-curl", """
        #!/bin/sh
        input=$(/bin/cat)
        case "$input" in
          *'request = "MLSD"'*) /usr/bin/printf 'type=file;size=14;modify=20240101000000; remote.txt\\r\\ntype=file;size=1; .hidden\\r\\ntype=dir; folder\\r\\n' ;;
          *'upload-file'*) exit 0 ;;
          *) /usr/bin/printf 'remote payload' ;;
        esac
        """)
        try fm.setAttributes([.posixPermissions:0o700],ofItemAtPath:mock.path)
        var profile=FTPProfile();profile.host="example.invalid";profile.security = .plainFTP
        let client=try FTPClient(profile:profile,password:"test-only",executable:mock),remote=PaneLocation.ftp(client,path:"/")
        let remoteEntries=try remote.list(showHidden:false)
        try check(remoteEntries.map(\.name)==["folder","remote.txt"] && remoteEntries.allSatisfy{!$0.url.isFileURL && $0.url.scheme=="tc-ftp"},"FTP mock listing filters hidden names and uses virtual URLs")
        try check(remote.parent==nil && (try remote.child(remoteEntries[0])).parent==remote,"FTP root and child parent navigation")
        let remoteFile=remoteEntries[1]
        var remoteLease:PaneReadableMaterialization?=try remote.readableMaterialization(remoteFile)
        let remoteURL=remoteLease!.url
        try check(try String(contentsOf:remoteURL,encoding:.utf8)=="remote payload","FTP view downloads into retained private local materialization")
        remoteLease=nil
        try check(!fm.fileExists(atPath:remoteURL.path),"FTP materialization cleans private download on release")
        let remoteExport=try directory("remote-export")
        try check(try remote.export([remoteFile],to:remoteExport)==1 && String(contentsOf:remoteExport.appendingPathComponent("remote.txt"),encoding:.utf8)=="remote payload","FTP export delegates safe file download")
        try check(try remote.upload([localEntries[0].url])==1,"FTP upload delegates local file to remote child")
        let second=PaneLocation.ftp(try FTPClient(profile:profile,password:"other",executable:mock),path:"/")
        try rejects("FTP identities cannot cross connections"){_=try second.readableMaterialization(remoteFile)}
        try rejects("Virtual URI cannot masquerade as local pane"){_=try PaneLocation.local(remoteFile.url).list(showHidden:true)}
        try rejects("Uploading virtual entries is rejected"){_=try remote.upload([remoteFile.url])}
        try rejects("Remote Trash requires explicit permanent-delete path"){try remote.trash([remoteFile])}
        try check(!remote.displayPath.contains("test-only") && !remote.identity.contains("test-only"),"Credentials excluded from display and identity")
        print("PASS: \(checks) pane location assertions")
    }
}
