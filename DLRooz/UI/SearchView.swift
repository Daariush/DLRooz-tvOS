import SwiftUI

/// The native tvOS search field and keyboard (dictation works from the Siri Remote), live results
/// as you type, and recent searches.
struct SearchView: View {
    @EnvironmentObject var model: AppModel
    @State private var query = ""
    @State private var results: [TitleCard] = []
    @State private var searching = false
    @State private var error: String?
    @State private var recent = LocalPrefs.recentSearches

    private let columns = Array(repeating: GridItem(.fixed(Theme.posterSize.width), spacing: 60), count: 5)

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 40) {
                if query.trimmed.isEmpty {
                    if !recent.isEmpty {
                        Text(L("جستجوهای اخیر", "Recent searches")).font(.title3.weight(.semibold))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 20) {
                                ForEach(recent, id: \.self) { q in
                                    Button(q) { query = q }.buttonStyle(.bordered)
                                }
                            }
                            .padding(.vertical, 20)
                        }
                    }
                    Text(L("نام انگلیسی فیلم یا سریال را جستجو کنید", "Search by the English title"))
                        .foregroundStyle(Theme.secondaryText)
                } else if searching && results.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
                } else if let error {
                    Text(error).foregroundStyle(Theme.secondaryText)
                } else if results.isEmpty {
                    Text(L("نتیجه‌ای پیدا نشد", "No results")).foregroundStyle(Theme.secondaryText)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 60) {
                        ForEach(results) { PosterCard(card: $0) }
                    }
                }
            }
            .padding(.horizontal, 80)
        }
        .searchable(text: $query, prompt: L("فیلم، سریال…", "Movies, series…"))
        .task(id: query) {
            let q = query.trimmed
            guard q.count >= 2 else { results = []; error = nil; return }
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            searching = true
            defer { searching = false }
            do {
                let found = try await model.site.search(q)
                guard !Task.isCancelled else { return }
                results = found
                error = nil
                if !found.isEmpty { LocalPrefs.addRecentSearch(q); recent = LocalPrefs.recentSearches }
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
