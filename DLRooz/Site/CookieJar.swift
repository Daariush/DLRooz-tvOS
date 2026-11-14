import Foundation

/// The site's cookies, persisted in the Keychain so the session (`cf`) and device id (`sf`) survive restarts.
/// Adds `scr=1` to every request for the site; `scr` itself is never stored.
final class CookieJar: @unchecked Sendable {
    private struct Stored: Codable {
        let name: String, value: String, domain: String, path: String
        let expires: Date?
        let secure: Bool
    }

    private let lock = NSLock()
    private var cookies: [Stored] = []
    private let keychainKey = "site.cookies"

    init() {
        cookies = Keychain.codable([Stored].self, for: keychainKey) ?? []
        dropExpired()
    }

    /// The `Cookie` header for `url`, or nil.
    func header(for url: URL) -> String? {
        let pairs = matching(url).map { "\($0.name)=\($0.value)" }
        return pairs.isEmpty ? nil : pairs.joined(separator: "; ")
    }

    /// Cookies for `url` as HTTPCookie objects (for AVURLAsset).
    func httpCookies(for url: URL) -> [HTTPCookie] {
        matching(url).compactMap { c in
            HTTPCookie(properties: [
                .name: c.name, .value: c.value, .domain: c.domain, .path: c.path,
                .secure: c.secure ? "TRUE" : "FALSE",
            ])
        }
    }

    func store(from response: HTTPURLResponse) {
        guard let url = response.url,
              let fields = response.allHeaderFields as? [String: String] else { return }
        let received = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
        guard !received.isEmpty else { return }
        lock.lock()
        for c in received where c.name != SiteConfig.scrCookie {
            cookies.removeAll { $0.name == c.name && $0.domain == c.domain && $0.path == c.path }
            cookies.append(Stored(name: c.name, value: c.value, domain: c.domain, path: c.path,
                                  expires: c.expiresDate, secure: c.isSecure))
        }
        dropExpiredLocked()
        let snapshot = cookies
        lock.unlock()
        Keychain.setCodable(snapshot, for: keychainKey)
    }

    func value(_ name: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        dropExpiredLocked()
        return cookies.last { $0.name == name }?.value
    }

    /// Removes all cookies except those named in `keep` (logout keeps the device id `sf`).
    func clear(keep: Set<String> = []) {
        lock.lock()
        cookies.removeAll { !keep.contains($0.name) }
        let snapshot = cookies
        lock.unlock()
        Keychain.setCodable(snapshot, for: keychainKey)
    }

    private func matching(_ url: URL) -> [Stored] {
        guard let host = url.host?.lowercased() else { return [] }
        let path = url.path.isEmpty ? "/" : url.path
        lock.lock()
        dropExpiredLocked()
        var out = cookies.filter { c in
            let d = c.domain.lowercased()
            let bare = d.hasPrefix(".") ? String(d.dropFirst()) : d
            let domainOK = host == bare || host.hasSuffix("." + bare)
            return domainOK && path.hasPrefix(c.path)
        }
        lock.unlock()
        if host == SiteConfig.host {
            out.append(Stored(name: SiteConfig.scrCookie, value: SiteConfig.scrValue, domain: host, path: "/",
                              expires: nil, secure: false))
        }
        return out
    }

    private func dropExpired() {
        lock.lock(); dropExpiredLocked(); lock.unlock()
    }

    private func dropExpiredLocked() {
        let now = Date()
        cookies.removeAll { ($0.expires ?? .distantFuture) <= now }
    }
}
