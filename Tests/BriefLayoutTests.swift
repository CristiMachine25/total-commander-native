import AppKit

@main struct BriefLayoutTests {
    static func main() {
        var checks=0
        func check(_ value:Bool,_ reason:String) {checks += 1;precondition(value,reason)}
        check(BriefLayout.rows(height:210,rowHeight:21)==10,"Ten full visible rows")
        check(BriefLayout.rows(height:209,rowHeight:21)==9,"Partial bottom row is excluded")
        check(BriefLayout.rows(height:0,rowHeight:0)==1,"Collapsed viewport retains one safe row")
        check(BriefLayout.columns(count:21,rows:10)==3,"Last partial column exists")
        check(BriefLayout.columns(count:20,rows:10)==2,"Exact column boundary has no extra column")
        check(BriefLayout.index(column:1,row:2,rows:10,count:21)==12,"Column-major index mapping")
        check(BriefLayout.index(column:2,row:1,rows:10,count:21)==nil,"Empty partial-column cell is not selectable")
        check(BriefLayout.index(column:-1,row:0,rows:10,count:21)==nil,"Negative hit-test rejected")
        check(BriefLayout.move(4,key:123,rows:10,count:21)==4,"Left edge does not wrap")
        check(BriefLayout.move(14,key:123,rows:10,count:21)==4,"Left moves by visible row count")
        check(BriefLayout.move(4,key:124,rows:10,count:21)==14,"Right keeps row position")
        check(BriefLayout.move(14,key:124,rows:10,count:21)==20,"Short final column clamps to its last item")
        check(BriefLayout.move(20,key:124,rows:10,count:21)==20,"Right edge does not move backwards")
        check(BriefLayout.move(9,key:125,rows:10,count:21)==10,"Down advances flat entry order across columns")
        check(BriefLayout.move(10,key:126,rows:10,count:21)==9,"Up reverses flat entry order")
        check(BriefLayout.move(0,key:126,rows:10,count:21)==0,"Parent row is the first entry")
        check(BriefLayout.move(12,key:115,rows:10,count:21)==0,"Home selects parent")
        check(BriefLayout.move(12,key:119,rows:10,count:21)==20,"End selects last entry")
        check(BriefLayout.move(12,key:116,rows:10,count:21)==2,"PageUp moves one column")
        check(BriefLayout.move(12,key:121,rows:10,count:21)==20,"PageDown clamps final column")
        check(BriefLayout.move(0,key:124,rows:1,count:0)==0,"Empty model is safe")
        print("Brief layout: \(checks) checks passed")
    }
}
