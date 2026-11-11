import SwiftUI

/// Home: featured carousel, Continue Watching, then the site's rows. Opens instantly from the last
/// home page and refreshes in the background.
struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var watch: WatchStore
    @ObservedObject private var marks = TitleMarks.shared
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
                    PagedRow(title: UIStrings.joinPlurals(section.title), path: section.morePath,
                             initial: section.items, firstPage: 0)
                }
                ForEach(extraRows) { row in
                    PagedRow(title: row.title, path: row.path, initial: row.items, firstPage: 1)
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
        // A title marked watched (long-press → Mark as Watched) leaves the row.
        let local = watch.latestPerTitle
            .filter { e in
                guard !e.finished || e.isSeries else { return false }
                guard let ref = e.ref else { return true }
                return !marks.isWatched(ref)
            }
            .prefix(20)
        let localRefs = Set(local.compactMap { $0.ref })
        let server = home.recentlyStreamed.filter { !localRefs.contains($0.ref) && !marks.isWatched($0.ref) }
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

/// A home row that keeps loading the next page of its list as you scroll towards its end.
struct PagedRow: View {
    @EnvironmentObject var model: AppModel
    let title: String
    let path: String?
    let initial: [TitleCard]
    /// The list page `initial` already covers: 0 for home-page rows (their own picks), 1 for list rows.
    let firstPage: Int
    @State private var more: [TitleCard] = []
    @State private var page: Int?
    @State private var lastPage = Int.max
    @State private var loading = false

    private var items: [TitleCard] {
        var seen = Set<TitleRef>()
        return (initial + more).filter { seen.insert($0.ref).inserted }
    }

    var body: some View {
        let all = items
        CardRow(title: title, items: all) { card in
            PosterCard(card: card)
                .onAppear {
                    if let i = all.firstIndex(where: { $0.ref == card.ref }), i >= all.count - 4 {
                        Task { await loadMore() }
                    }
                }
        }
    }

    /// Fetches the next list page; if every title on it is already in the row (home picks are often on
    /// page 1), it goes on to the following page so the row actually grows.
    private func loadMore() async {
        guard let path, !loading else { return }
        loading = true
        defer { loading = false }
        for _ in 0..<3 {
            let next = (page ?? firstPage) + 1
            guard next <= lastPage, next <= 15 else { return }
            guard let result = try? await model.site.list(path, page: next) else { return }
            let before = items.count
            page = next
            lastPage = result.items.isEmpty ? next : result.lastPage
            more += result.items
            if items.count > before { return }
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
    @State private var score: Double?
    @State private var name: String?
    @ObservedObject private var marks = TitleMarks.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.cardTitleGap) {
            NavigationLink(value: Route.title(item.ref, backdropHash: nil)) {
                ZStack(alignment: .bottom) {
                    RemoteImage(url: Theme.posterURL(item.posterHash))
                        .frame(width: Theme.posterSize.width, height: Theme.posterSize.height)
                    if let e = item.entry, !e.finished {
                        ProgressBar(value: e.progress).padding(14)
                    }
                }
                .frame(width: Theme.posterSize.width, height: Theme.posterSize.height)
                .overlay(alignment: .topLeading) {
                    if let score, score > 0 { RatingBadge(score: score).padding(10) }
                }
                .clipped()
            }
            .buttonStyle(.card)
            .overlay(alignment: .topTrailing) {
                if marks.isWatched(item.ref) { WatchedBadge().padding(10) }
            }
            .contextMenu { WatchedMenuButton(ref: item.ref) }
            .task(id: item.ref) {
                score = await RatingStore.shared.rating(for: item.ref)
                if item.entry?.title == nil { name = await RatingStore.shared.title(for: item.ref) }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.entry?.title ?? name ?? item.ref.displayName)
                    .font(.callout).lineLimit(1)
                    .environment(\.layoutDirection, .leftToRight)
                if let e = item.entry, e.isSeries {
                    Text(UIStrings.episodeLabel(season: e.season, episode: e.episode)).font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(width: Theme.posterSize.width, alignment: .leading)
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
