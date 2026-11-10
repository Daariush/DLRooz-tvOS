import Foundation

/// Critic scores from OMDb (omdbapi.com), looked up by IMDb id: Rotten Tomatoes (the site itself only
/// shows IMDb and Metacritic). Needs a free OMDb API key in Settings. Results are cached for a week.
struct ExternalScores: Codable, Equatable {
    /// e.g. "93%"
    var rottenTomatoes: String?
    /// e.g. "74/100"
    var metacritic: String?
    var fetchedAt: Date
}

@MainActor
final class ExternalRatings {
    static let shared = ExternalRatings()
    static let keychainKey = "ratings.omdb.key"
    /// Optional built-in OMDb key, injected at build time (OMDB_API_KEY build setting -> Info.plist),
    /// so it never lives in the repository. Used when no key is entered in Settings.
    static var builtInKey: String {
        let v = (Bundle.main.object(forInfoDictionaryKey: "OMDbAPIKey") as? String ?? "").trimmingCharacters(in: .whitespaces)
        return v.hasPrefix("$(") ? "" : v
    }
    /// The key from Settings, or the built-in one.
    static var activeKey: String {
        let own = Keychain.string(for: keychainKey)
        return own.isEmpty ? builtInKey : own
    }
    private let cacheKey = "ratings.omdb.cache"
    private var cache: [String: ExternalScores]

    private init() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let decoded = try? JSONDecoder().decode([String: ExternalScores].self, from: data) {
            cache = decoded
        } else {
            cache = [:]
        }
    }

    var isConfigured: Bool { !Self.activeKey.isEmpty }

    func scores(imdbID: String) async -> ExternalScores? {
        if let hit = cache[imdbID], Date().timeIntervalSince(hit.fetchedAt) < 7 * 86_400 { return hit }
        let key = Self.activeKey
        guard !key.isEmpty, var c = URLComponents(string: "https://www.omdbapi.com/") else { return nil }
        c.queryItems = [URLQueryItem(name: "apikey", value: key), URLQueryItem(name: "i", value: imdbID)]
        guard let url = c.url, let result = try? await URLSession.shared.data(from: url),
              let json = (try? JSONSerialization.jsonObject(with: result.0)) as? [String: Any],
              (json["Response"] as? String) == "True" else { return nil }
        var s = ExternalScores(rottenTomatoes: nil, metacritic: nil, fetchedAt: Date())
        for r in json["Ratings"] as? [[String: Any]] ?? [] {
            switch r["Source"] as? String {
            case "Rotten Tomatoes": s.rottenTomatoes = r["Value"] as? String
            case "Metacritic": s.metacritic = r["Value"] as? String
            default: break
            }
        }
        cache[imdbID] = s
        if cache.count > 2000 { cache = [imdbID: s] }
        if let data = try? JSONEncoder().encode(cache) { UserDefaults.standard.set(data, forKey: cacheKey) }
        return s
    }

    /// Checks a key; nil when it works, else the error text.
    func test(key: String) async -> String? {
        guard var c = URLComponents(string: "https://www.omdbapi.com/") else { return "URL" }
        c.queryItems = [URLQueryItem(name: "apikey", value: key), URLQueryItem(name: "i", value: "tt1375666")]
        guard let url = c.url else { return "URL" }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if (json?["Response"] as? String) == "True" { return nil }
            return json?["Error"] as? String ?? "OMDb error"
        } catch {
            return error.localizedDescription
        }
    }

    func clear() {
        cache = [:]
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }
}
