import Foundation

/// IMDb scores and real titles for thumbnails whose list doesn't carry them (home rows, Continue
/// Watching, suggestions). Read from the title page (never the stream page, so nothing is marked as
/// watched), at most three at a time, and remembered so each title is looked up once.
@MainActor
final class RatingStore {
    static let shared = RatingStore()
    var site: SiteRepository?

    private let key = "ratings.cache"
    private let titlesKey = "titles.cache"
    /// postId → score; 0 means "looked up, the site has no rating".
    private var scores: [String: Double]
    /// postId → the site's title.
    private var titles: [String: String]
    private var inFlight: [Int: Task<Void, Never>] = [:]
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let maxConcurrent = 3

    private init() {
        scores = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        titles = UserDefaults.standard.dictionary(forKey: titlesKey) as? [String: String] ?? [:]
    }

    func rating(for ref: TitleRef) async -> Double? {
        let id = String(ref.postId)
        if scores[id] == nil { await lookUp(ref) }
        guard let known = scores[id] else { return nil }
        return known > 0 ? known : nil
    }

    func title(for ref: TitleRef) async -> String? {
        let id = String(ref.postId)
        if titles[id] == nil { await lookUp(ref) }
        return titles[id]
    }

    func remember(_ ref: TitleRef, score: Double?, title: String? = nil) {
        let id = String(ref.postId)
        scores[id] = score ?? 0
        if scores.count > 3000 { scores = [:] }
        UserDefaults.standard.set(scores, forKey: key)
        if let title = title?.trimmed.nilIfBlank {
            titles[id] = title
            if titles.count > 3000 { titles = [:] }
            UserDefaults.standard.set(titles, forKey: titlesKey)
        }
    }

    func clear() {
        scores = [:]
        titles = [:]
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: titlesKey)
    }

    /// One title-page read per title, shared by everyone waiting on it.
    private func lookUp(_ ref: TitleRef) async {
        if let task = inFlight[ref.postId] { return await task.value }
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.acquire()
            defer { self.release() }
            guard !Task.isCancelled, let site = self.site, let detail = try? await site.title(ref) else { return }
            self.remember(ref, score: detail.card.imdb?.score, title: detail.card.title)
        }
        inFlight[ref.postId] = task
        await task.value
        inFlight[ref.postId] = nil
    }

    private func acquire() async {
        if running < maxConcurrent {
            running += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            running -= 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}
