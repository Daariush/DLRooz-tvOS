import Foundation
import SwiftSoup

// Ports of the Android app's Jsoup parsers. Markup is matched by Font Awesome icons and headings,
// never by position, so small layout changes on the site don't break them.

/// One title "card" (`.postMeta` on lists/home, the header block on title pages).
enum CardParser {
    private static let titleYear = Rx(#"^(.*?)\s*\((\d{4})\)\s*$"#)

    static func parse(_ el: Element) -> TitleCard? {
        guard let link = el.all("a[href*=/post/]").first(where: { TitleRef.fromPath($0.a("href")) != nil }),
              let ref = TitleRef.fromPath(link.a("href")) else { return nil }
        let headingEl = el.first("h1, h2, h3") ?? el.first("b")
        var heading = ""
        if let h = headingEl {
            heading = (h.first("a")?.own ?? h.own)
            if heading.isEmpty { heading = h.txt }
        }
        let m = titleYear.firstMatch(in: heading)
        let title = m?[1]?.nilIfBlank ?? heading.nilIfBlank
            ?? link.a("title").trimmed.nilIfBlank
            ?? el.first("img[alt]")?.a("alt").trimmed.nilIfBlank
            ?? ref.displayName
        let year = m?[2].flatMap { Int($0) }
        let poster = el.all("img").lazy
            .map { $0.imageSource }
            .compactMap { src -> String? in
                guard src.contains("/img/"), !src.contains("avatar") else { return nil }
                return ImageURLs.hashOf(src)
            }.first

        func line(_ icon: String) -> Element? { el.first("i.\(icon)")?.up }
        func value(_ icon: String) -> String? { line(icon)?.txt.after(":").trimmed.nilIfBlank }
        func list(_ icon: String) -> [String] {
            guard let l = line(icon) else { return [] }
            let links = l.all("a").map { $0.txt }.filter { !$0.isEmpty }
            if !links.isEmpty { return links }
            return l.innerHTML.after(":").components(separatedBy: "<spl></spl>").map { Soup.text(ofHTML: $0) }.filter { !$0.isEmpty }
        }

        return TitleCard(
            ref: ref,
            title: title,
            year: year,
            posterHash: poster,
            durationMin: line("fa-hourglass-half").flatMap { PersianText.minutes($0.txt) },
            imdb: line("fa-star").flatMap { PersianText.rating($0.txt) },
            criticsScore: line("fa-flag").flatMap { PersianText.criticsScore($0.txt) },
            genres: list("fa-typo3"),
            countries: list("fa-globe"),
            director: list("fa-user").first,
            stars: list("fa-users"),
            synopsis: el.first(".text-justify")?.txt.nilIfBlank,
            episodeLabel: value("fa-chevron-circle-left") ?? line("fa-chevron-circle-left")?.txt.nilIfBlank,
            status: line("fa-circle-notch")?.txt.nilIfBlank
        )
    }
}

enum HomeParser {
    private static let recentlyStreamed = "مشاهدات اخیر"
    private static let newFilmsTitle = "فیلم های جدید"
    private static let newFilmsPath = "/archive/category/new-films/"

    static func parse(_ html: String) throws -> HomePage {
        let doc = try Soup.parse(html)
        let featured: [FeaturedItem] = doc.all(".carousel-item").compactMap { item in
            guard let ref = TitleRef.fromPath(item.a("href")),
                  let img = item.first("img"), let hash = ImageURLs.hashOf(img.imageSource) else { return nil }
            return FeaturedItem(ref: ref, backdropHash: hash)
        }
        var recent: [PosterRef] = []
        var sections: [HomeSection] = []
        for h2 in doc.all("h2") {
            guard let header = h2.up, let content = header.nextSibling else { continue }
            let title = PersianText.normalize(h2.txt)
            if title.contains(recentlyStreamed) {
                recent = posters(content)
                continue
            }
            let items = unique(content.kids.compactMap(CardParser.parse))
            if !items.isEmpty {
                sections.append(HomeSection(title: title, morePath: header.first("a.btn[href]")?.a("href"), items: items))
            }
        }
        let newFilms = unique(doc.all(".postMeta").compactMap(CardParser.parse))
        if !newFilms.isEmpty { sections.append(HomeSection(title: newFilmsTitle, morePath: newFilmsPath, items: newFilms)) }
        if featured.isEmpty && recent.isEmpty && sections.isEmpty { throw SiteError.parse("home") }
        return HomePage(featured: featured, recentlyStreamed: recent, sections: sections)
    }

