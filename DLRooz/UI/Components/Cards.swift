import SwiftUI

/// A 2:3 poster with the tvOS card focus effect (lift, shadow, parallax-like highlight); title below.
struct PosterCard: View {
    let ref: TitleRef
    let title: String
    let posterHash: String?
    var subtitle: String?
    var badge: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: Route.title(ref, backdropHash: nil)) {
                RemoteImage(url: Theme.posterURL(posterHash))
                    .frame(width: Theme.posterSize.width, height: Theme.posterSize.height)
                    .overlay(alignment: .topLeading) {
                        if let badge { Pill(text: badge, filled: true).padding(10) }
                    }
                    .clipped()
            }
            .buttonStyle(.card)
            Text(title).font(.callout).lineLimit(1)
                .environment(\.layoutDirection, .leftToRight)
                .frame(width: Theme.posterSize.width, alignment: .leading)
            if let subtitle {
                Text(subtitle).font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
                    .frame(width: Theme.posterSize.width, alignment: .leading)
            }
        }
    }
}

extension PosterCard {
    init(card: TitleCard) {
        self.init(ref: card.ref, title: card.title, posterHash: card.posterHash,
                  subtitle: card.episodeLabel ?? card.year.map { String($0) },
                  badge: card.imdb.map { "IMDb \(String(format: "%.1f", $0.score))" })
    }
}

/// A titled horizontal row of cards.
struct CardRow<Item: Identifiable, Card: View>: View {
    let title: String
    var morePath: String?
    let items: [Item]
    @ViewBuilder let card: (Item) -> Card

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(title).font(.title3.weight(.semibold))
                Spacer()
                if let morePath {
                    NavigationLink(value: Route.list(title: title, path: morePath, categories: nil)) {
                        Text(L("همه", "See all")).font(.callout)
                    }
                    .buttonStyle(.borderless)
                }
            }
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
