import Foundation

/// Everything the UI asks of the site. An expired session is renewed once, transparently.
final class SiteRepository: @unchecked Sendable {
    let http: SiteHTTP
    let auth: AuthService
    private let relogin = ReloginGate()
    /// Called when the session is gone for good (the UI goes back to sign-in).
    var onSessionLost: (@Sendable () -> Void)?

    init(http: SiteHTTP, auth: AuthService) {
        self.http = http
        self.auth = auth
    }

    func home() async throws -> HomePage {
        try await authed { try HomeParser.parse(try await self.http.get("/").body) }
    }

    /// Page 1 is `path` itself; page N inserts `N/` before any query string.
    func list(_ path: String, page: Int = 1) async throws -> ListPage {
        if path == SiteConfig.watchlistPath {
            // My List is one page with film and series sections, not a paged archive.
            guard page <= 1 else { return ListPage(items: [], page: page, lastPage: 1) }
            return try await authed {
                ListPage(items: try WatchlistParser.parse(try await self.http.get(path).body), page: 1, lastPage: 1)
            }
        }
        return try await authed {
            var target = path
            if page > 1 {
                var base = path.before("?")
                if !base.hasSuffix("/") { base += "/" }
                let query = path.contains("?") ? path.after("?") : ""
                target = "\(base)\(page)/" + (query.isEmpty ? "" : "?\(query)")
            }
            return try ListParser.parse(try await self.http.get(target).body)
        }
    }

    func listWithCategories(_ path: String) async throws -> CategorizedListPage {
        try await authed {
            let doc = try Soup.parse(try await self.http.get(path).body)
            return CategorizedListPage(page: ListParser.parse(doc), categories: CategoryMenuParser.parse(doc))
        }
    }

    func search(_ query: String) async throws -> [TitleCard] {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?"))) ?? query
        return try await authed { try SearchParser.parse(try await self.http.get("/search/?s=\(q)").body) }
    }

    func title(_ ref: TitleRef) async throws -> TitleDetail {
        try await authed { try TitleParser.parse(try await self.http.get(ref.path).body, ref: ref) }
    }

    /// Opening the stream page marks the title as streamed on the account; call only right before playback.
    func openStream(_ episode: Episode, ref: TitleRef, dubbed: Bool, height: Int = 1080) async throws -> StreamSession {
        try await authed {
            let lang = dubbed ? "dubbed-fa" : "original"
            let body = try await self.http.get("/stream/\(episode.streamId)/\(ref.postId)/?lang=\(lang)&h=\(height)").body
            return try StreamPageParser.parse(body, streamId: episode.streamId)
        }
    }

    /// `state` is one of `watch`, `favorite`, `watched`. It toggles on the site, so it is never retried.
    func toggleWatchlist(postId: Int, state: String = "watch", from page: String? = nil) async throws {
        _ = try await authed {
            try await self.http.get("/json/userWatchlist/\(postId)/\(state)/", retry: false, ajaxFrom: page ?? "/")
        }
    }

    /// A site subtitle file (needs the session cookies), decoded to text.
    func subtitle(_ url: String) async throws -> String {
        try await authed { TextDecoding.decode(try await self.http.getData(url)) }
    }

    func reportStreamError(streamId: String, event: String, message: String) async {
        let msg = message.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        _ = try? await http.get("/json/logStreamError/\(streamId)/?event=\(event)&msg=\(msg)", requiresAuth: false, retry: false)
    }

    private func authed<T>(_ block: @escaping () async throws -> T) async throws -> T {
        let before = auth.sessionToken
        do {
            return try await block()
        } catch SiteError.sessionExpired {}
        let renewed = await relogin.renew(before: before, auth: auth)
        guard renewed else {
            onSessionLost?()
            throw SiteError.notLoggedIn
        }
        do {
            return try await block()
        } catch SiteError.sessionExpired {
            onSessionLost?()
            throw SiteError.notLoggedIn
        }
    }
}

/// Concurrent expiries share a single login; a refused relogin is not retried until a new login.
private actor ReloginGate {
    private var refusedToken: String??
    private var inFlight: Task<Bool, Never>?

    func renew(before: String?, auth: AuthService) async -> Bool {
        if let inFlight { return await inFlight.value }
        let current = auth.sessionToken
        if let current, current != before { return true }
        if let refused = refusedToken, refused == current { return false }
        let task = Task { await auth.relogin() }
        inFlight = task
        let ok = await task.value
        inFlight = nil
        refusedToken = ok ? nil : .some(auth.sessionToken)
        return ok
    }
}
