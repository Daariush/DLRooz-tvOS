import Foundation

enum TitleKind: String, Codable, Hashable, Sendable {
    case film, series
}

struct TitleRef: Hashable, Codable, Sendable {
    let kind: TitleKind
    let postId: Int
    let slug: String

    var path: String { "/post/\(kind.rawValue)/\(postId)/\(slug)/" }

    private static let pathRx = Rx(#"/post/(film|series)/(\d+)/([^/?#]+)/?"#)

    static func fromPath(_ raw: String) -> TitleRef? {
        let path = raw.hasPrefix(SiteConfig.baseString) ? String(raw.dropFirst(SiteConfig.baseString.count)) : raw
        guard let m = pathRx.firstMatch(in: path),
              let k = m[1], let id = m[2].flatMap({ Int($0) }), let slug = m[3] else { return nil }
        return TitleRef(kind: k == "film" ? .film : .series, postId: id, slug: slug)
    }
}

/// IMDb score with absolute vote count (۱۸۱ هزار → 181000).
struct Rating: Hashable, Codable, Sendable {
    let score: Double
    let votes: Int
}

struct TitleCard: Hashable, Codable, Identifiable, Sendable {
    var ref: TitleRef
    var title: String
    var year: Int?
    var posterHash: String?
    var durationMin: Int?
    var imdb: Rating?
    var criticsScore: Int?
    var genres: [String]
    var countries: [String]
    var director: String?
    var stars: [String]
    var synopsis: String?
    /// Series badge, e.g. «قسمت ۰۷ فصل سوم».
    var episodeLabel: String?
    /// Series status, e.g. «در حال پخش».
    var status: String?

    var id: TitleRef { ref }

    static func minimal(_ ref: TitleRef, title: String? = nil, posterHash: String? = nil) -> TitleCard {
        TitleCard(ref: ref, title: title ?? ref.slug.replacingOccurrences(of: "-", with: " ").capitalized, year: nil,
                  posterHash: posterHash, durationMin: nil, imdb: nil, criticsScore: nil, genres: [], countries: [],
                  director: nil, stars: [], synopsis: nil, episodeLabel: nil, status: nil)
    }
}

struct FeaturedItem: Hashable, Codable, Sendable {
    let ref: TitleRef
    let backdropHash: String
}

/// Home "recently streamed" items carry only a link and a poster.
struct PosterRef: Hashable, Codable, Sendable {
    let ref: TitleRef
    let posterHash: String
}

struct HomeSection: Hashable, Codable, Sendable, Identifiable {
    let title: String
    let morePath: String?
    let items: [TitleCard]
    var id: String { title }
}

struct HomePage: Codable, Sendable {
    let featured: [FeaturedItem]
    let recentlyStreamed: [PosterRef]
    let sections: [HomeSection]
}

struct ListPage: Sendable {
    let items: [TitleCard]
    let page: Int
    let lastPage: Int
}

/// Which browse page a site category belongs on.
enum CategoryKind: String, Hashable, Codable, Sendable { case film, series, both }

struct SiteCategory: Hashable, Sendable, Identifiable {
    let label: String
    let path: String
    let kind: CategoryKind
    var id: String { path }
}

struct CategorizedListPage: Sendable {
    let page: ListPage
    let categories: [SiteCategory]
}

struct VideoVariant: Hashable, Sendable {
    let id: String
    let width: Int
    let height: Int
    let size: String
}

/// `lang` is "original" or "dubbed-fa".
struct AudioTrackRef: Hashable, Sendable {
    let id: String
    let lang: String
    let channels: Int
}

/// `lang` is "fa" or "en".
struct SubtitleRef: Hashable, Sendable {
    let id: String
    let lang: String
}

struct Episode: Hashable, Sendable, Identifiable {
    let season: Int
    let number: Int
    let streamId: String
    let videos: [VideoVariant]
    let audios: [AudioTrackRef]
    let subtitles: [SubtitleRef]
    let played: Bool
    var id: String { streamId }
}

struct Season: Hashable, Sendable, Identifiable {
    let number: Int
    let episodes: [Episode]
    var id: Int { number }
}

/// Films are one Season(1) with one Episode(1); `dub` is empty when there is no Persian dub.
struct StreamCatalog: Hashable, Sendable {
    let main: [Season]
    let dub: [Season]
}

struct TitleDetail: Sendable {
    let card: TitleCard
    let channel: String?
    let awards: [String]
    let catalog: StreamCatalog
    let suggestions: [TitleRef]
    let suggestionPosters: [TitleRef: String]
    let trailerThumbHash: String?
    /// Whether the title is on the user's watchlist, as the page renders it; nil when the page doesn't say.
    let inWatchlist: Bool?
    /// e.g. "tt22202452"; used to find subtitles on SubDL / SubSource / OpenSubtitles.
    let imdbID: String?
}

/// Labels as on the site: Farsi, English, English + Farsi, Farsi for Dub.
struct SiteSubtitleTrack: Hashable, Sendable {
    let label: String
    let url: String
}

struct StreamSession: Sendable {
    let title: String
    /// Valid for about a minute: open right before playback, never cache.
    let masterURL: String
    let backdropPath: String?
    let subtitles: [SiteSubtitleTrack]
    /// Keyed by bitrate in kbps, e.g. 2475 → "1080 [ 2.48 GB ]".
    let qualityLabels: [Int: String]
    let streamId: String
}

extension Array where Element == Season {
    /// The episode after `streamId`, crossing into the next season.
    func nextEpisode(after streamId: String) -> Episode? {
        let ordered = sorted { $0.number < $1.number }.flatMap { $0.episodes.sorted { $0.number < $1.number } }
        guard let i = ordered.firstIndex(where: { $0.streamId == streamId }), i + 1 < ordered.count else { return nil }
        return ordered[i + 1]
    }

    func episode(_ streamId: String) -> Episode? {
        lazy.flatMap { $0.episodes }.first { $0.streamId == streamId }
    }
}
