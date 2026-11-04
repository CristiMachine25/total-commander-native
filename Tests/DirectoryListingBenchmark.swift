import Foundation
@main struct Bench {
 static func main()throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1])
  for count in [1000,10000] {
   let folder=root.appendingPathComponent(String(count)),start=ProcessInfo.processInfo.systemUptime
   var checksum=0
   for _ in 0..<3 {checksum += try FileService.list(folder,showHidden:false).count}
   print("\(count) entries, mean of three listings: \((ProcessInfo.processInfo.systemUptime-start)*1000/3) ms; checksum \(checksum)")
  }
 }
}
