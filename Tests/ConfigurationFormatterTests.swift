import Foundation

/// Regression coverage for formatter reuse: keys must not leak precision, locale,
/// time zone or date options between calls, including calls on worker threads.
@main struct ConfigurationFormatterTests {
    static func main()throws {
        let date=Date(timeIntervalSince1970:1_704_164_645)
        let utc=TimeZone(secondsFromGMT:0)!,offset=TimeZone(secondsFromGMT:7200)!
        let en=Locale(identifier:"en_US_POSIX"),de=Locale(identifier:"de_DE")
        var first=CommanderConfiguration();first.sizeFormat = .dynamicOneDecimal;first.dateOrder = .yearFirst
        var second=first;second.sizeFormat = .dynamicTwoDecimals;second.dateOrder = .dayFirst;second.showCentury=false;second.showSeconds=false
        let lock=NSLock();var failures=[String]()
        DispatchQueue.concurrentPerform(iterations:200){index in
            var errors=[String]()
            if first.sizeString(1_310_720,locale:en) != "1.2 M"{errors.append("one-decimal precision")}
            if second.sizeString(1_310_720,locale:de) != "1,25 M"{errors.append("German two-decimal precision")}
            if first.dateString(date,locale:en,timeZone:utc) != "2024-01-02 03:04:05"{errors.append("UTC/long year/seconds")}
            if second.dateString(date,locale:de,timeZone:offset) != "02.01.24 05:04"{errors.append("offset/short year/no seconds")}
            var integer=first;integer.sizeFormat = .bytes
            if integer.sizeString(Int64.max,locale:en) != "9,223,372,036,854,775,807"{errors.append("integer precision")}
            if !errors.isEmpty{lock.lock();failures.append("\(index): "+errors.joined(separator:", "));lock.unlock()}
        }
        // Exercise eviction on one thread, then revisit an original key.
        for identifier in Locale.availableIdentifiers.prefix(80){_ = first.sizeString(1024,locale:Locale(identifier:identifier));_ = second.dateString(date,locale:Locale(identifier:identifier),timeZone:utc)}
        if first.sizeString(1_310_720,locale:en) != "1.2 M" || first.dateString(date,locale:en,timeZone:utc) != "2024-01-02 03:04:05"{failures.append("eviction changed output")}
        guard failures.isEmpty else{throw NSError(domain:"ConfigurationFormatterTests",code:1,userInfo:[NSLocalizedDescriptionKey:failures.prefix(5).joined(separator:"\n")])}
        print("PASS: 1,001 formatter isolation assertions across threads, locales, precision, time zones and eviction")
    }
}
