import SwiftUI

enum Route: Hashable {
    case title(TitleRef, backdropHash: String?)
    case list(title: String, path: String, categories: CategoryKind?)
    case subtitleSources
}

/// The tvOS top tab bar, as in the Apple TV app: Home, Series, Films, My List, Search, Settings.
struct MainTabView: View {
    @State private var tab = 0
    /// One navigation path per tab, so the tab bar can send a tab back to its first page.
    @State private var paths = Array(repeating: NavigationPath(), count: 6)

    var body: some View {
        tabs
            .background(TabBarClickObserver {
                // Clicking the tab you're on (it is the selected one) goes back to its first page.
                paths[tab] = NavigationPath()
            }.frame(width: 0, height: 0))
            .task { await TitleMarks.shared.refresh() }
            // Going Back to a page must never leave the top tab bar hidden.
            .onChange(of: paths) { TabBarReveal.showSoon() }
    }

    /// Choosing a tab in the top bar always shows that tab's own page: choosing the tab you're on goes
    /// back to its first page, and a tab you leave is reset so it opens on its first page next time.
    private var selection: Binding<Int> {
        Binding(
            get: { tab },
            set: { new in
                if new == tab {
                    paths[new] = NavigationPath()
                } else {
                    paths[tab] = NavigationPath()
                    tab = new
                }
            }
        )
    }

    private var tabs: some View {
        TabView(selection: selection) {
            NavStack(path: $paths[0]) { HomeView() }
                .tabItem { Label(L("خانه", "Home"), systemImage: "house") }.tag(0)
            NavStack(path: $paths[1]) { ListGridView(title: L("سریال‌ها", "Series"), path: SiteConfig.seriesPath, categories: .series) }
                .tabItem { Label(L("سریال‌ها", "Series"), systemImage: "tv") }.tag(1)
            NavStack(path: $paths[2]) { ListGridView(title: L("فیلم‌ها", "Films"), path: SiteConfig.filmsPath, categories: .film) }
                .tabItem { Label(L("فیلم‌ها", "Films"), systemImage: "film") }.tag(2)
            NavStack(path: $paths[3]) { ListGridView(title: L("لیست من", "My List"), path: SiteConfig.watchlistPath, categories: nil, reloadOnAppear: true,
                                    emptyText: L("هنوز چیزی به لیست خود اضافه نکرده‌اید", "Nothing on your list yet"), kindSwitch: true) }
                .tabItem { Label(L("لیست من", "My List"), systemImage: "bookmark") }.tag(3)
            NavStack(path: $paths[4]) { SearchView() }
                .tabItem { Label(L("جستجو", "Search"), systemImage: "magnifyingglass") }.tag(4)
            NavStack(path: $paths[5]) { SettingsView() }
                .tabItem { Label(L("تنظیمات", "Settings"), systemImage: "gearshape") }.tag(5)
        }
    }
}

/// One navigation stack per tab, with the app's routes.
struct NavStack<Content: View>: View {
    @Binding var path: NavigationPath
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationStack(path: $path) {
            content()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .title(let ref, let backdrop):
                        TitleDetailView(ref: ref, featuredBackdrop: backdrop)
                    case .list(let title, let path, let categories):
                        ListGridView(title: title, path: path, categories: categories)
                    case .subtitleSources:
                        SubtitleSourcesView()
                    }
                }
        }
    }
}
