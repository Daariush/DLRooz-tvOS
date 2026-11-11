import SwiftUI

/// A 2:3 poster with the tvOS card focus effect (lift, shadow, parallax-like highlight); title below.
struct PosterCard: View {
    let ref: TitleRef
    let title: String
    let posterHash: String?
    var subtitle: String?
    /// IMDb score when the list already carries it; otherwise it is looked up (and cached) from the title page.
    var rating: Double?
    @State private var fetched: Double?
    /// The real title, looked up when the list only gave the URL slug.
    @State private var realTitle: String?

    private var needsTitle: Bool { title == ref.displayName || title == ref.slug }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.cardTitleGap) {
            NavigationLink(value: Route.title(ref, backdropHash: nil)) {
                RemoteImage(url: Theme.posterURL(posterHash))
                    .frame(width: Theme.posterSize.width, height: Theme.posterSize.height)
                    .overlay(alignment: .topLeading) {
                        if let score = rating ?? fetched, score > 0 { RatingBadge(score: score).padding(10) }
                    }
                    .clipped()
            }
            .buttonStyle(.card)
            VStack(alignment: .leading, spacing: 4) {
                Text(realTitle ?? title).font(.callout).lineLimit(1)
                    .environment(\.layoutDirection, .leftToRight)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
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
    init(card: TitleCard) {
        self.init(ref: card.ref, title: card.title, posterHash: card.posterHash,
                  subtitle: card.episodeLabel ?? card.year.map { String($0) }, rating: card.imdb?.score)
    }
}

/// The IMDb score on a thumbnail, in IMDb's yellow.
struct RatingBadge: View {
    let score: Double

    var body: some View {
        HStack(spacing: 6) {
            Text("IMDb").font(.system(size: 17, weight: .heavy))
            Text(String(format: "%.1f", score)).font(.system(size: 22, weight: .bold))
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Color(red: 0.96, green: 0.77, blue: 0.09), in: RoundedRectangle(cornerRadius: 8))
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
        HStack(spacing: 6) {
            Text("Metacritic").font(.system(size: 17, weight: .heavy))
            Text(value.before("/")).font(.system(size: 22, weight: .bold))
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(color, in: RoundedRectangle(cornerRadius: 8))
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
            Text(title).font(.title3.weight(.semibold))
                .padding(.horizontal, 80)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 40) {
                    ForEach(items) { card($0) }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 30)
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
