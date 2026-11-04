import Foundation

/// A documented subset of TC's mask language, evaluated without mutating files.
struct RenameMaskOptions {
    enum CaseConversion: String, CaseIterable { case unchanged, uppercase, lowercase, firstLetter, eachWord }
    var nameMask = "[N]"
    var extensionMask = "[E]"
    var counterStart = 1
    var counterStep = 1
    /// nil implements TC's automatic digit width.
    var counterDigits: Int? = 1
    var search = ""
    var replacement = ""
    var regularExpression = false
    var caseSensitiveSearch = false
    var replaceFirstOnly = false
    var includeExtension = true
    var substituteEntireName = false
    var caseConversion: CaseConversion = .unchanged
    var openedAt = Date()
    var changedAt = Date()
    var timeZone = TimeZone.current
    var locale = Locale.current
}

struct RenameMaskInput {
    let name: String
    var parentName = ""
    var grandparentName = ""
    var isDirectory = false
    var size: UInt64 = 0
    var modifiedAt = Date()
}

struct RenameMaskPreview { let source: URL; let destination: URL }

enum RenameMaskError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}

enum RenameMaskEngine {
    private struct State {
        var caseMode: RenameMaskOptions.CaseConversion = .unchanged
        var foldersHaveNoExtension = false
        var dateSource = 1
        var normalize = false
    }
    private static func fail(_ text: String) -> RenameMaskError { .invalid(text) }

    static func render(input: RenameMaskInput, index: Int, total: Int, options: RenameMaskOptions) throws -> String {
        guard index >= 0, total > index else { throw fail("Invalid item position for the rename counter.") }
        guard options.nameMask.count <= 4096, options.extensionMask.count <= 4096,
              options.search.count <= 4096, options.replacement.count <= 4096 else { throw fail("Rename expressions must not exceed 4,096 characters.") }
        try checkDigits(options.counterDigits)
        var state = State()
        var name = try expand(options.nameMask, input: input, index: index, total: total, options: options, state: &state)
        var ext = try expand(options.extensionMask, input: input, index: index, total: total, options: options, state: &state)
        if options.includeExtension {
            name = try replace(join(name, ext), options: options)
            ext = ""
        } else { name = try replace(name, options: options) }
        var result = convert(join(name, ext), mode: options.caseConversion, locale: options.locale)
        if state.normalize { result = result.precomposedStringWithCanonicalMapping }
        guard !result.isEmpty, result != ".", result != "..", !result.contains("/"), !result.contains("\0") else {
            throw fail("The rename result is not a valid filename: \(result)")
        }
        guard !result.contains("\\") else { throw fail("Moving into subfolders with a rename mask is not supported. Use a filename without backslashes.") }
        guard result.utf8.count <= 255 else { throw fail("The rename result exceeds the supported 255-byte filename limit.") }
        return result
    }

