import SwiftUI

enum Route: Hashable {
    case title(TitleRef, backdropHash: String?)
    case list(title: String, path: String, categories: CategoryKind?)
    case subtitleSources
}

/// The tvOS top tab bar, as in the Apple TV app: Home, Series, Films, My List, Search, Settings.
struct MainTabView: View {
    @State private var tab = 0

    var body: some View {
        tabs.task { await TitleMarks.shared.refresh() }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            NavStack { HomeView() }
                .tabItem { Label(L("خانه", "Home"), systemImage: "house") }.tag(0)
            NavStack { ListGridView(title: L("سریال‌ها", "Series"), path: SiteConfig.seriesPath, categories: .series) }
                .tabItem { Label(L("سریال‌ها", "Series"), systemImage: "tv") }.tag(1)
            NavStack { ListGridView(title: L("فیلم‌ها", "Films"), path: SiteConfig.filmsPath, categories: .film) }
                .tabItem { Label(L("فیلم‌ها", "Films"), systemImage: "film") }.tag(2)
            NavStack { ListGridView(title: L("لیست من", "My List"), path: SiteConfig.watchlistPath, categories: nil, reloadOnAppear: true,
                                    emptyText: L("هنوز چیزی به لیست خود اضافه نکرده‌اید", "Nothing on your list yet")) }
                .tabItem { Label(L("لیست من", "My List"), systemImage: "bookmark") }.tag(3)
            NavStack { SearchView() }
                .tabItem { Label(L("جستجو", "Search"), systemImage: "magnifyingglass") }.tag(4)
            NavStack { SettingsView() }
                .tabItem { Label(L("تنظیمات", "Settings"), systemImage: "gearshape") }.tag(5)
        }
    }
}

/// One navigation stack per tab, with the app's routes.
struct NavStack<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var path = NavigationPath()

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
