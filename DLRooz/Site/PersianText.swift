import Foundation

/// Helpers for the site's Persian-digit metadata strings.
enum PersianText {
    private static let persian = Array("۰۱۲۳۴۵۶۷۸۹")
    private static let arabic = Array("٠١٢٣٤٥٦٧٨٩")
    private static let scoreRx = Rx(#"([\d.]+)\s*از\s*10"#)
    private static let votesRx = Rx(#"با\s*([\d.]+)\s*(هزار|میلیون)?\s*رای"#)
    private static let minutesRx = Rx(#"(\d+)\s*دقیقه"#)
    private static let criticsRx = Rx(#"منتقدین\s*:\s*(\d+)"#)
    private static let thousandsRx = Rx(#"(?<=\d)[٬،,](?=\d)"#)
    private static let spacesRx = Rx(#"\s+"#)

    /// Persian/Arabic digits to ASCII, `٫` to `.`; thousands separators between digits are dropped.
    static func digits(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for c in s {
            if let i = persian.firstIndex(of: c) ?? arabic.firstIndex(of: c) {
                out.append(Character(String(i)))
            } else if c == "٫" {
                out.append(".")
            } else {
                out.append(c)
            }
        }
        return thousandsRx.replace(in: out, with: "")
    }

    /// The form site text is compared in: Arabic ي/ى/ك become Persian ی/ک, ZWNJ and NBSP become a space,
    /// bidi marks and tatweel are dropped, and runs of spaces collapse.
    static func normalize(_ s: String) -> String {
        var out = ""
        for u in s.unicodeScalars {
            switch u {
            case "ي", "ى": out.append("ی")
            case "ك": out.append("ک")
            case "\u{200C}", "\u{00A0}", "\u{202F}", "\u{2009}": out.append(" ")
            case "\u{200D}", "\u{200E}", "\u{200F}", "\u{0640}", "\u{FEFF}": break
            default: out.unicodeScalars.append(u)
            }
        }
        return spacesRx.replace(in: out, with: " ").trimmed
    }

    static func rating(_ s: String) -> Rating? {
        let t = digits(s)
        guard let score = scoreRx.firstMatch(in: t)?[1].flatMap({ Double($0) }),
              let v = votesRx.firstMatch(in: t), let base = v[1].flatMap({ Double($0) }) else { return nil }
        let mult: Double = v[2] == "هزار" ? 1_000 : (v[2] == "میلیون" ? 1_000_000 : 1)
        return Rating(score: score, votes: Int((base * mult).rounded()))
    }

    static func minutes(_ s: String) -> Int? { minutesRx.firstMatch(in: digits(s))?[1].flatMap { Int($0) } }

    static func criticsScore(_ s: String) -> Int? { criticsRx.firstMatch(in: digits(s))?[1].flatMap { Int($0) } }
}

extension String {
    /// ASCII digits to Persian digits (for Persian UI copy only).
    var persianDigits: String {
        let p = Array("۰۱۲۳۴۵۶۷۸۹")
        return String(map { c in
            if let v = c.wholeNumberValue, c.isASCII { return p[v] }
            return c
        })
    }
}
