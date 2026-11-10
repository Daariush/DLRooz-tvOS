import SwiftUI

enum Theme {
    static let background = Color(red: 0.043, green: 0.043, blue: 0.06)
    static let accent = Color(red: 0.90, green: 0.20, blue: 0.22)
    static let secondaryText = Color.white.opacity(0.65)

    /// Poster size in points (tvOS renders 1 pt = 1 px at 1080p, 2 px at 4K).
    static let posterSize = CGSize(width: 250, height: 375)
    static let landscapeSize = CGSize(width: 420, height: 236)

    static func posterURL(_ hash: String?, w: Int = 500, h: Int = 750) -> URL? {
        hash.flatMap { ImageURLs.image($0, w: w, h: h) }
    }

    static func backdropURL(_ hash: String?) -> URL? {
        hash.flatMap { ImageURLs.image($0, w: 1920, h: 1080) }
    }
}

/// Small rounded label, e.g. «دوبله» or «IMDb 7.9».
struct Pill: View {
    let text: String
    var filled = false

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(filled ? Theme.accent : Color.white.opacity(0.14), in: Capsule())
    }
}

/// Full-screen loading / error states.
struct LoadingView: View {
    var body: some View {
        ProgressView().scaleEffect(1.4).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 80)).foregroundStyle(Theme.secondaryText)
            Text(message).font(.title3).multilineTextAlignment(.center)
            Button(L("تلاش دوباره", "Try again"), action: retry)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension TitleCard {
    /// "2024 · 120 دقیقه · Drama, Sci-Fi"
    var metaLine: String {
        var parts: [String] = []
        if let y = year { parts.append(String(y)) }
        if let m = durationMin { parts.append(L("\(N(m)) دقیقه", "\(m) min")) }
        if !genres.isEmpty { parts.append(genres.prefix(3).joined(separator: L("، ", ", "))) }
        return parts.joined(separator: "  ·  ")
    }
}
