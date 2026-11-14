import SwiftUI

/// A 2:3 poster with the tvOS card focus effect (lift, shadow, parallax-like highlight); title below.
struct PosterCard: View {
    let ref: TitleRef
    let title: String
    let posterHash: String?
    var subtitle: String?
    /// IMDb score when the list already carries it; otherwise it is looked up (and cached) from the title page.
    var rating: Double?
    /// Show "Movie" / "Series" before the subtitle line (search results mix both).
    var showKind = false
    @State private var fetched: Double?
    /// The real title, looked up when the list only gave the URL slug.
    @State private var realTitle: String?
    @ObservedObject private var marks = TitleMarks.shared
    @ObservedObject private var watch = WatchStore.shared

    private var needsTitle: Bool { title == ref.displayName || title == ref.slug }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.cardTitleGap) {
            NavigationLink(value: Route.title(ref, backdropHash: nil)) {
                RemoteImage(url: Theme.posterURL(posterHash))
                    .frame(width: Theme.posterSize.width, height: Theme.posterSize.height)
                    .background(Theme.surface)
                    .overlay(alignment: .topLeading) {
                        if let score = rating ?? fetched, score > 0 { RatingBadge(score: score).padding(10) }
                    }
                    .overlay(alignment: .topTrailing) {
                        if marks.isWatched(ref) || (ref.kind == .film && watch.filmFinished(ref.path)) {
                            WatchedBadge().padding(10)
                        }
                    }
                    .clipped()
            }
            .buttonStyle(.card)
            .contextMenu { WatchedMenuButton(ref: ref) }
            VStack(alignment: .leading, spacing: 4) {
                Text(realTitle ?? title).font(.control).lineLimit(1)
                    .environment(\.layoutDirection, .leftToRight)
                if showKind {
                    HStack(spacing: 10) {
                        KindTag(kind: ref.kind)
                        if let subtitle { Text(subtitle).font(.captionText).foregroundStyle(Theme.secondaryText) }
                    }
                    .lineLimit(1)
                } else if let subtitle {
                    Text(subtitle).font(.captionText).foregroundStyle(Theme.secondaryText).lineLimit(1)
                }
            }
            .frame(width: Theme.posterSize.width, alignment: .leading)
        }
        .task(id: ref) {
            if rating == nil { fetched = await RatingStore.shared.rating(for: ref) }
            if needsTitle { realTitle = await RatingStore.shared.title(for: ref) }
        }
    }
}

extension PosterCard {
    init(card: TitleCard, showKind: Bool = false) {
        self.init(ref: card.ref, title: card.title, posterHash: card.posterHash,
                  subtitle: card.episodeLabel ?? card.year.map { String($0) }, rating: card.imdb?.score,
                  showKind: showKind)
    }
}

/// The «watched» tick on a thumbnail or episode tile: top-right, in the icon's green-teal. The same
/// mark for films, series and episodes.
struct WatchedBadge: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 18, weight: .black))
            .foregroundStyle(.black)
            .frame(width: 34, height: 34)
            .background(Theme.watched, in: Circle())
            .accessibilityLabel(L("دیده شده", "Watched"))
    }
}

/// "Movie" / "Series" label under a search result.
struct KindTag: View {
    let kind: TitleKind
    var body: some View {
        Text(kind == .series ? L("سریال", "Series") : L("فیلم", "Movie"))
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(kind == .series ? Color.black : Color.white)
            .padding(.horizontal, 8).frame(height: 28)
            .background(kind == .series ? Color.white : Theme.accent,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// Long-press menu item on a thumbnail: mark the film or series watched / unwatched on the site.
struct WatchedMenuButton: View {
    let ref: TitleRef
    @ObservedObject private var marks = TitleMarks.shared

    var body: some View {
        let seen = marks.isWatched(ref)
        Button {
            Task { _ = await marks.setWatched(ref, !seen) }
        } label: {
            Label(seen ? L("علامت دیده نشده", "Mark as Unwatched") : L("علامت دیده شده", "Mark as Watched"),
                  systemImage: seen ? "eye.slash" : "eye")
        }
    }
}

/// The IMDb score on a thumbnail, in IMDb's yellow.
struct RatingBadge: View {
    let score: Double

    var body: some View {
        Badge(text: String(format: "%.1f", score), prefix: "IMDb", style: .imdb)
            .environment(\.layoutDirection, .leftToRight)
    }
}

/// Metacritic score (the site's «امتیاز منتقدین»).
struct MetacriticBadge: View {
    let value: String

    private var color: Color {
        let n = Int(value.before("/").filter(\.isNumber)) ?? 0
        if n >= 61 { return Color(red: 0.40, green: 0.80, blue: 0.20) }
        if n >= 40 { return Color(red: 1.0, green: 0.80, blue: 0.20) }
        return Color(red: 1.0, green: 0.0, blue: 0.0)
    }

    var body: some View {
        Badge(text: value.before("/"), prefix: "Metacritic", style: .critics(color))
            .environment(\.layoutDirection, .leftToRight)
    }
}

/// A titled horizontal row of cards.
struct CardRow<Item: Identifiable, Card: View>: View {
    let title: String
    let items: [Item]
    @ViewBuilder let card: (Item) -> Card

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            RowHeading(title)
                .padding(.horizontal, Theme.margin)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Theme.cardSpacing) {
                    ForEach(items) { card($0) }
                }
                .padding(.horizontal, Theme.margin)
                .padding(.vertical, Theme.focusRoom)
            }
        }
        .focusSection()
    }
}

/// A progress bar under Continue Watching cards.
struct ProgressBar: View {
    let value: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.25))
                Capsule().fill(Theme.accent).frame(width: g.size.width * max(0, min(1, value)))
            }
        }
        .frame(height: 6)
        .environment(\.layoutDirection, .leftToRight)
    }
}
