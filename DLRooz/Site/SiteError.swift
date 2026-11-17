import Foundation

enum SiteError: Error, LocalizedError {
    /// `retryAfter`: the server's `Retry-After` in seconds, when it sent one.
    case http(code: Int, retryAfter: Int?)
    case network(String)
    case blocked
    case sessionExpired
    case notLoggedIn
    case parse(String)

    var errorDescription: String? {
        switch self {
        case .http(let code, _): return L("خطای سایت (\(code))", "Site error (\(code))")
        case .network: return L("اتصال به سایت برقرار نشد؛ دوباره تلاش کنید", "Couldn't reach the site. Please try again.")
        case .blocked: return L("سایت درخواست را مسدود کرد", "The site blocked the request")
        case .sessionExpired, .notLoggedIn: return L("نشست شما به پایان رسید؛ دوباره وارد شوید", "Your session ended. Please sign in again.")
        case .parse: return L("اطلاعات درست دریافت نشد. دوباره امتحان کنید", "Couldn't get the data. Please try again.")
        }
    }

    var isRetryableNetwork: Bool {
        switch self {
        case .network: return true
        case .http(let code, _): return [502, 503, 504].contains(code)
        default: return false
        }
    }
}
