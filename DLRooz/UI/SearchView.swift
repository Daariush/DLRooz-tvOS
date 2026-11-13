import SwiftUI

/// The native tvOS search field and keyboard (dictation works from the Siri Remote), live results
/// as you type, and recent searches.
/// Search state lives outside the view, so going Back from a title shows the same query and results
/// without searching again.
@MainActor
final class SearchState: ObservableObject {
    static let shared = SearchState()
    @Published var query = ""
    @Published var results: [TitleCard] = []
    @Published var searching = false
    @Published var error: String?
    @Published var recent = LocalPrefs.recentSearches
    /// The query `results` belong to.
    var searched = ""
    /// Which kind of result to show: nil = all.
    @Published var kind: TitleKind?
}

struct SearchView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var state = SearchState.shared
    /// Bumped by Try again to run the same search once more.
    @State private var attempt = 0

    /// tvOS puts the keyboard in a column beside the results (on the right in Persian), so the grid fits
    /// as many posters as the remaining width allows instead of a fixed five.
    private let columns = [GridItem(.adaptive(minimum: Theme.posterSize.width, maximum: Theme.posterSize.width),
                                    spacing: Theme.cardSpacing, alignment: .top)]

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 40) {
                if state.query.trimmed.isEmpty {
                    if !state.recent.isEmpty {
                        RowHeading(L("جستجوهای اخیر", "Recent searches"))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Theme.chipSpacing) {
                                ForEach(state.recent, id: \.self) { q in
                                    Button(q) { state.query = q }
                                }
                            }
                            .padding(.vertical, 20)
                        }
                    }
                    Text(L("نام انگلیسی فیلم یا سریال را جستجو کنید", "Search by the English title"))
                        .font(.bodyText).foregroundStyle(Theme.secondaryText)
                } else if state.searching && state.results.isEmpty {
                    LoadingView().frame(height: 400)
                } else if let error = state.error {
                    ErrorView(message: error) { state.searched = ""; attempt += 1 }
                        .frame(height: 500)
                } else if state.results.isEmpty {
                    EmptyStateView(icon: "magnifyingglass", message: L("نتیجه‌ای پیدا نشد", "No results"))
                } else {
                    let shown = state.kind == nil ? state.results : state.results.filter { $0.ref.kind == state.kind }
                    HStack(spacing: Theme.chipSpacing) {
                        kindChip(L("همه", "All"), nil, count: state.results.count)
                        kindChip(L("فیلم", "Movies"), .film, count: state.results.filter { $0.ref.kind == .film }.count)
                        kindChip(L("سریال", "Series"), .series, count: state.results.filter { $0.ref.kind == .series }.count)
                    }
                    .focusSection()
                    if shown.isEmpty {
                        EmptyStateView(icon: state.kind == .film ? "film" : "tv",
                                       message: state.kind == .film ? L("فیلمی پیدا نشد", "No movies found") : L("سریالی پیدا نشد", "No series found"))
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.gridRowSpacing) {
                            ForEach(shown) { PosterCard(card: $0) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The keyboard column already sits on one side, so the results keep the card gap from it
            // rather than the full page margin.
            .padding(.horizontal, Theme.cardSpacing)
            .padding(.vertical, Theme.focusRoom)
        }
        .searchable(text: $state.query, prompt: L("فیلم، سریال…", "Movies, series…"))
        .task(id: "\(attempt)|\(state.query)") {
            let q = state.query.trimmed
            guard q.count >= 2 else { state.results = []; state.error = nil; state.searched = ""; return }
            // Coming back from a title: the results on screen already match.
            guard q != state.searched else { return }
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            state.searching = true
            defer { state.searching = false }
            do {
                let found = try await model.site.search(q)
                guard !Task.isCancelled else { return }
                state.results = found
                state.searched = q
                state.error = nil
                if !found.isEmpty { LocalPrefs.addRecentSearch(q); state.recent = LocalPrefs.recentSearches }
            } catch is CancellationError {
            } catch {
                state.error = error.localizedDescription
            }
        }
    }

    /// Small All / Movies / Series switch above the results, with how many there are of each.
    private func kindChip(_ label: String, _ kind: TitleKind?, count: Int) -> some View {
        Button {
            state.kind = kind
        } label: {
            Text("\(label) (\(N(count)))")
        }
        .buttonStyle(TVButtonStyle(selected: state.kind == kind))
    }
}
