import Foundation

/// One subtitle cue; `text` has its lines joined with "\n" and formatting tags removed.
struct SubCue: Hashable, Sendable {
    let start: Double
    let end: Double
    let text: String
}

/// Lenient SRT / WebVTT parser: malformed blocks are skipped, anything else yields no cues.
enum SubtitleParser {
    private static let timing = Rx(#"(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})\s*-->\s*(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})"#)
    /// WebVTT allows "MM:SS.mmm" without hours.
    private static let shortTiming = Rx(#"^(\d{2}):(\d{2})[.,](\d{1,3})\s*-->\s*(\d{2}):(\d{2})[.,](\d{1,3})"#)
    /// HTML-style tags (<i>, </font>, <v Name>, <c.yellow>), VTT inline timestamps and ASS overrides.
    /// Anything else between angle brackets is dialogue (e.g. "<< Previously >>") and is kept.
    private static let tags = Rx(#"</?[A-Za-z][^>]*>|<\d{1,2}:\d{2}[^>]*>|\{\\[^}]*\}"#)

    static func parse(_ text: String) -> [SubCue] {
        let lines = text.replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\r\n", with: "\n")
            .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var cues: [SubCue] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            i += 1
            guard let span = times(line) else { continue }
            let (start, end) = span
            var body: [String] = []
            while i < lines.count, times(lines[i]) == nil {
                if lines[i].trimmed.isEmpty {
                    // A blank line usually ends the cue, but some files (often English ones converted
                    // from broadcast captions) put a blank line between two speakers inside one cue.
                    // The text after it belongs to this cue unless a new cue starts there.
                    guard let next = nextNonBlank(lines, from: i), !startsCue(lines, at: next) else { break }
                    i = next
                    continue
                }
                body.append(tags.replace(in: lines[i], with: "").trimmed)
                i += 1
            }
            // Block without a blank separator: a trailing bare number is the next block's index.
            if i < lines.count, !lines[i].trimmed.isEmpty, let last = body.last, !last.isEmpty, last.allSatisfy(\.isNumber) {
                body.removeLast()
            }
            let joined = body.filter { !$0.isEmpty }.joined(separator: "\n")
            if !joined.isEmpty { cues.append(SubCue(start: start, end: end, text: joined)) }
        }
        return cues.sorted { $0.start < $1.start }
    }

    private static func nextNonBlank(_ lines: [String], from: Int) -> Int? {
        var j = from
        while j < lines.count, lines[j].trimmed.isEmpty { j += 1 }
        return j < lines.count ? j : nil
    }

    /// Does a new cue start at this line: a timing line, or a cue number (or VTT cue id / NOTE) followed by one?
    private static func startsCue(_ lines: [String], at j: Int) -> Bool {
        if times(lines[j]) != nil { return true }
        let line = lines[j].trimmed
        if line.hasPrefix("NOTE") || line.hasPrefix("STYLE") || line.hasPrefix("REGION") { return true }
        return j + 1 < lines.count && times(lines[j + 1]) != nil
    }

    private static func times(_ line: String) -> (Double, Double)? {
        if let g = timing.firstMatch(in: line) {
            return (secs(g[1], g[2], g[3], g[4]), secs(g[5], g[6], g[7], g[8]))
        }
        if let g = shortTiming.firstMatch(in: line.trimmed) {
            return (secs("0", g[1], g[2], g[3]), secs("0", g[4], g[5], g[6]))
        }
        return nil
    }

    /// Millis digits are a fraction: "5" means 500.
    private static func secs(_ h: String?, _ m: String?, _ s: String?, _ frac: String?) -> Double {
        let f = (frac ?? "0").padding(toLength: 3, withPad: "0", startingAt: 0)
        return Double(Int(h ?? "0") ?? 0) * 3600 + Double(Int(m ?? "0") ?? 0) * 60 + Double(Int(s ?? "0") ?? 0)
            + Double(Int(f) ?? 0) / 1000
    }
}

/// Cues indexed by start time for the player's 10 Hz poll.
struct SubtitleTimeline: Sendable {
    private let sorted: [SubCue]
    private let maxCue: Double

    init(_ cues: [SubCue]) {
        sorted = cues.sorted { $0.start < $1.start }
        maxCue = sorted.map { $0.end - $0.start }.max() ?? 0
    }

    var isEmpty: Bool { sorted.isEmpty }

    /// Every cue with `start <= t < end`, in start order.
    func at(_ t: Double) -> [SubCue] {
        var lo = 0, hi = sorted.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if sorted[mid].start <= t { lo = mid + 1 } else { hi = mid }
        }
        var out: [SubCue] = []
        var i = lo - 1
        while i >= 0, sorted[i].start > t - maxCue {
            if sorted[i].end > t { out.append(sorted[i]) }
            i -= 1
        }
        return out.reversed()
    }
}

/// Subtitle files come in many encodings; Persian ones are often Windows-1256.
enum TextDecoding {
    static func decode(_ data: Data) -> String {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let s = String(data: data, encoding: .utf16) { return s }
        if let s = String(data: data, encoding: .utf8) { return s }
        // Not UTF-8. A file that is almost all plain ASCII is a Western (English) one saved as
        // Windows-1252: its curly quotes, dashes and accents must not be read as Arabic letters, which
        // scrambles the line on screen. Otherwise it is a Persian file in Windows-1256.
        let high = data.reduce(0) { $1 >= 0x80 ? $0 + 1 : $0 }
        if high * 20 < data.count, let s = String(data: data, encoding: .windowsCP1252) { return s }
        let arabic = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.windowsArabic.rawValue))
        if let s = String(data: data, encoding: String.Encoding(rawValue: arabic)) { return s }
        return String(decoding: data, as: UTF8.self)
    }
}
