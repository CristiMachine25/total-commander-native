import AppKit
@main struct FileListComparisonTests {
static func main() {
 var count=0
 func check(_ value:Bool,_ message:String) {count += 1;precondition(value,message)}
 func item(_ id:Int,_ name:String,_ time:TimeInterval?,_ directory:Bool=false)->FileListComparison.Item {.init(id:id,name:name,directory:directory,modified:time.map{Date(timeIntervalSince1970:$0)})}
 let l=[item(0,"newer",20),item(1,"older",10),item(2,"equal",10),item(3,"left-only",nil),item(4,"folder",10,true),item(5,"unknown",nil)]
 let r=[item(0,"NEWER",10),item(1,"older",20),item(2,"equal",10),item(3,"right-only",nil),item(4,"unknown",10)]
 let result=FileListComparison.compare(l,r)
 check(result.left == [0,3],"Only newer and missing files marked left")
 check(result.right == [1,3],"Only newer and missing files marked right")
 check(result.unresolved == 1,"Unknown matched timestamp not invented")
 check(!result.left.contains(4),"Directories excluded")
 check(!result.left.contains(2) && !result.right.contains(2),"Equal dates unmarked regardless of byte differences")
 let collision=FileListComparison.compare([item(0,"a",30),item(1,"A",40)],[item(0,"a",10)])
 check(collision.left.isEmpty && collision.right.isEmpty && collision.unresolved == 1,"Case collision never arbitrarily matched")
 let collisionType=FileListComparison.compare([item(0,"a",30)],[item(0,"a",10,true)])
 check(collisionType.left.isEmpty && collisionType.right.isEmpty,"File-directory collision not treated as missing file")
 let empty=FileListComparison.compare([],[])
 check(empty.left.isEmpty && empty.right.isEmpty,"Empty lists")
 print("File-list comparison: \(count) checks passed")
}}
