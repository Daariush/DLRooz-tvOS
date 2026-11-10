import Foundation

/// What we know about the video when looking for subtitles online.
struct SubtitleQuery: Sendable {
    /// "tt1234567"; for series this is the show's id.
    let imdbID: String?
    let title: String
    let year: Int?
    let season: Int?
    let episode: Int?
    /// ISO 639-1 codes, e.g. ["fa", "en"].
    let languages: [String]

    var isEpisode: Bool { season != nil && episode != nil }
}

enum SubtitleSource: String, CaseIterable, Sendable {
    case subdl = "SubDL"
    case subsource = "SubSource"
    case opensubtitles = "OpenSubtitles"
}

/// One downloadable subtitle found on an external site.
struct OnlineSubtitle: Identifiable, Hashable, Sendable {
    let id: String
    let source: SubtitleSource
    /// ISO 639-1 when known ("fa", "en"), else the site's own name.
    let language: String
    let release: String
    /// Provider-specific handle used to download it.
    let token: String
}

enum SubtitleProviderError: Error, LocalizedError {
    case notConfigured(SubtitleSource)
    case http(SubtitleSource, Int, String?)
    case noFile
    case noIMDb

    var errorDescription: String? {
        switch self {
        case .notConfigured(let s): return L("برای \(s.rawValue) در تنظیمات کلید API وارد کنید", "Add your \(s.rawValue) API key in Settings")
        case .http(let s, let code, let msg): return "\(s.rawValue): \(msg ?? "HTTP \(code)")"
        case .noFile: return L("فایل زیرنویس در بسته پیدا نشد", "No subtitle file in the download")
        case .noIMDb: return L("شناسه IMDb این عنوان پیدا نشد", "This title has no IMDb id")
        }
    }
}

/// API keys / logins the user entered in Settings (read from the Keychain).
struct SubtitleCredentials: Sendable {
    var subdlKey: String
    var subsourceKey: String
    var openSubtitlesKey: String
    var openSubtitlesUser: String
    var openSubtitlesPassword: String

    static func load() -> SubtitleCredentials {
        SubtitleCredentials(
            subdlKey: Keychain.string(for: SecretKeys.subdl),
            subsourceKey: Keychain.string(for: SecretKeys.subsource),
            openSubtitlesKey: Keychain.string(for: SecretKeys.osKey),
            openSubtitlesUser: Keychain.string(for: SecretKeys.osUser),
            openSubtitlesPassword: Keychain.string(for: SecretKeys.osPassword)
        )
    }

    func isConfigured(_ s: SubtitleSource) -> Bool {
        switch s {
        case .subdl: return !subdlKey.isEmpty
        case .subsource: return !subsourceKey.isEmpty
        case .opensubtitles: return !openSubtitlesKey.isEmpty
        }
    }
}

enum SecretKeys {
    static let subdl = "subs.subdl.key"
    static let subsource = "subs.subsource.key"
    static let osKey = "subs.opensubtitles.key"
    static let osUser = "subs.opensubtitles.user"
    static let osPassword = "subs.opensubtitles.password"
}

