import Foundation
@main struct Bench {
 static func main(){
  let locale=Locale(identifier:"en_US_POSIX"),zone=TimeZone(secondsFromGMT:0)!,date=Date(timeIntervalSince1970:1704164645)
  var c=CommanderConfiguration();c.sizeFormat = .dynamicOneDecimal
  var checksum=0
  func run(_ name:String,_ f:(Int)->String){let start=Date();for i in 0..<10000{checksum += f(i).utf8.count};print("\(name): \(Date().timeIntervalSince(start)*1000) ms / 10000 values")}
  run("size"){c.sizeString(Int64($0)*145923,locale:locale)}
  run("date"){c.dateString(date.addingTimeInterval(Double($0)),locale:locale,timeZone:zone)}
  print("checksum \(checksum)")
 }
}
