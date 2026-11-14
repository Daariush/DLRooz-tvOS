import Foundation

/// Small, predictable wrapper around NSRegularExpression (patterns are compile-time constants).
struct Rx: @unchecked Sendable {
    let re: NSRegularExpression

    init(_ pattern: String, dotAll: Bool = false, caseInsensitive: Bool = false) {
        var opts: NSRegularExpression.Options = []
        if dotAll { opts.insert(.dotMatchesLineSeparators) }
        if caseInsensitive { opts.insert(.caseInsensitive) }
        // swiftlint:disable:next force_try
        re = try! NSRegularExpression(pattern: pattern, options: opts)
    }

    /// Capture groups of the first match (index 0 is the whole match); a group that did not take part is nil.
    func firstMatch(in s: String) -> [String?]? {
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return Rx.groups(m, ns)
    }

    func allMatches(in s: String) -> [[String?]] {
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { Rx.groups($0, ns) }
    }

    func matches(_ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }

    func replace(in s: String, with template: String) -> String {
        re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: template)
    }

    private static func groups(_ m: NSTextCheckingResult, _ ns: NSString) -> [String?] {
        (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfBlank: String? { trimmed.isEmpty ? nil : self }

    /// Text after the first occurrence of `sep`; the whole string when it does not occur.
    func after(_ sep: String) -> String {
        guard let r = range(of: sep) else { return self }
        return String(self[r.upperBound...])
    }

    func before(_ sep: String) -> String {
        guard let r = range(of: sep) else { return self }
        return String(self[..<r.lowerBound])
    }
}
