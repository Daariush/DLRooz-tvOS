import Combine
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case fa, en
    var id: String { rawValue }
    var label: String { self == .fa ? "فارسی" : "English" }
}

/// Localised copy: Persian first (as the Android app), English when chosen in Settings.
func L(_ fa: String, _ en: String) -> String {
    (UserDefaults.standard.string(forKey: "app.language") ?? "fa") == "en" ? en : fa
}

/// Numbers inside localised copy: Persian digits in Persian.
func N(_ n: Int) -> String {
    L(String(n).persianDigits, String(n))
}

enum PlayerChoice: String, CaseIterable, Identifiable {
    case ask, `internal`, infuse, vlc, senplayer, custom
    var id: String { rawValue }

    var label: String {
        switch self {
        case .ask: return L("هر بار بپرس", "Ask every time")
        case .internal: return L("پخش‌کننده داخلی", "Built-in player")
        case .infuse: return "Infuse"
        case .vlc: return "VLC"
        case .senplayer: return "SenPlayer"
        case .custom: return L("برنامه دلخواه (URL scheme)", "Custom app (URL scheme)")
        }
    }

    static var externalApps: [PlayerChoice] { [.infuse, .vlc, .senplayer, .custom] }
}

/// Which site subtitle to turn on by default.
enum SubtitlePreference: String, CaseIterable, Identifiable {
    case fa, en, dual, off
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fa: return L("فارسی", "Persian")
        case .en: return L("انگلیسی", "English")
        case .dual: return L("انگلیسی + فارسی", "English + Persian")
        case .off: return L("خاموش", "Off")
        }
    }
}

enum SubtitleColor: String, CaseIterable, Identifiable {
    case white, yellow, cyan, green
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .white: return .white
        case .yellow: return Color(red: 1, green: 1, blue: 0)
        case .cyan: return Color(red: 0.5, green: 0.88, blue: 1)
        case .green: return Color(red: 0.65, green: 0.95, blue: 0.55)
        }
    }
    var uiColor: UIColor { UIColor(color) }
    var label: String {
        switch self {
        case .white: return L("سفید", "White")
        case .yellow: return L("زرد", "Yellow")
        case .cyan: return L("آبی روشن", "Cyan")
        case .green: return L("سبز", "Green")
        }
    }
}

/// App-wide preferences (UserDefaults) plus the subtitle-site secrets (Keychain).
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    @Published var language: AppLanguage { didSet { d.set(language.rawValue, forKey: "app.language") } }

    // Playback
    @Published var playerChoice: PlayerChoice { didSet { d.set(playerChoice.rawValue, forKey: "player.choice") } }
    /// Minutes of video the built-in player tries to keep downloaded ahead: 5, 10 or 20.
    @Published var bufferMinutes: Int { didSet { d.set(bufferMinutes, forKey: "player.bufferMinutes") } }
    @Published var autoplayNext: Bool { didSet { d.set(autoplayNext, forKey: "player.autoplayNext") } }
    /// "{url}" is replaced with the percent-encoded stream URL, e.g. "myplayer://play?url={url}".
    @Published var customSchemeTemplate: String { didSet { d.set(customSchemeTemplate, forKey: "player.customScheme") } }
    /// Max quality the built-in player starts with (0 = automatic).
    @Published var maxHeight: Int { didSet { d.set(maxHeight, forKey: "player.maxHeight") } }

    // Subtitles
    @Published var subtitlePreference: SubtitlePreference { didSet { d.set(subtitlePreference.rawValue, forKey: "subs.pref") } }
    @Published var subtitleSize: Int { didSet { d.set(subtitleSize, forKey: "subs.size") } }
    @Published var subtitleColor: SubtitleColor { didSet { d.set(subtitleColor.rawValue, forKey: "subs.color") } }
    @Published var subtitleBackground: Int { didSet { d.set(subtitleBackground, forKey: "subs.bg") } }
    /// Languages to look for on SubDL / SubSource / OpenSubtitles.
    @Published var onlineSubtitleLanguages: [String] { didSet { d.set(onlineSubtitleLanguages, forKey: "subs.onlineLangs") } }

    // Subtitle sites (Keychain)
    @Published var subdlKey: String { didSet { Keychain.setString(subdlKey.trimmed, for: SecretKeys.subdl) } }
    @Published var subsourceKey: String { didSet { Keychain.setString(subsourceKey.trimmed, for: SecretKeys.subsource) } }
    @Published var openSubtitlesKey: String { didSet { Keychain.setString(openSubtitlesKey.trimmed, for: SecretKeys.osKey) } }
    @Published var openSubtitlesUser: String { didSet { Keychain.setString(openSubtitlesUser.trimmed, for: SecretKeys.osUser) } }
    @Published var openSubtitlesPassword: String { didSet { Keychain.setString(openSubtitlesPassword, for: SecretKeys.osPassword) } }

    static let bufferOptions = [5, 10, 20]
    static let sizeOptions = Array(stride(from: 60, through: 200, by: 10))
    static let backgroundOptions = [0, 25, 50, 75, 100]

    private init() {
        language = AppLanguage(rawValue: d.string(forKey: "app.language") ?? "") ?? .fa
        playerChoice = PlayerChoice(rawValue: d.string(forKey: "player.choice") ?? "") ?? .ask
        let buffer = d.integer(forKey: "player.bufferMinutes")
        bufferMinutes = AppSettings.bufferOptions.contains(buffer) ? buffer : 10
        autoplayNext = d.object(forKey: "player.autoplayNext") as? Bool ?? true
        customSchemeTemplate = d.string(forKey: "player.customScheme") ?? ""
        maxHeight = d.integer(forKey: "player.maxHeight")
        subtitlePreference = SubtitlePreference(rawValue: d.string(forKey: "subs.pref") ?? "") ?? .fa
        let size = d.integer(forKey: "subs.size")
        subtitleSize = size == 0 ? 100 : size
        subtitleColor = SubtitleColor(rawValue: d.string(forKey: "subs.color") ?? "") ?? .yellow
        subtitleBackground = d.object(forKey: "subs.bg") as? Int ?? 50
        onlineSubtitleLanguages = d.stringArray(forKey: "subs.onlineLangs") ?? ["fa", "en"]
        subdlKey = Keychain.string(for: SecretKeys.subdl)
        subsourceKey = Keychain.string(for: SecretKeys.subsource)
        openSubtitlesKey = Keychain.string(for: SecretKeys.osKey)
        openSubtitlesUser = Keychain.string(for: SecretKeys.osUser)
        openSubtitlesPassword = Keychain.string(for: SecretKeys.osPassword)
        Keychain.setString("", for: "ratings.omdb.key")
        UserDefaults.standard.removeObject(forKey: "ratings.omdb.cache")
    }

    var layoutDirection: LayoutDirection { language == .fa ? .rightToLeft : .leftToRight }
}
