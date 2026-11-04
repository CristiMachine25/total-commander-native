import Foundation

/// The four choices documented in dlg_display.htm. Locale collation uses macOS,
/// so equivalence to every Windows locale is not claimed.
enum CommanderSortMethod:String,Codable,CaseIterable {
    case naturalAlphabetical,alphabetical,characterCode,naturalCharacterCode
    var title:String {switch self {
    case .naturalAlphabetical:return "Natural: alphabetical and numbers"
    case .alphabetical:return "Alphabetical, considering accents"
    case .characterCode:return "Strict character code"
    case .naturalCharacterCode:return "Natural: character code and numbers"
    }}
    func compare(_ left:String,_ right:String,caseSensitive:Bool=false)->ComparisonResult {
        if caseSensitive {return left.compare(right)}
        switch self {
        case .naturalAlphabetical:return left.localizedStandardCompare(right)
        case .alphabetical:return left.compare(right,options:[.caseInsensitive],range:nil,locale:.current)
        case .characterCode:return Self.lexical(Array(left.uppercased().utf16),Array(right.uppercased().utf16))
        case .naturalCharacterCode:return Self.numericCodeCompare(left.lowercased(),right.lowercased())
        }
    }
    private static func lexical(_ left:[UInt16],_ right:[UInt16])->ComparisonResult {
        if left==right{return .orderedSame};return left.lexicographicallyPrecedes(right) ? .orderedAscending:.orderedDescending
    }
    /// Compare digit runs without conversion to fixed-width integers.
    private static func numericCodeCompare(_ left:String,_ right:String)->ComparisonResult {
        let a=Array(left.utf16),b=Array(right.utf16);var i=0,j=0
        func digit(_ v:UInt16)->Bool{(48...57).contains(v)}
        while i<a.count && j<b.count {
            if digit(a[i]) && digit(b[j]) {
                let ai=i,bj=j
                while i<a.count && digit(a[i]){i+=1};while j<b.count && digit(b[j]){j+=1}
                var az=ai,bz=bj;while az<i && a[az]==48{az+=1};while bz<j && b[bz]==48{bz+=1}
                let x=Array(a[az..<i]),y=Array(b[bz..<j])
                if x.count != y.count{return x.count<y.count ? .orderedAscending:.orderedDescending}
                let value=lexical(x,y);if value != .orderedSame{return value}
            } else {
                if a[i] != b[j]{return a[i]<b[j] ? .orderedAscending:.orderedDescending};i+=1;j+=1
            }
        }
        return i==a.count && j==b.count ? .orderedSame:(i==a.count ? .orderedAscending:.orderedDescending)
    }
}

extension CommanderConfiguration {
    func directoryDisplayName(_ name:String)->String {
        (directoryBrackets ? "["+name+"]":name)+(directoryTrailingSlash ? "/":"")
    }
    func compareDisplayNames(_ left:String,_ right:String)->ComparisonResult {
        sortMethod.compare(left,right,caseSensitive:caseSensitiveSort)
    }
    func directoryCountSuffix(total:Int,selected:Int)->String {
        showDirectoryCount ? "  ·  \(selected) / \(total) dirs":""
    }
}
