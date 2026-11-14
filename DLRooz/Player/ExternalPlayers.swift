import UIKit

/// Hands a stream to another player app on the Apple TV through its URL scheme.
/// The site's stream URL carries its own short-lived token, so the other app needs no cookies;
/// it must be opened right away (the link expires after about a minute).
enum ExternalPlayers {
    static func url(for app: PlayerChoice, streamURL: String, template: String) -> URL? {
        let enc = streamURL.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? streamURL
        switch app {
        case .infuse: return URL(string: "infuse://x-callback-url/play?url=\(enc)")
        case .vlc: return URL(string: "vlc-x-callback://x-callback-url/stream?url=\(enc)")
        case .senplayer: return URL(string: "SenPlayer://x-callback-url/play?url=\(enc)")
        case .custom:
            let t = template.trimmed
            guard !t.isEmpty else { return nil }
            if t.contains("{url}") || t.contains("{rawurl}") {
                return URL(string: t.replacingOccurrences(of: "{url}", with: enc).replacingOccurrences(of: "{rawurl}", with: streamURL))
            }
            return URL(string: t + enc)
        case .ask, .internal: return nil
        }
    }

    /// Opens `app`; false when the app isn't installed or the scheme is wrong.
    @MainActor
    static func open(_ app: PlayerChoice, streamURL: String, template: String) async -> Bool {
        guard let url = url(for: app, streamURL: streamURL, template: template) else { return false }
        return await UIApplication.shared.open(url)
    }
}
