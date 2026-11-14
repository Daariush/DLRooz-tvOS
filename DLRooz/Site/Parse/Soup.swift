import Foundation
import SwiftSoup

/// Non-throwing conveniences over SwiftSoup, so parsers read like their Jsoup originals.
extension Element {
    func all(_ css: String) -> [Element] { (try? select(css).array()) ?? [] }
    func first(_ css: String) -> Element? { (try? select(css))?.first() }
    func a(_ key: String) -> String { (try? attr(key)) ?? "" }
    var txt: String { ((try? text()) ?? "").trimmed }
    var own: String { ownText().trimmed }
    var innerHTML: String { (try? html()) ?? "" }
    var up: Element? { parent() }
    var nextSibling: Element? { (try? nextElementSibling()) ?? nil }
    var kids: [Element] { children().array() }
    func has(_ cls: String) -> Bool { hasClass(cls) }

    /// `data-src` (lazy images) or `src`.
    var imageSource: String {
        let lazy = a("data-src")
        return lazy.isEmpty ? a("src") : lazy
    }
}

enum Soup {
    static func parse(_ html: String) throws -> Document {
        do { return try SwiftSoup.parse(html, SiteConfig.baseString) } catch { throw SiteError.parse("html") }
    }

    static func text(ofHTML fragment: String) -> String {
        ((try? SwiftSoup.parseBodyFragment(fragment).text()) ?? "").trimmed
    }
}
