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

    /// tvOS puts the keyboard in a column beside the results (on the right in Persian), so the grid fits
    /// as many posters as the remaining width allows instead of a fixed five.
    private let columns = [GridItem(.adaptive(minimum: Theme.posterSize.width, maximum: Theme.posterSize.width),
                                    spacing: 48, alignment: .top)]

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 40) {
                if query.trimmed.isEmpty {
                    if !recent.isEmpty {
                        Text(L("جستجوهای اخیر", "Recent searches")).font(.title3.weight(.semibold))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 20) {
                                ForEach(recent, id: \.self) { q in
                                    Button(q) { query = q }
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
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 56) {
                        ForEach(results) { PosterCard(card: $0) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 48)
            .padding(.vertical, 30)
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
