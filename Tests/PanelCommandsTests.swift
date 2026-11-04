import Foundation
@main struct Test {
 static func main() throws {
  var count=0
  func check(_ value:Bool){precondition(value);count+=1}
  check(PanelFilter.matches(name:"readme",mask:"*.*"))
  check(PanelFilter.matches(name:"HELLO.TXT",mask:"*.txt;*.md|secret*"))
  check(!PanelFilter.matches(name:"secret.txt",mask:"*.txt|secret*"))
  check(!PanelFilter.matches(name:"hello.png",mask:"*.txt;*.md"))
  check(PanelFilter.matches(name:"[a].txt",mask:"[a].txt"))
  check(PanelFilter.matches(name:"a.txt",mask:"?.txt"))
  check(!PanelFilter.matches(name:"ab.txt",mask:"?.txt"))
  check(PanelFilter.matches(name:"other",mask:"|*.tmp"))
  check(!PanelFilter.matches(name:"x.tmp",mask:"|*.tmp"))
  let names=["a.txt","spaced name.txt","日本語"]
  let encoded=try SelectionFile.encode(names)
  check(try SelectionFile.decode(encoded)==Set(names))
  check(try SelectionFile.decode("one\r\ntwo\r\n".data(using:.utf16)!)==Set(["one","two"]))
  do {_=try SelectionFile.encode(["line\nbreak"]);preconditionFailure()}catch{count+=1}
  do {_=try SelectionFile.decode(Data(repeating:0,count:16*1024*1024+1));preconditionFailure()}catch{count+=1}
  print("PASS: \(count) panel filter and selection assertions")
 }
}