    /// All-or-nothing preview validation. Applying remains the existing file operation layer's responsibility.
    static func preview(sources: [URL], options: RenameMaskOptions) throws -> [RenameMaskPreview] {
        guard !sources.isEmpty else { throw fail("Select files or folders to rename.") }
        let fm = FileManager.default
        var items: [RenameMaskPreview] = []
        for (index, source) in sources.enumerated() {
            let parent = source.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
            let source = parent.appendingPathComponent(source.lastPathComponent)
            let attributes = try fm.attributesOfItem(atPath: source.path)
            let input = RenameMaskInput(name: source.lastPathComponent, parentName: parent.lastPathComponent,
                                        grandparentName: parent.deletingLastPathComponent().lastPathComponent,
                                        isDirectory: attributes[.type] as? FileAttributeType == .typeDirectory,
                                        size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
                                        modifiedAt: attributes[.modificationDate] as? Date ?? .distantPast)
            let name = try render(input: input, index: index, total: sources.count, options: options)
            items.append(RenameMaskPreview(source: source, destination: parent.appendingPathComponent(name)))
        }
        func key(_ url: URL) -> String {
            let sensitive = (try? url.deletingLastPathComponent().resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]).volumeSupportsCaseSensitiveNames) ?? false
            let path = url.path.precomposedStringWithCanonicalMapping
            return sensitive ? path : path.lowercased()
        }
        let sourceKeys = Set(items.map { key($0.source) })
        guard sourceKeys.count == items.count else { throw fail("Duplicate rename sources.") }
        var destinationKeys = Set<String>()
        for item in items {
            let destinationKey = key(item.destination)
            guard destinationKeys.insert(destinationKey).inserted else { throw fail("Two items would be renamed to \(item.destination.lastPathComponent).") }
            if (try? fm.attributesOfItem(atPath: item.destination.path)) != nil && !sourceKeys.contains(destinationKey) {
                throw fail("Destination already exists: \(item.destination.path)")
            }
            for other in items where other.source != item.source {
                if other.source.path.hasPrefix(item.source.path + "/") { throw fail("Do not rename a folder and its contents in one operation.") }
            }
        }
        return items
    }

    private static func join(_ name: String, _ ext: String) -> String { ext.isEmpty ? name : name + "." + ext }
    private static func split(_ input: RenameMaskInput, state: State) -> (String, String) {
        if input.isDirectory && state.foldersHaveNoExtension { return (input.name, "") }
        // A leading dot alone marks a macOS hidden name, not an extension.
        guard let dot = input.name.lastIndex(of: "."), dot != input.name.startIndex, input.name.index(after: dot) != input.name.endIndex else { return (input.name, "") }
        return (String(input.name[..<dot]), String(input.name[input.name.index(after: dot)...]))
    }
    private static func convert(_ value: String, mode: RenameMaskOptions.CaseConversion, locale: Locale) -> String {
        switch mode {
        case .unchanged: return value
        case .uppercase: return value.uppercased(with: locale)
        case .lowercase: return value.lowercased(with: locale)
        case .eachWord: return value.capitalized(with: locale)
        case .firstLetter:
            guard let first = value.first else { return value }
            return String(first).uppercased(with: locale) + value.dropFirst().lowercased(with: locale)
        }
    }
    private static func expand(_ mask: String, input: RenameMaskInput, index: Int, total: Int,
                               options: RenameMaskOptions, state: inout State) throws -> String {
        var result = "", cursor = mask.startIndex
        while cursor < mask.endIndex {
            let rest = mask[cursor...]
            if rest.hasPrefix("[[]") || rest.hasPrefix("[]]") {
                result += rest.hasPrefix("[[]") ? "[" : "]"
                cursor = mask.index(cursor, offsetBy: 3); continue
            }
            if mask[cursor] != "[" {
                guard mask[cursor] != "]" else { throw fail("Use []] to insert a closing square bracket.") }
                var end = mask.index(after: cursor)
                while end < mask.endIndex && mask[end] != "[" && mask[end] != "]" { end = mask.index(after: end) }
                result += convert(String(mask[cursor..<end]), mode: state.caseMode, locale: options.locale)
                cursor = end; continue
            }
            guard let end = mask[cursor...].firstIndex(of: "]") else { throw fail("Unclosed rename placeholder.") }
            let token = String(mask[mask.index(after: cursor)..<end]); cursor = mask.index(after: end)
            switch token {
            case "U": state.caseMode = .uppercase; continue
            case "L": state.caseMode = .lowercase; continue
            case "F": state.caseMode = .eachWord; continue
            case "n": state.caseMode = .unchanged; continue
            case "I": state.foldersHaveNoExtension.toggle(); continue
            case "u":
                guard result.isEmpty else { throw fail("[u] must be the first placeholder.") }
                state.normalize = true; continue
            case "T1", "T2", "T3": state.dateSource = Int(token.suffix(1))!; continue
            default: break
            }
            let value: String
            let parts = split(input, state: state)
            if let first = token.first, "NEAPG".contains(first) {
                let base: String
                switch first { case "N": base = parts.0; case "E": base = parts.1; case "A": base = input.name; case "P": base = input.parentName; default: base = input.grandparentName }
                value = try slice(base, specification: String(token.dropFirst()))
            } else if token.hasPrefix("C") {
                value = try counter(String(token.dropFirst()), index: index, total: total, options: options)
            } else if token == "c" || token == "c1" { value = String(total)
            } else if token == "c2" { value = try padded(total, digits: digits(options.counterDigits, start: options.counterStart, step: options.counterStep, total: total))
            } else if token == "c3" { value = String(try counterValue(start: options.counterStart, step: options.counterStep, index: total - 1))
            } else if token == "S" { value = String(input.size)
            } else if !token.isEmpty && token.allSatisfy({ "YyMDdhHimstv".contains($0) }) {
                let date = state.dateSource == 1 ? input.modifiedAt : (state.dateSource == 2 ? options.openedAt : options.changedAt)
                value = try dateText(token, date: date, options: options)
            } else if token == "i1" {
                let date = state.dateSource == 1 ? input.modifiedAt : (state.dateSource == 2 ? options.openedAt : options.changedAt)
                value = String(try dateText("i", date: date, options: options).prefix(1))
            } else { throw fail("Unsupported rename placeholder: [\(token)]") }
            result += convert(value, mode: state.caseMode, locale: options.locale)
        }
        return result
    }

    private static func capture(_ value: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return nil }
        return (1..<match.numberOfRanges).map { i in Range(match.range(at: i), in: value).map { String(value[$0]) } ?? "" }
    }
    private static func slice(_ value: String, specification: String) throws -> String {
        if specification.isEmpty { return value }
        var spec = specification, padding: Character?
        if spec.first == " " { padding = " "; spec.removeFirst() }
        else if spec.first == "0" { padding = "0"; spec.removeFirst() }
        let characters = Array(value)
        func position(_ text: String) throws -> Int {
            guard let n = Int(text), n != 0, (-1_000_000...1_000_000).contains(n) else { throw fail("Invalid substring index: \(specification)") }
            return n > 0 ? n - 1 : characters.count + n
        }
        let start: Int, end: Int, requested: Int
        if let fields = capture(spec, pattern: #"^(-?\d+),(\d+)$"#) {
            start = try position(fields[0]); guard let count = Int(fields[1]), count <= 4096 else { throw fail("Substring length exceeds 4,096 characters.") }
            requested = count; end = start + count - 1
        } else if let fields = capture(spec, pattern: #"^(-?\d+)-(-?\d*)$"#) {
            start = try position(fields[0])
            if fields[1].isEmpty { end = characters.count - 1 }
            else {
                let endText = fields[0].hasPrefix("-") && !fields[1].hasPrefix("-") ? "-" + fields[1] : fields[1]
                end = try position(endText)
            }
            requested = max(0, end - start + 1)
        } else if capture(spec, pattern: #"^(-?\d+)$"#) != nil {
            start = try position(spec); end = start; requested = 1
        } else { throw fail("Unsupported substring specification: \(specification)") }
        guard requested <= 4096 else { throw fail("Substring length exceeds 4,096 characters.") }
        let lower = max(0, start), upper = min(characters.count - 1, end)
        let selected = lower <= upper ? String(characters[lower...upper]) : ""
        if let padding { return String(repeating: String(padding), count: max(0, requested - selected.count)) + selected }
        return selected
    }

    private static func checkDigits(_ digits: Int?) throws {
        if let digits, !(1...32).contains(digits) { throw fail("Counter digits must be 1–32, or automatic.") }
    }
    private static func counterValue(start: Int, step: Int, index: Int) throws -> Int {
        let (increment, productOverflow) = step.multipliedReportingOverflow(by: index)
        let (value, additionOverflow) = start.addingReportingOverflow(increment)
        guard !productOverflow && !additionOverflow else { throw fail("Counter exceeds the supported integer range.") }
        return value
    }
    private static func digits(_ configured: Int?, start: Int, step: Int, total: Int) throws -> Int {
        try checkDigits(configured)
        if let configured { return configured }
        let last = try counterValue(start: start, step: step, index: total - 1)
        return max(String(start).count, String(last).count)
    }
    private static func padded(_ value: Int, digits: Int) -> String {
        let text = String(value), negative = text.hasPrefix("-")
        let body = negative ? String(text.dropFirst()) : text
        return (negative ? "-" : "") + String(repeating: "0", count: max(0, digits - text.count)) + body
    }
    private static func counter(_ specification: String, index: Int, total: Int, options: RenameMaskOptions) throws -> String {
        var start = options.counterStart, step = options.counterStep, width = options.counterDigits, divisor = 1
        if !specification.isEmpty {
            guard let fields = capture(specification, pattern: #"^(-?\d+)?([+-]\d+)?(?:/(\d+))?(?::(\d+|a))?$"#), fields.contains(where: { !$0.isEmpty }) else {
                throw fail("Unsupported counter settings: [C\(specification)]")
            }
            // TC explicitly ignores the Define counter fields when inline settings exist.
            start = 1; step = 1; width = 1
            if !fields[0].isEmpty { guard let n = Int(fields[0]) else { throw fail("Invalid counter start.") }; start = n }
            if !fields[1].isEmpty { guard let n = Int(fields[1]) else { throw fail("Invalid counter step.") }; step = n }
            if !fields[2].isEmpty { guard let n = Int(fields[2]), n > 0 else { throw fail("Counter grouping must be positive.") }; divisor = n }
            if !fields[3].isEmpty { width = fields[3] == "a" ? nil : Int(fields[3]); if fields[3] != "a" && width == nil { throw fail("Invalid counter digit width.") } }
        }
        let fieldWidth = try digits(width, start: start, step: step, total: (total - 1) / divisor + 1)
        return padded(try counterValue(start: start, step: step, index: index / divisor), digits: fieldWidth)
    }
    private static func dateText(_ token: String, date: Date, options: RenameMaskOptions) throws -> String {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = options.timeZone
        let c = calendar.dateComponents([.year,.month,.day,.hour,.minute,.second,.nanosecond], from: date)
        var text = ""
        for ch in token {
            switch ch {
            case "Y": text += padded(c.year ?? 0, digits: 4)
            case "y": text += padded((c.year ?? 0) % 100, digits: 2)
            case "M": text += padded(c.month ?? 0, digits: 2)
            case "D": text += padded(c.day ?? 0, digits: 2)
            case "h": text += padded(c.hour ?? 0, digits: 2)
            case "H": text += padded((c.hour ?? 0) % 12 == 0 ? 12 : (c.hour ?? 0) % 12, digits: 2)
            case "i": text += (c.hour ?? 0) < 12 ? "am" : "pm"
            case "m": text += padded(c.minute ?? 0, digits: 2)
            case "s": text += padded(c.second ?? 0, digits: 2)
            case "v": text += padded((c.nanosecond ?? 0) / 1_000_000, digits: 3)
            case "d", "t":
                let formatter = DateFormatter(); formatter.locale = options.locale; formatter.timeZone = options.timeZone
                formatter.dateStyle = ch == "d" ? .short : .none; formatter.timeStyle = ch == "t" ? .medium : .none
                text += formatter.string(from: date).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
            default: throw fail("Unsupported date placeholder: [\(token)]")
            }
        }
        return text
    }

    private static func replace(_ value: String, options: RenameMaskOptions) throws -> String {
        guard !options.search.isEmpty else { return value }
        if !options.regularExpression {
            guard !options.search.contains(where: { "*?|".contains($0) }) else { throw fail("Wildcard and multiple-pair replacement are not implemented. Use a regular expression for this search.") }
            let compare: String.CompareOptions = options.caseSensitiveSearch ? [.literal] : [.literal, .caseInsensitive]
            guard let range = value.range(of: options.search, options: compare) else { return value }
            if options.substituteEntireName { return options.replacement }
            if options.replaceFirstOnly { return value.replacingCharacters(in: range, with: options.replacement) }
            return value.replacingOccurrences(of: options.search, with: options.replacement, options: compare)
        }
        let regex: NSRegularExpression
        do { regex = try NSRegularExpression(pattern: options.search, options: options.caseSensitiveSearch ? [] : [.caseInsensitive]) }
        catch { throw fail("Invalid or unsupported regular expression: \(error.localizedDescription)") }
        let matches = regex.matches(in: value, range: NSRange(value.startIndex..., in: value))
        guard !matches.isEmpty else { return value }
        let selected = options.replaceFirstOnly || options.substituteEntireName ? Array(matches.prefix(1)) : matches
        var result = value
        for match in selected.reversed() {
            let replacement = try replacementText(options.replacement, match: match, value: value, options: options)
            if options.substituteEntireName { return replacement }
            guard let range = Range(match.range, in: result) else { throw fail("Invalid regular expression match range.") }
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }
    private static func replacementText(_ template: String, match: NSTextCheckingResult, value: String, options: RenameMaskOptions) throws -> String {
        let chars = Array(template); var i = 0, result = ""; var mode: RenameMaskOptions.CaseConversion = .unchanged
        while i < chars.count {
            if chars[i] == "\\" {
                guard i + 1 < chars.count else { throw fail("Incomplete replacement escape.") }
                i += 1
                switch chars[i] {
                case "U": mode = .uppercase
                case "L": mode = .lowercase
                case "F": mode = .eachWord
                case "\\", "$": result += String(chars[i])
                default: throw fail("Unsupported replacement escape: \\\(chars[i])")
                }
                i += 1; continue
            }
            var piece: String
            if chars[i] == "$" {
                i += 1; var number = ""
                while i < chars.count && chars[i].isNumber { number.append(chars[i]); i += 1 }
                guard let group = Int(number), group < match.numberOfRanges else { throw fail("Replacement references an unavailable capture group: $\(number)") }
                piece = Range(match.range(at: group), in: value).map { String(value[$0]) } ?? ""
            } else {
                let start = i
                while i < chars.count && chars[i] != "$" && chars[i] != "\\" { i += 1 }
                piece = String(chars[start..<i])
            }
            result += convert(piece, mode: mode, locale: options.locale)
        }
        return result
    }
}
