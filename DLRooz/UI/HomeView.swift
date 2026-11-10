import SwiftUI

/// Home: featured carousel, Continue Watching, then the site's rows. Opens instantly from the last
/// home page and refreshes in the background.
struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var watch: WatchStore
    @State private var home: HomePage?
    @State private var extraRows: [ExtraRow] = []
    @State private var error: String?
    @State private var featuredCards: [TitleRef: TitleCard] = [:]

    struct ExtraRow: Identifiable {
        let title: String
        let path: String
        var items: [TitleCard]
        var id: String { path }
    }

    /// Extra rows from list pages, as on the Android app (titles in Persian, from the site's menu).
    private static let extraSources: [(fa: String, en: String, path: String)] = [
        ("سریال‌های جدید", "New series", "/archive/category/new-tv-show/"),
        ("سریال‌های محبوب", "Popular series", "/archive/playlist/show/most-popular-tv-shows/"),
        ("سریال‌های برتر IMDb", "IMDb top series", "/archive/playlist/show/imdb-top-250-tv-series/"),
        ("دوبله فارسی", "Persian dubbed", "/archive/category/dubbed-films/"),
        ("مناسب کودکان", "For kids", "/archive/category/safe-for-children/"),
    ]

    var body: some View {
        Group {
            if let home {
                content(home)
            } else if let error {
                ErrorView(message: error) { Task { await load() } }
            } else {
                LoadingView()
            }
        }
        .task {
            if home == nil { home = model.cachedHome }
            await load()
        }
    }

    private func content(_ home: HomePage) -> some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 50) {
                if !home.featured.isEmpty { featuredRow(home.featured) }
                continueRow(home)
                ForEach(home.sections) { section in
                    CardRow(title: UIStrings.joinPlurals(section.title), morePath: section.morePath, items: section.items) {
                        PosterCard(card: $0)
                    }
                }
                ForEach(extraRows) { row in
                    CardRow(title: row.title, morePath: row.path, items: row.items) { PosterCard(card: $0) }
                }
            }
            .padding(.vertical, 40)
        }
    }

    private func featuredRow(_ items: [FeaturedItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 48) {
                ForEach(items, id: \.ref) { item in
                    NavigationLink(value: Route.title(item.ref, backdropHash: item.backdropHash)) {
                        ZStack(alignment: .bottomLeading) {
                            RemoteImage(url: ImageURLs.image(item.backdropHash, w: 1920, h: 1080))
                                .frame(width: 1200, height: 560)
                            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                            if let card = featuredCards[item.ref] {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(card.title).font(.title2.bold()).environment(\.layoutDirection, .leftToRight)
                                    Text(card.metaLine).font(.callout).foregroundStyle(Theme.secondaryText)
                                }
                                .padding(36)
                            }
                        }
                        .frame(width: 1200, height: 560)
                        .clipped()
                    }
                    .buttonStyle(.card)
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 30)
        }
        .focusSection()
    }

    /// Local progress (newest first), then the site's «recently streamed» titles not already shown.
    @ViewBuilder
    private func continueRow(_ home: HomePage) -> some View {
        let local = watch.latestPerTitle.filter { !$0.finished || $0.isSeries }.prefix(20)
        let localRefs = Set(local.compactMap { $0.ref })
        let server = home.recentlyStreamed.filter { !localRefs.contains($0.ref) }
        let items: [ContinueItem] = local.compactMap { e in e.ref.map { ContinueItem(ref: $0, entry: e, posterHash: e.posterHash) } }
            + server.map { ContinueItem(ref: $0.ref, entry: nil, posterHash: $0.posterHash) }
        if !items.isEmpty {
            CardRow(title: L("ادامه تماشا", "Continue Watching"), items: items) { item in
                ContinueCard(item: item)
            }
        }
    }

    private func load() async {
        do {
            let page = try await model.site.home()
            home = page
            error = nil
            model.rememberHome(page)
            var map: [TitleRef: TitleCard] = [:]
            for s in page.sections { for c in s.items { map[c.ref] = c } }
            featuredCards = map
        } catch {
            if home == nil { self.error = error.localizedDescription }
        }
        if extraRows.isEmpty {
            for src in Self.extraSources {
                if let page = try? await model.site.list(src.path) , !page.items.isEmpty {
                    extraRows.append(ExtraRow(title: L(src.fa, src.en), path: src.path, items: page.items))
                }
            }
        }
    }
}

struct ContinueItem: Identifiable {
    let ref: TitleRef
    let entry: WatchEntry?
    let posterHash: String?
    var id: TitleRef { ref }
}

/// Opens the title and, when there's local progress, resumes it right away.
struct ContinueCard: View {
    let item: ContinueItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: Route.title(item.ref, backdropHash: nil)) {
                ZStack(alignment: .bottom) {
                    RemoteImage(url: Theme.posterURL(item.posterHash))
                        .frame(width: Theme.posterSize.width, height: Theme.posterSize.height)
                    if let e = item.entry, !e.finished {
                        ProgressBar(value: e.progress).padding(14)
                    }
                }
                .frame(width: Theme.posterSize.width, height: Theme.posterSize.height)
                .clipped()
            }
            .buttonStyle(.card)
            Text(item.entry?.title ?? item.ref.slug.replacingOccurrences(of: "-", with: " ").capitalized)
                .font(.callout).lineLimit(1)
                .environment(\.layoutDirection, .leftToRight)
                .frame(width: Theme.posterSize.width, alignment: .leading)
            if let e = item.entry, e.isSeries {
                Text(UIStrings.episodeLabel(season: e.season, episode: e.episode)).font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

enum UIStrings {
    /// «سریال های» → «سریال‌های».
    static func joinPlurals(_ text: String) -> String {
        Rx(#"(\S) (ها|های|هایی)(?=\s|$)"#).replace(in: text, with: "$1\u{200C}$2")
    }

    static func episodeLabel(season: Int, episode: Int) -> String {
        L("فصل \(N(season)) · قسمت \(N(episode))", "S\(season) · E\(episode)")
    }

    static func clock(_ seconds: Double) -> String {
        let t = Int(max(0, seconds))
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}