    private static func posters(_ content: Element) -> [PosterRef] {
        var seen = Set<TitleRef>()
        return content.all("a[href*=/post/]").compactMap { a in
            guard let ref = TitleRef.fromPath(a.a("href")), let img = a.first("img"),
                  let hash = ImageURLs.hashOf(img.imageSource), seen.insert(ref).inserted else { return nil }
            return PosterRef(ref: ref, posterHash: hash)
        }
    }
}

func unique(_ cards: [TitleCard]) -> [TitleCard] {
    var seen = Set<TitleRef>()
    return cards.filter { seen.insert($0.ref).inserted }
}

enum ListParser {
    static func parse(_ html: String) throws -> ListPage { parse(try Soup.parse(html)) }

    static func parse(_ doc: Document) -> ListPage {
        var items = unique(doc.all(".postMeta").compactMap(CardParser.parse))
        // Some pages (My List) lay titles out as bare poster links instead of `.postMeta` cards.
        if items.isEmpty { items = posterLinks(doc) }
        let page = doc.first(".pagination .page-item.active").flatMap { Int(PersianText.digits($0.txt).trimmed) } ?? 1
        let last = doc.all(".pagination .page-link").compactMap { Int(PersianText.digits($0.txt).trimmed) }.max() ?? page
        return ListPage(items: items, page: page, lastPage: max(page, last))
    }

    /// Every `/post/` link with a poster image outside the page's header, menus, sidebar and footer.
    /// Titles come from the link or image text; when missing, cards look the real title up later.
    static func posterLinks(_ doc: Document) -> [TitleCard] {
        var seen = Set<TitleRef>()
        return doc.all("a[href*=/post/]").compactMap { a in
            guard let ref = TitleRef.fromPath(a.a("href")), !inChrome(a) else { return nil }
            let img = a.first("img") ?? a.up?.first("img")
            guard let img, let hash = ImageURLs.hashOf(img.imageSource), seen.insert(ref).inserted else { return nil }
            let name = a.a("title").trimmed.nilIfBlank ?? img.a("alt").trimmed.nilIfBlank ?? a.txt.nilIfBlank
            return TitleCard.minimal(ref, title: name, posterHash: hash)
        }
    }

