import Foundation

/// Which films and series are marked «دیده شده» (watched) on the site. Read from the My List page and
/// from title pages, remembered between launches, and changed through the site's own watched toggle.
@MainActor
final class TitleMarks: ObservableObject {
    static let shared = TitleMarks()
    var site: SiteRepository?

    private let key = "marks.watched"
    @Published private(set) var watched: Set<Int>
    @Published private(set) var busy: Set<Int> = []

    private init() {
        watched = Set(UserDefaults.standard.array(forKey: key) as? [Int] ?? [])
    }

    func isWatched(_ ref: TitleRef) -> Bool { watched.contains(ref.postId) }

    /// Reads the user's watched list from the site.
    func refresh() async {
        guard let site, let entries = try? await site.userLists() else { return }
        watched = Set(entries.filter { $0.lists.contains("watchedList") }.map { $0.card.ref.postId })
        persist()
    }

    /// What a title page says.
    func note(_ ref: TitleRef, watched value: Bool?) {
        guard let value, !busy.contains(ref.postId) else { return }
        set(ref.postId, value)
    }

    /// Marks a title watched or unwatched on the site (the site's button is a toggle).
    func setWatched(_ ref: TitleRef, _ value: Bool) async -> String? {
        guard isWatched(ref) != value, !busy.contains(ref.postId), let site else { return nil }
        busy.insert(ref.postId)
        defer { busy.remove(ref.postId) }
        set(ref.postId, value)
        do {
            try await site.toggleWatchlist(postId: ref.postId, state: "watched", from: ref.path)
            return nil
        } catch {
            set(ref.postId, !value)
            return error.localizedDescription
        }
    }

    func clear() {
        watched = []
        persist()
    }

    private func set(_ id: Int, _ value: Bool) {
        if value { watched.insert(id) } else { watched.remove(id) }
        persist()
    }

    private func persist() { UserDefaults.standard.set(Array(watched), forKey: key) }
}
