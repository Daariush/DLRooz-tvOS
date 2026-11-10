import SwiftUI

/// A site list (`/archive/...`, My List) as a poster grid with infinite scroll; Series and Films
/// pages also show the site menu's categories (dubbed, anime, Iranian, kids…) as chips.
struct ListGridView: View {
    let title: String
    let path: String
    let categories: CategoryKind?
    /// My List changes when titles are bookmarked elsewhere in the app: refresh each time it is shown.
    var reloadOnAppear = false
    var emptyText: String?

    @EnvironmentObject var model: AppModel
    @State private var items: [TitleCard] = []
    @State private var page = 0
    @State private var lastPage = 1
    @State private var loading = false
    @State private var error: String?
    @State private var chips: [SiteCategory] = []
    @State private var selectedPath: String?

    private var currentPath: String { selectedPath ?? path }
    private let columns = Array(repeating: GridItem(.fixed(Theme.posterSize.width), spacing: 60), count: 5)

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 30) {
                Text(title).font(.title2.bold()).padding(.horizontal, 80)
                if !chips.isEmpty { chipRow }
                if let error, items.isEmpty {
                    ErrorView(message: error) { Task { await reload() } }.frame(height: 500)
                } else if items.isEmpty && !loading && page > 0 {
                    Text(emptyText ?? L("چیزی پیدا نشد", "Nothing here"))
                        .foregroundStyle(Theme.secondaryText).frame(maxWidth: .infinity).padding(.top, 120)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 60) {
                        ForEach(items) { card in
                            PosterCard(card: card)
                                .onAppear { if card.ref == items.last?.ref { Task { await loadMore() } } }
                        }
                    }
                    .padding(.horizontal, 80)
                    if loading { ProgressView().frame(maxWidth: .infinity).padding() }
                }
            }
            .padding(.vertical, 40)
        }
        .task { if page == 0 { await reload() } }
        .onAppear { if reloadOnAppear && page > 0 && !loading { Task { await refresh() } } }
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                chip(L("همه", "All"), path: nil)
                ForEach(chips) { c in chip(UIStrings.joinPlurals(c.label), path: c.path) }
            }
            .padding(.horizontal, 80).padding(.vertical, 20)
        }
        .focusSection()
    }

    private func chip(_ label: String, path: String?) -> some View {
        Button {
            guard selectedPath != path else { return }
            selectedPath = path
            Task { await reload() }
        } label: {
            Text(label).font(.callout)
                .foregroundStyle(selectedPath == path ? Theme.accent : .primary)
        }
        .buttonStyle(.bordered)
    }

    private func reload() async {
        items = []
        page = 0
        lastPage = 1
        error = nil
        loading = true
        defer { loading = false }
        do {
            if categories != nil && chips.isEmpty && selectedPath == nil {
                let result = try await model.site.listWithCategories(currentPath)
                chips = result.categories.filter { $0.kind == categories || $0.kind == .both }
                apply(result.page)
            } else {
                apply(try await model.site.list(currentPath, page: 1))
            }
        } catch {
            self.error = error.localizedDescription
            page = 1
        }
    }

    /// Reloads page 1 without blanking the grid.
    private func refresh() async {
        guard let first = try? await model.site.list(currentPath, page: 1) else { return }
        items = first.items
        page = first.page
        lastPage = first.lastPage
    }

    private func loadMore() async {
        guard !loading, page < lastPage else { return }
        loading = true
        defer { loading = false }
        if let next = try? await model.site.list(currentPath, page: page + 1) { apply(next) }
    }

    private func apply(_ p: ListPage) {
        let known = Set(items.map(\.ref))
        items += p.items.filter { !known.contains($0.ref) }
        page = p.page
        lastPage = p.lastPage
    }
}
