import Foundation

/// Fixed facts about the DLRooz website. Everything the app knows about the site lives under `Site/`.
enum SiteConfig {
    static let host = "robin.robert-redford.net"
    static let baseURL = URL(string: "https://\(host)")!
    static let baseString = "https://\(host)"

    /// A desktop browser UA: the site serves its full markup to it.
    static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"

    static let loginPath = "/user/login/"
    static let logoutPath = "/user/logout/"
    static let watchlistPath = "/user/watchlist/"
    static let seriesPath = "/archive/series/"
    static let filmsPath = "/archive/category/new-films/"

    /// Cookie the site normally sets from JavaScript; without it every page is a JS redirect stub.
    static let scrCookie = "scr"
    static let scrValue = "1"
    /// Login session cookie.
    static let sessionCookie = "cf"
    /// Device id cookie. Kept across logouts so this Apple TV stays one device on the account.
    static let deviceCookie = "sf"

    static func absolute(_ path: String) -> String {
        path.hasPrefix("/") ? baseString + path : path
    }
}

/// The site resizes `/img/W-H/<hash>` to any requested size; request exactly what is drawn (in pixels).
enum ImageURLs {
    static func image(_ hash: String, w: Int, h: Int) -> URL? {
        URL(string: "\(SiteConfig.baseString)/img/\(w)-\(h)/\(hash)")
    }

    static func trailerThumb(_ hash: String, w: Int, h: Int) -> URL? {
        URL(string: "\(SiteConfig.baseString)/img/\(w)-\(h)/trailer/\(hash)")
    }

    private static let hashRx = Rx(#"/img/\d+-\d+/(?:trailer/)?([^/'"\s?]+)"#)

    /// Extracts the image hash from an `/img/W-H/<hash>` path, or nil.
    static func hashOf(_ path: String) -> String? {
        hashRx.firstMatch(in: path)?[1]
    }
}
