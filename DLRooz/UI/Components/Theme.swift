import SwiftUI

/// The app's shared design rules (see the UX and UI review): one safe-area margin, one spacing set,
/// one type scale, colours taken from the app icon, and the shared button, badge and state views.
/// Screens use these instead of their own numbers.
enum Theme {
    // MARK: Colour

    /// Ground #0B0B0F.
    static let background = Color(red: 0.043, green: 0.043, blue: 0.059)
    /// Surface for empty tiles and panels, #1C1C24.
    static let surface = Color(red: 0.110, green: 0.110, blue: 0.141)
    /// "On" state and progress: the icon's red-orange, #E45611.
    static let accent = Color(red: 0.894, green: 0.337, blue: 0.067)
    /// Watched mark: the icon's green-teal, #2BB5A0.
    static let watched = Color(red: 0.169, green: 0.710, blue: 0.627)
    static let secondaryText = Color.white.opacity(0.7)
    /// A control at rest.
    static let controlRest = Color.white.opacity(0.12)

    // MARK: Layout

    /// Page margin on the left and right of every screen (Apple TV safe area).
    static let margin: CGFloat = 80
    /// Space above a page's content and below it.
    static let pageTop: CGFloat = 60
    /// Between rows and sections of a page.
    static let rowSpacing: CGFloat = 50
    /// Between cards in a row or grid.
    static let cardSpacing: CGFloat = 40
    /// Between grid rows (a card's title sits under it).
    static let gridRowSpacing: CGFloat = 60
    /// Between buttons and chips in a row.
    static let chipSpacing: CGFloat = 20
    /// Room above and below a row of cards for the focused card's lift and shadow.
    static let focusRoom: CGFloat = 30
    /// Space between a card and its title, enough for the focused card's lift and shadow.
    static let cardTitleGap: CGFloat = 34
    static let cornerRadius: CGFloat = 12
    static let controlRadius: CGFloat = 14

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

// MARK: Type scale

extension Font {
    /// Page titles, 57 bold.
    static let pageTitle = Font.system(size: 57, weight: .bold)
    /// Row and section headings, 38 semibold.
    static let rowHeading = Font.system(size: 38, weight: .semibold)
    /// Buttons, chips and card titles, 31 medium.
    static let control = Font.system(size: 31, weight: .medium)
    /// Body text, 29.
    static let bodyText = Font.system(size: 29)
    /// Secondary lines and captions, 25.
    static let captionText = Font.system(size: 25)
    /// Badges, 22 bold.
    static let badge = Font.system(size: 22, weight: .bold)
}

/// A page's title, in the same place on every screen.
struct PageTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.pageTitle).lineLimit(2)
    }
}

/// A row or section heading.
struct RowHeading: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.rowHeading)
    }
}

// MARK: Badges

/// One badge shape for every label on a thumbnail or title page: same height, same 8 corner.
struct Badge: View {
    enum Style {
        case imdb, critics(Color), watched, neutral
    }

    let text: String
    var prefix: String?
    var icon: String?
    var style: Style = .neutral

    private var fill: Color {
        switch style {
        case .imdb: return Color(red: 0.96, green: 0.77, blue: 0.09)
        case .critics(let c): return c
        case .watched: return Theme.watched
        case .neutral: return Color.white.opacity(0.16)
        }
    }

    private var ink: Color {
        if case .neutral = style { return .white }
        return .black
    }

    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).font(.system(size: 18, weight: .bold)) }
            if let prefix { Text(prefix).font(.system(size: 17, weight: .heavy)) }
            Text(text).font(.badge)
        }
        .foregroundStyle(ink)
        .lineLimit(1)
        .padding(.horizontal, 10).frame(height: 34)
        .background(fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Neutral badge, e.g. «دوبله» or «زیرنویس».
struct Pill: View {
    let text: String
    var body: some View { Badge(text: text) }
}

// MARK: Loading, empty and error states

/// Full-screen loading state.
struct LoadingView: View {
    var body: some View {
        ProgressView().scaleEffect(1.4).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Nothing to show: an icon and one line, centred in the space left.
struct EmptyStateView: View {
    let icon: String
    let message: String

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: icon).font(.system(size: 72)).foregroundStyle(Theme.secondaryText)
            Text(message).font(.bodyText).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 100)
    }
}

/// Something failed: the same layout as the empty state, plus a Try again button.
struct ErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 72)).foregroundStyle(Theme.secondaryText)
            Text(message).font(.bodyText).multilineTextAlignment(.center).frame(maxWidth: 1100)
            Button(action: retry) {
                Label(L("تلاش دوباره", "Try again"), systemImage: "arrow.clockwise")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
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

// MARK: Buttons and chips

/// The one button shape on Apple TV, for Play, My List, categories, filters, seasons and the
/// Original / Dubbed choice. Only the state changes: a soft plate at rest, white with dark text and a
/// lift when focused (as in the Apple TV app), accent fill when `selected` ("on").
struct TVButtonStyle: ButtonStyle {
    var selected = false
    /// Stretch to the full width (Settings rows).
    var fullWidth = false
    /// Smaller text and padding, for a row that holds many buttons (the title page's actions).
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        Plate(configuration: configuration, selected: selected, fullWidth: fullWidth, compact: compact)
    }

    private struct Plate: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        let fullWidth: Bool
        let compact: Bool
        @Environment(\.isFocused) private var focused
        @Environment(\.isEnabled) private var enabled

        private var fill: Color {
            if focused { return .white }
            if !enabled { return Color.white.opacity(0.08) }
            return selected ? Theme.accent : Theme.controlRest
        }

        var body: some View {
            configuration.label
                .font(compact ? .system(size: 26, weight: .medium) : .control)
                .lineLimit(1)
                .foregroundStyle(focused ? Color.black : Color.white.opacity(enabled ? 1 : 0.75))
                .frame(maxWidth: fullWidth ? .infinity : nil, alignment: .leading)
                .padding(.horizontal, compact ? 20 : 28).padding(.vertical, compact ? 13 : 16)
                .background(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).fill(fill))
                .scaleEffect(focused ? (configuration.isPressed ? 1.0 : (fullWidth ? 1.03 : 1.06)) : 1)
                .shadow(color: .black.opacity(focused ? 0.55 : 0), radius: 12, y: 10)
                .animation(.easeOut(duration: 0.15), value: focused)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}

/// A row of chips where one is chosen, e.g. Original / Persian dub or the app language.
struct ChoiceChips<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    var compact = false
    let label: (T) -> String

    var body: some View {
        HStack(spacing: 12) {
            ForEach(options, id: \.self) { option in
                Button { selection = option } label: { Text(label(option)) }
                    .buttonStyle(TVButtonStyle(selected: option == selection, compact: compact))
            }
        }
    }
}
