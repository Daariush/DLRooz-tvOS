import Foundation

struct SiteResponse: Sendable {
    /// Path of the final URL after redirects, e.g. "/user/login/".
    let finalPath: String
    let body: String
}

/// Thin HTTP layer for the site: our own cookie jar, browser UA, and typed failures.
///
/// The site's server silently drops a share of requests (healthy responses arrive in < 1 s), so GETs
/// use a short timeout and are retried a few times on timeouts and gateway errors. POSTs are never retried.
final class SiteHTTP: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let jar: CookieJar
    private var session: URLSession!
    private let maxAttempts = 3

    init(jar: CookieJar) {
        self.jar = jar
        super.init()
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        // Never answer from a local cache: pages change per user (My List, the watchlist button), and a
        // cached toggle URL would never reach the site.
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        config.httpAdditionalHeaders = ["User-Agent": SiteConfig.userAgent, "Accept-Language": "fa,en;q=0.8"]
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func url(_ path: String) -> URL? {
        URL(string: path, relativeTo: SiteConfig.baseURL)?.absoluteURL
    }

    /// Pass `retry: false` for GETs that change server state (toggles).
    /// `ajaxFrom`: the page path a browser would call this from; sends it as Referer with the XHR header,
    /// as the site's own JSON endpoints expect.
    func get(_ path: String, requiresAuth: Bool = true, retry: Bool = true, timeout: TimeInterval = 8,
             ajaxFrom: String? = nil) async throws -> SiteResponse {
        guard let u = url(path) else { throw SiteError.parse("url") }
        var req = URLRequest(url: u)
        req.timeoutInterval = timeout
        if let ajaxFrom {
            req.setValue(SiteConfig.baseString + ajaxFrom, forHTTPHeaderField: "Referer")
            req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
            req.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
        }
        let attempts = retry ? maxAttempts : 1
        var attempt = 1
        while true {
            do {
                return try await execute(req, requiresAuth: requiresAuth)
            } catch let e as SiteError {
                var wait: UInt64? = e.isRetryableNetwork ? 500_000_000 : nil
                if case .http(429, let after) = e, let after, after <= 5 { wait = UInt64(max(after, 1)) * 1_000_000_000 }
                guard let w = wait, attempt < attempts else { throw e }
                try await Task.sleep(nanoseconds: w)
                attempt += 1
            }
        }
    }

    /// Raw bytes (subtitle files); cookies are sent, nothing is retried more than the default.
    func getData(_ urlString: String) async throws -> Data {
        guard let u = url(urlString) else { throw SiteError.parse("url") }
        var req = URLRequest(url: u)
        req.timeoutInterval = 15
        let (data, response) = try await send(req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SiteError.http(code: http.statusCode, retryAfter: nil)
        }
        return data
    }

    func postMultipart(_ path: String, fields: [(String, String)]) async throws -> SiteResponse {
        guard let u = url(path) else { throw SiteError.parse("url") }
        let boundary = "----DLRooz\(UUID().uuidString)"
        var body = Data()
        for (k, v) in fields {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(k)\"\r\n\r\n\(v)\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue(SiteConfig.baseString + path, forHTTPHeaderField: "Referer")
        req.setValue(SiteConfig.baseString, forHTTPHeaderField: "Origin")
        req.httpBody = body
        return try await execute(req, requiresAuth: false)
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        var req = request
        if let u = req.url, let cookie = jar.header(for: u) { req.setValue(cookie, forHTTPHeaderField: "Cookie") }
        do {
            let (data, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse { jar.store(from: http) }
            return (data, response)
        } catch is CancellationError {
            throw CancellationError()
        } catch let e as URLError where e.code == .cancelled {
            throw CancellationError()
        } catch {
            throw SiteError.network(error.localizedDescription)
        }
    }

    private func execute(_ request: URLRequest, requiresAuth: Bool) async throws -> SiteResponse {
        let (data, response) = try await send(request)
        guard let http = response as? HTTPURLResponse else { throw SiteError.network("no response") }
        let body = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        if !(200..<300).contains(http.statusCode) {
            if (http.statusCode == 403 || http.statusCode == 503) && (body.contains("cf-chl") || body.contains("Just a moment")) {
                throw SiteError.blocked
            }
            let after = (http.value(forHTTPHeaderField: "Retry-After")).flatMap { Int($0.trimmed) }
            throw SiteError.http(code: http.statusCode, retryAfter: after)
        }
        let finalPath = http.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: true)?.percentEncodedPath } ?? "/"
        if requiresAuth && finalPath.hasPrefix(SiteConfig.loginPath) { throw SiteError.sessionExpired }
        if body.count < 4000 && body.contains("setCookie(window.devicePixelRatio)") { throw SiteError.parse("scr-stub") }
        return SiteResponse(finalPath: finalPath, body: body)
    }

    // MARK: URLSessionTaskDelegate

    /// Redirect responses can set cookies (login, logout): keep them, and send the jar on the next hop.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        jar.store(from: response)
        var next = request
        if let u = next.url, let cookie = jar.header(for: u) {
            next.setValue(cookie, forHTTPHeaderField: "Cookie")
        } else {
            next.setValue(nil, forHTTPHeaderField: "Cookie")
        }
        completionHandler(next)
    }
}
