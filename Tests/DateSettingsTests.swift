import Foundation
@main struct DateSettingsTests {
    static func main()throws {
        var count=0;func check(_ value:Bool,_ message:String){count += 1;precondition(value,message)}
        let date=Date(timeIntervalSince1970:1735787106),locale=Locale(identifier:"en_US_POSIX"),zone=TimeZone(secondsFromGMT:0)!
        var c=CommanderConfiguration();c.dateOrder = .yearFirst
        let initial=CommanderDateFormatting.string(date,configuration:c,locale:locale,timeZone:zone)
        check(initial=="2025-01-02 03:05:06","Default ISO date/time unchanged")
        c.dateSeparator="/";c.timeSeparator="."
        check(CommanderDateFormatting.string(date,configuration:c,locale:locale,timeZone:zone)=="2025/01/02 03.05.06","Independent custom separators")
        c.use12HourTime=true;c.showSeconds=false
        let afternoon=date.addingTimeInterval(12*3600)
        check(CommanderDateFormatting.string(afternoon,configuration:c,locale:locale,timeZone:zone)=="2025/01/02 03.05 PM","12-hour time and period")
        c.showCentury=false;c.dateOrder = .dayFirst
        check(CommanderDateFormatting.string(afternoon,configuration:c,locale:locale,timeZone:zone)=="02/01/25 03.05 PM","Date ordering and century preserved")
        c.dateSeparator="x";c.timeSeparator="H"
        check(CommanderDateFormatting.string(afternoon,configuration:c,locale:locale,timeZone:zone)=="02x01x25 03H05 PM","ICU pattern letters treated as literals")
        c.dateSeparator="'";c.timeSeparator=":"
        check(CommanderDateFormatting.string(afternoon,configuration:c,locale:locale,timeZone:zone)=="02'01'25 03:05 PM","Quote separator escaped")
        c=CommanderConfiguration();c.dateOrder = .system
        let expected=DateFormatter();expected.locale=locale;expected.timeZone=zone;expected.dateStyle = .short;expected.timeStyle = .medium;expected.dateFormat=expected.dateFormat.replacingOccurrences(of:"y+",with:"yyyy",options:.regularExpression)
        check(CommanderDateFormatting.string(date,configuration:c,locale:locale,timeZone:zone)==expected.string(from:date),"Unmodified system locale formatting unchanged")
        c.dateSeparator="-";c.timeSeparator=".";c.use12HourTime=true
        check(CommanderDateFormatting.string(afternoon,configuration:c,locale:locale,timeZone:zone)=="01-02-2025 03.05.06 PM","System date order with separator override")
        c=CommanderConfiguration();c.dateOrder = .yearFirst
        check(CommanderDateFormatting.string(date,configuration:c,locale:locale,timeZone:zone)==initial,"Cache isolates previous custom formats")
        print("PASS: \(count) date settings assertions")
    }
}