    private static func inChrome(_ el: Element) -> Bool {
        var node = el.up
        while let n = node {
            let tag = n.tagName()
            if ["nav", "header", "footer", "aside"].contains(tag) { return true }
            let cls = (try? n.className()) ?? ""
            if cls.contains("sidebar") || cls.contains("navbar") || cls.contains("dropdown") || cls.contains("swiper") { return true }
            node = n.up
        }
        return false
    }
}

/// Only the «فیلم و سریال» result block; the page's sidebar lists are ignored.
enum SearchParser {
    static func parse(_ html: String) throws -> [TitleCard] {
        let doc = try Soup.parse(html)
        guard let h2 = doc.all("h2").first(where: { PersianText.normalize($0.txt).contains("فیلم و سریال") }),
              let block = h2.up?.up else { return [] }
        return unique(block.all("div.rtl").compactMap(CardParser.parse))
    }
}

/// The site's navigation menu as browsable categories (only plain `/archive/...` listings).
enum CategoryMenuParser {
    private static let listing = Rx(#"^/archive/(?:category/([a-z0-9-]+)|series|(?:film|series)/(?:country|genre)/[a-z0-9-]+)/$"#)
    private static let typeQuery = Rx(#"^type=(film|series)$"#)

    static func parse(_ doc: Document) -> [SiteCategory] {
        guard let menu = doc.first("#navbar") ?? doc.first("nav") else { return [] }
        var seen = Set<String>()
        return menu.all("a[href]").compactMap { a in
            let label = PersianText.normalize(a.txt)
            guard !label.isEmpty else { return nil }
            var href = a.a("href").trimmed
            if href.hasPrefix(SiteConfig.baseString) { href = String(href.dropFirst(SiteConfig.baseString.count)) }
            let rawPath = href.before("?").before("#")
            let path = rawPath.hasSuffix("/") ? rawPath : rawPath + "/"
            let query = href.contains("?") ? href.after("?").before("#") : ""
            guard let m = listing.firstMatch(in: path) else { return nil }
            let slug = m[1] ?? ""
            if slug == "coming-soon" { return nil }
            var type: String?
            if !query.isEmpty {
                guard let t = typeQuery.firstMatch(in: query)?[1] else { return nil }
                type = t
            }
            let full = query.isEmpty ? path : "\(path)?\(query)"
            guard seen.insert(full).inserted else { return nil }
            return SiteCategory(label: label, path: full, kind: kind(path: path, slug: slug, type: type, link: a))
        }
    }

    private static func kind(path: String, slug: String, type: String?, link: Element) -> CategoryKind {
        if type == "film" { return .film }
        if type == "series" { return .series }
        if path.hasPrefix("/archive/film/") { return .film }
        if path.hasPrefix("/archive/series/") { return .series }
        if slug.hasSuffix("-films") || slug.hasSuffix("-film") { return .film }
        if slug.contains("series") || slug.contains("tv-show") { return .series }
        var node = link.up
        while let n = node {
            if n.has("dropdown") {
                let menu = PersianText.normalize(n.first(".dropdown-toggle")?.txt ?? "")
                if menu.contains("فیلم") { return .film }
                if menu.contains("سریال") { return .series }
                break
            }
            node = n.up
        }
        return .both
    }
}

enum TitleParser {
    private static let streamRx = Rx(#"var STREAM\s*=\s*(\{.*?\})\s*(?:;\s*\n|;?\s*</script>)"#, dotAll: true)
    private static let trailerRx = Rx(#"/img/590-331/trailer/[^'"\s]+"#)
    private static let imdbRx = Rx(#"imdb\.com/title/(tt\d+)"#)

    static func parse(_ html: String, ref: TitleRef) throws -> TitleDetail {
        guard let json = streamRx.firstMatch(in: html)?[1] else { throw SiteError.parse("STREAM") }
        let catalog = try parseCatalog(json)
        let doc = try Soup.parse(html)
        let meta = doc.first(".postMeta")?.up
        var card = meta.flatMap(CardParser.parse) ?? TitleCard.minimal(ref)
        card.ref = ref
        let channel = meta?.first("i.fa-tv")?.up?.txt.after(":").trimmed.nilIfBlank
        var awards: [String] = []
        for icon in meta?.all("i.fa-flag") ?? [] {
            guard let heading = icon.up, let box = heading.up else { continue }
            let title = heading.txt.trimmingCharacters(in: CharacterSet(charactersIn: ": "))
            awards += box.all("div.col-12.px-0").map { "\(title): \($0.txt)" }
        }
        var suggestions: [TitleRef] = []
        var posters: [TitleRef: String] = [:]
        if let block = doc.all("h2").first(where: { PersianText.normalize($0.txt).contains("آثار پیشنهادی") })?.up?.up {
            for a in block.all("a[href*=/post/]") {
                guard let r = TitleRef.fromPath(a.a("href")) else { continue }
                if !suggestions.contains(r) { suggestions.append(r) }
                if let img = a.first("img"), let hash = ImageURLs.hashOf(img.imageSource) { posters[r] = hash }
            }
        }
        let trailer = trailerRx.firstMatch(in: html)?[0].flatMap { ImageURLs.hashOf($0) }
        let watchButton = doc.first("button.watchlist[value2=watch]")
        var inWatchlist: Bool?
        if let b = watchButton {
            if b.has("btn-warning") { inWatchlist = true } else if b.has("btn-gray") { inWatchlist = false }
        }
        return TitleDetail(card: card, channel: channel, awards: awards, catalog: catalog, suggestions: suggestions,
                           suggestionPosters: posters, trailerThumbHash: trailer, inWatchlist: inWatchlist,
                           imdbID: imdbRx.firstMatch(in: html)?[1])
    }

    /// `STREAM` is `{"main": seasons, "dub"?: seasons}`; films use arrays, series objects keyed by number.
    static func parseCatalog(_ json: String) throws -> StreamCatalog {
        guard let root = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] else {
            throw SiteError.parse("STREAM")
        }
        return StreamCatalog(main: seasons(root["main"]), dub: seasons(root["dub"]))
    }

    private static func numbered(_ v: Any?) -> [(Int, Any)] {
        if let arr = v as? [Any] { return arr.enumerated().map { ($0.offset + 1, $0.element) } }
        if let obj = v as? [String: Any] {
            return obj.compactMap { k, val in Int(k).map { ($0, val) } }.sorted { $0.0 < $1.0 }
        }
        return []
    }

    private static func seasons(_ v: Any?) -> [Season] {
        numbered(v).map { (n, eps) in
            Season(number: n, episodes: numbered(eps).compactMap { episode(season: n, number: $0.0, $0.1) })
        }
    }

    private static func str(_ o: [String: Any], _ k: String) -> String {
        if let s = o[k] as? String { return s }
        if let n = o[k] as? NSNumber { return n.stringValue }
        return ""
    }

    private static func episode(season: Int, number: Int, _ v: Any) -> Episode? {
        guard let o = v as? [String: Any] else { return nil }
        let id = str(o, "id").trimmed
        guard !id.isEmpty else { return nil }
        func list(_ k: String) -> [[String: Any]] { (o[k] as? [Any] ?? []).compactMap { $0 as? [String: Any] } }
        let played: Bool = {
            if let b = o["played"] as? Bool { return b }
            return str(o, "played") == "1"
        }()
        return Episode(
            season: season, number: number, streamId: id,
            videos: list("videos").map { VideoVariant(id: str($0, "id"), width: Int(str($0, "width")) ?? 0,
                                                     height: Int(str($0, "height")) ?? 0, size: str($0, "size")) },
            audios: list("audios").map { AudioTrackRef(id: str($0, "id"), lang: str($0, "lang"), channels: Int(str($0, "channels")) ?? 2) },
            subtitles: list("subtitles").map { SubtitleRef(id: str($0, "id"), lang: str($0, "lang")) },
            played: played
        )
    }
}

/// Reads the JW Player setup script of a `/stream/{streamId}/{postId}/` page.
enum StreamPageParser {
    private static let masterRx = Rx(#"file:\s*'(/json/m3u8/[^']+)'"#)
    private static let trackRx = Rx(#"kind:\s*'captions',\s*file:\s*"([^"]+)",\s*label:\s*'([^']+)'"#)
    private static let qualityBlockRx = Rx(#"qualityLabels:\s*\{([^}]*)\}"#)
    private static let qualityRx = Rx(#"'(\d+)'\s*:\s*'([^']*)'"#)
    private static let titleRx = Rx(#"title:\s*"([^"]*)""#)
    private static let imageRx = Rx(#"image:\s*'([^']+)'"#)

    static func parse(_ html: String, streamId: String) throws -> StreamSession {
        guard let master = masterRx.firstMatch(in: html)?[1] else { throw SiteError.parse("m3u8") }
        var labels: [Int: String] = [:]
        if let block = qualityBlockRx.firstMatch(in: html)?[1] {
            for m in qualityRx.allMatches(in: block) {
                if let k = m[1].flatMap({ Int($0) }), let v = m[2] { labels[k] = v }
            }
        }
        return StreamSession(
            title: titleRx.firstMatch(in: html)?[1] ?? "",
            masterURL: SiteConfig.absolute(master),
            backdropPath: imageRx.firstMatch(in: html)?[1],
            subtitles: trackRx.allMatches(in: html).compactMap { m in
                guard let file = m[1], let label = m[2] else { return nil }
                return SiteSubtitleTrack(label: label, url: SiteConfig.absolute(file))
            },
            qualityLabels: labels,
            streamId: streamId
        )
    }
}