/// Searches every configured provider and downloads the chosen file as subtitle text.
final class OnlineSubtitles: @unchecked Sendable {
    private let session: URLSession
    private let appUA = "DLRoozTV v1.0"
    private var osToken: (token: String, base: String)?
    private let lock = NSLock()

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
    }

    /// Results from all configured providers; a provider that fails is skipped (its error returned separately).
    func searchAll(_ q: SubtitleQuery, creds: SubtitleCredentials) async -> (results: [OnlineSubtitle], errors: [String]) {
        var results: [OnlineSubtitle] = []
        var errors: [String] = []
        await withTaskGroup(of: Result<[OnlineSubtitle], Error>.self) { group in
            for source in SubtitleSource.allCases where creds.isConfigured(source) {
                group.addTask {
                    do { return .success(try await self.search(source, q, creds: creds)) } catch { return .failure(error) }
                }
            }
            for await r in group {
                switch r {
                case .success(let list): results += list
                case .failure(let e): errors.append(e.localizedDescription)
                }
            }
        }
        let order = q.languages
        results.sort { (order.firstIndex(of: $0.language) ?? 99, $0.source.rawValue) < (order.firstIndex(of: $1.language) ?? 99, $1.source.rawValue) }
        return (results, errors)
    }

    func search(_ source: SubtitleSource, _ q: SubtitleQuery, creds: SubtitleCredentials) async throws -> [OnlineSubtitle] {
        switch source {
        case .subdl: return try await searchSubDL(q, key: creds.subdlKey)
        case .subsource: return try await searchSubSource(q, key: creds.subsourceKey)
        case .opensubtitles: return try await searchOpenSubtitles(q, creds: creds)
        }
    }

    /// The subtitle as text (unzipped and decoded).
    func download(_ sub: OnlineSubtitle, query: SubtitleQuery, creds: SubtitleCredentials) async throws -> String {
        let data: Data
        switch sub.source {
        case .subdl:
            data = try await fetch(URL(string: "https://dl.subdl.com" + sub.token)!, source: .subdl)
        case .subsource:
            var req = URLRequest(url: URL(string: "https://api.subsource.net/api/v1/subtitles/\(sub.token)/download")!)
            req.setValue(creds.subsourceKey, forHTTPHeaderField: "X-API-Key")
            data = try await fetch(req, source: .subsource)
        case .opensubtitles:
            data = try await downloadOpenSubtitles(fileID: sub.token, creds: creds)
        }
        if ZipReader.isZip(data) {
            guard let file = ZipReader.subtitleFiles(data, season: query.season, episode: query.episode).first else {
                throw SubtitleProviderError.noFile
            }
            return TextDecoding.decode(file.data)
        }
        return TextDecoding.decode(data)
    }

    // MARK: SubDL — https://subdl.com/api-doc

    private func searchSubDL(_ q: SubtitleQuery, key: String) async throws -> [OnlineSubtitle] {
        var c = URLComponents(string: "https://api.subdl.com/api/v1/subtitles")!
        var items = [URLQueryItem(name: "api_key", value: key),
                     URLQueryItem(name: "languages", value: q.languages.map { $0 == "fa" ? "FA" : $0.uppercased() }.joined(separator: ",")),
                     URLQueryItem(name: "subs_per_page", value: "30"),
                     URLQueryItem(name: "type", value: q.isEpisode ? "tv" : "movie")]
        if let id = q.imdbID { items.append(URLQueryItem(name: "imdb_id", value: id)) } else {
            items.append(URLQueryItem(name: "film_name", value: q.title))
            if let y = q.year { items.append(URLQueryItem(name: "year", value: String(y))) }
        }
        if let s = q.season { items.append(URLQueryItem(name: "season_number", value: String(s))) }
        if let e = q.episode { items.append(URLQueryItem(name: "episode_number", value: String(e))) }
        c.queryItems = items
        let json = try await fetchJSON(URLRequest(url: c.url!), source: .subdl)
        if (json["status"] as? Bool) == false {
            let msg = json["error"] as? String
            if msg?.lowercased().contains("can't find") == true || msg?.lowercased().contains("not found") == true { return [] }
            throw SubtitleProviderError.http(.subdl, 200, msg)
        }
        let subs = json["subtitles"] as? [[String: Any]] ?? []
        return subs.compactMap { s in
            guard let url = s["url"] as? String else { return nil }
            let lang = (s["lang"] as? String ?? s["language"] as? String ?? "").lowercased()
            return OnlineSubtitle(id: "subdl:\(url)", source: .subdl, language: Self.iso(lang),
                                  release: s["release_name"] as? String ?? s["name"] as? String ?? "", token: url)
        }
    }

    // MARK: SubSource — https://subsource.net/api-docs

    private func searchSubSource(_ q: SubtitleQuery, key: String) async throws -> [OnlineSubtitle] {
        guard let imdb = q.imdbID else { throw SubtitleProviderError.noIMDb }
        var c = URLComponents(string: "https://api.subsource.net/api/v1/movies/search")!
        var items = [URLQueryItem(name: "searchType", value: "imdb"), URLQueryItem(name: "imdb", value: imdb)]
        if let s = q.season { items.append(URLQueryItem(name: "season", value: String(s))) }
        c.queryItems = items
        var req = URLRequest(url: c.url!)
        req.setValue(key, forHTTPHeaderField: "X-API-Key")
        let found = try await fetchJSON(req, source: .subsource)
        guard let movie = (found["data"] as? [[String: Any]])?.first, let movieId = Self.anyString(movie["movieId"]) else { return [] }

        var out: [OnlineSubtitle] = []
        for lang in q.languages {
            var sc = URLComponents(string: "https://api.subsource.net/api/v1/subtitles")!
            var si = [URLQueryItem(name: "movieId", value: movieId),
                      URLQueryItem(name: "language", value: lang == "fa" ? "farsi_persian" : (lang == "en" ? "english" : lang)),
                      URLQueryItem(name: "limit", value: "100")]
            if let s = q.season { si.append(URLQueryItem(name: "seasonNumber", value: String(s))) }
            if let e = q.episode { si.append(URLQueryItem(name: "episodeNumber", value: String(e))) }
            sc.queryItems = si
            var r = URLRequest(url: sc.url!)
            r.setValue(key, forHTTPHeaderField: "X-API-Key")
            let json = try await fetchJSON(r, source: .subsource)
            for item in json["data"] as? [[String: Any]] ?? [] {
                guard let id = Self.anyString(item["subtitleId"]) else { continue }
                let release = (item["releaseInfo"] as? [String])?.joined(separator: ", ") ?? (item["releaseInfo"] as? String ?? "")
                if let s = q.season, let e = q.episode, !Self.matchesEpisode(release, season: s, episode: e) { continue }
                out.append(OnlineSubtitle(id: "subsource:\(id)", source: .subsource, language: lang, release: release, token: id))
            }
        }
        return out
    }

    // MARK: OpenSubtitles — https://opensubtitles.stoplight.io

    private func osRequest(_ url: URL, creds: SubtitleCredentials, method: String = "GET", body: [String: Any]? = nil, token: String? = nil) -> URLRequest {
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.setValue(creds.openSubtitlesKey, forHTTPHeaderField: "Api-Key")
        r.setValue(appUA, forHTTPHeaderField: "User-Agent")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return r
    }

    private func searchOpenSubtitles(_ q: SubtitleQuery, creds: SubtitleCredentials) async throws -> [OnlineSubtitle] {
        var c = URLComponents(string: "https://api.opensubtitles.com/api/v1/subtitles")!
        // The API wants parameters sorted and lower-case.
        var items: [URLQueryItem] = []
        if let s = q.season, let e = q.episode {
            items.append(URLQueryItem(name: "episode_number", value: String(e)))
            if let id = q.imdbID { items.append(URLQueryItem(name: "parent_imdb_id", value: Self.imdbDigits(id))) }
            items.append(URLQueryItem(name: "languages", value: q.languages.sorted().joined(separator: ",")))
            if q.imdbID == nil { items.append(URLQueryItem(name: "query", value: q.title.lowercased())) }
            items.append(URLQueryItem(name: "season_number", value: String(s)))
        } else {
            if let id = q.imdbID { items.append(URLQueryItem(name: "imdb_id", value: Self.imdbDigits(id))) }
            items.append(URLQueryItem(name: "languages", value: q.languages.sorted().joined(separator: ",")))
            if q.imdbID == nil { items.append(URLQueryItem(name: "query", value: q.title.lowercased())) }
            if q.imdbID == nil, let y = q.year { items.append(URLQueryItem(name: "year", value: String(y))) }
        }
        c.queryItems = items
        let json = try await fetchJSON(osRequest(c.url!, creds: creds), source: .opensubtitles)
        var out: [OnlineSubtitle] = []
        for item in json["data"] as? [[String: Any]] ?? [] {
            guard let attrs = item["attributes"] as? [String: Any],
                  let file = (attrs["files"] as? [[String: Any]])?.first, let fileID = Self.anyString(file["file_id"]) else { continue }
            let lang = (attrs["language"] as? String ?? "").lowercased()
            out.append(OnlineSubtitle(id: "os:\(fileID)", source: .opensubtitles, language: Self.iso(lang),
                                      release: attrs["release"] as? String ?? file["file_name"] as? String ?? "", token: fileID))
        }
        return out
    }

    private func openSubtitlesLogin(_ creds: SubtitleCredentials) async throws -> (token: String, base: String)? {
        lock.lock()
        let cached = osToken
        lock.unlock()
        if let cached { return cached }
        guard !creds.openSubtitlesUser.isEmpty, !creds.openSubtitlesPassword.isEmpty else { return nil }
        let req = osRequest(URL(string: "https://api.opensubtitles.com/api/v1/login")!, creds: creds, method: "POST",
                            body: ["username": creds.openSubtitlesUser, "password": creds.openSubtitlesPassword])
        let json = try await fetchJSON(req, source: .opensubtitles)
        guard let token = json["token"] as? String else { return nil }
        let base = (json["base_url"] as? String).flatMap { $0.nilIfBlank } ?? "api.opensubtitles.com"
        let value = (token, base)
        lock.lock(); osToken = value; lock.unlock()
        return value
    }

    private func downloadOpenSubtitles(fileID: String, creds: SubtitleCredentials) async throws -> Data {
        let login = try await openSubtitlesLogin(creds)
        let host = login?.base ?? "api.opensubtitles.com"
        let req = osRequest(URL(string: "https://\(host)/api/v1/download")!, creds: creds, method: "POST",
                            body: ["file_id": Int(fileID) ?? 0, "sub_format": "srt"], token: login?.token)
        let json = try await fetchJSON(req, source: .opensubtitles)
        guard let link = (json["link"] as? String).flatMap(URL.init(string:)) else {
            throw SubtitleProviderError.http(.opensubtitles, 200, json["message"] as? String)
        }
        return try await fetch(URLRequest(url: link), source: .opensubtitles)
    }

    // MARK: helpers

    private func fetch(_ url: URL, source: SubtitleSource) async throws -> Data {
        try await fetch(URLRequest(url: url), source: source)
    }

    private func fetch(_ request: URLRequest, source: SubtitleSource) async throws -> Data {
        var r = request
        if r.value(forHTTPHeaderField: "User-Agent") == nil { r.setValue(appUA, forHTTPHeaderField: "User-Agent") }
        let (data, response) = try await session.data(for: r)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let msg = obj?["message"] as? String ?? obj?["error"] as? String
            throw SubtitleProviderError.http(source, http.statusCode, msg)
        }
        return data
    }

    private func fetchJSON(_ request: URLRequest, source: SubtitleSource) async throws -> [String: Any] {
        let data = try await fetch(request, source: source)
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    static func anyString(_ v: Any?) -> String? {
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }

    static func imdbDigits(_ id: String) -> String {
        String(Int(id.filter(\.isNumber)) ?? 0)
    }

    static func iso(_ lang: String) -> String {
        switch lang {
        case "fa", "farsi", "persian", "farsi_persian", "per", "fas": return "fa"
        case "en", "english", "eng": return "en"
        default: return lang
        }
    }

    static func matchesEpisode(_ release: String, season: Int, episode: Int) -> Bool {
        let r = release.lowercased()
        let tag = String(format: "e%02d", episode)
        // Season packs (no episode marker) are kept: the right file is picked from the archive.
        if !Rx(#"e\d{1,3}"#).matches(r) { return true }
        return r.contains(tag) || r.contains(String(format: "%dx%02d", season, episode))
    }
}

extension SubtitleSource {
    var signupURL: String {
        switch self {
        case .subdl: return "subdl.com/panel/api"
        case .subsource: return "subsource.net/api-docs"
        case .opensubtitles: return "opensubtitles.com/consumers"
        }
    }
}
