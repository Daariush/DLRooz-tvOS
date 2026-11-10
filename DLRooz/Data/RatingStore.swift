import Foundation

/// IMDb scores for thumbnails whose list doesn't carry one (home rows, Continue Watching, suggestions).
/// Read from the title page (never the stream page, so nothing is marked as watched), at most three
/// at a time, and remembered so each title is looked up once.
@MainActor
final class RatingStore {
    static let shared = RatingStore()
    var site: SiteRepository?

    private let key = "ratings.cache"
    /// postId → score; 0 means "looked up, the site has no rating".
    private var scores: [String: Double]
    private var inFlight: [Int: Task<Double?, Never>] = [:]
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let maxConcurrent = 3

    private init() {
        scores = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
    }

    func rating(for ref: TitleRef) async -> Double? {
        if let known = scores[String(ref.postId)] { return known > 0 ? known : nil }
        if let task = inFlight[ref.postId] { return await task.value }
        let task = Task<Double?, Never> { [weak self] in
            guard let self else { return nil }
            await self.acquire()
            defer { self.release() }
            guard !Task.isCancelled, let site = self.site, let detail = try? await site.title(ref) else { return nil }
            self.remember(ref, score: detail.card.imdb?.score)
            return detail.card.imdb?.score
        }
        inFlight[ref.postId] = task
        let value = await task.value
        inFlight[ref.postId] = nil
        return value
    }

    func remember(_ ref: TitleRef, score: Double?) {
        scores[String(ref.postId)] = score ?? 0
        if scores.count > 3000 { scores = [:] }
        UserDefaults.standard.set(scores, forKey: key)
    }

    func clear() {
        scores = [:]
        UserDefaults.standard.removeObject(forKey: key)
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
