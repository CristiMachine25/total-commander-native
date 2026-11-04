import Foundation
@main struct Test {
 static func main(){
  var count=0
  func check(_ actual:Bool,_ expected:Bool=true){precondition(actual==expected);count+=1}
  check(QuickSearchMatcher.matches("Readme.txt",query:"read",beginning:true,ending:false))
  check(QuickSearchMatcher.matches("Readme.txt",query:"me",beginning:true,ending:false),false)
  check(QuickSearchMatcher.matches("Readme.txt",query:"me",beginning:false,ending:false))
  check(QuickSearchMatcher.matches("Readme.txt",query:"read.",beginning:true,ending:true),false)
  check(QuickSearchMatcher.matches("Readme.txt",query:"readme.",beginning:true,ending:true))
  check(QuickSearchMatcher.matches("Readme.txt",query:"readme.t",beginning:true,ending:true))
  check(QuickSearchMatcher.matches("Readme.txt",query:"readme.z",beginning:true,ending:true),false)
  check(QuickSearchMatcher.matches("Readme.txt",query:"me.t",beginning:false,ending:true))
  check(QuickSearchMatcher.matches("Readme",query:"readme.",beginning:true,ending:true))
  check(QuickSearchMatcher.matches("Café.txt",query:"cafe",beginning:true,ending:false))
  check(QuickSearchMatcher.matches("Readme.txt",query:"",beginning:true,ending:true))
  print("PASS: \(count) quick search assertions")
 }
}
