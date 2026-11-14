import Foundation

/// Local progress for one stream (episode or film).
struct WatchEntry: Codable, Hashable {
    var streamId: String
    var refPath: String
    var title: String
    var posterHash: String?
    var season: Int
    var episode: Int
    var isSeries: Bool
    var dubbed: Bool
    var position: Double
    var duration: Double
    var updatedAt: Date
    var finished: Bool
    var subtitleOffset: Double

    var ref: TitleRef? { TitleRef.fromPath(refPath) }
    var progress: Double { duration > 0 ? min(1, position / duration) : 0 }
}

/// Watch progress, kept in UserDefaults (tvOS apps have no durable file storage). Small by design:
/// the oldest entries are dropped beyond `limit`.
@MainActor
final class WatchStore: ObservableObject {
    static let shared = WatchStore()
    private let key = "watch.entries"
    private let limit = 400
    @Published private(set) var entries: [String: WatchEntry] = [:]
    /// Episodes marked watched (true) or unwatched (false) by hand; wins over progress and the site.
    @Published private(set) var marks: [String: Bool] = [:]
    private let marksKey = "watch.marks"

    static let resumeMin: Double = 30
    static let resumeRewind: Double = 3
    static let finishedFraction = 0.9

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: WatchEntry].self, from: data) {
            entries = decoded
        }
        marks = UserDefaults.standard.dictionary(forKey: marksKey) as? [String: Bool] ?? [:]
    }

    /// Watched state of an episode: a hand mark first, else the site's flag or local progress.
    func isWatched(_ streamId: String, playedOnSite: Bool) -> Bool {
        marks[streamId] ?? (playedOnSite || isWatched(streamId))
    }

    func mark(_ streamId: String, watched: Bool) {
        marks[streamId] = watched
        if !watched, var e = entries[streamId] {
            e.finished = false
            e.position = 0
            entries[streamId] = e
            persist()
        }
        if marks.count > 2000 { marks = [streamId: watched] }
        UserDefaults.standard.set(marks, forKey: marksKey)
    }

    func entry(_ streamId: String) -> WatchEntry? { entries[streamId] }

    func save(_ e: WatchEntry) {
        var e = e
        if e.duration > 0 && e.position >= e.duration * Self.finishedFraction { e.finished = true }
        entries[e.streamId] = e
        if entries.count > limit {
            let drop = entries.values.sorted { $0.updatedAt < $1.updatedAt }.prefix(entries.count - limit)
            for d in drop { entries[d.streamId] = nil }
        }
        persist()
    }

    func remove(refPath: String) {
        entries = entries.filter { $0.value.refPath != refPath }
        persist()
    }

    func clear() {
        entries = [:]
        marks = [:]
        UserDefaults.standard.removeObject(forKey: marksKey)
        persist()
    }

    /// Where playback should start: nothing for short or finished progress, else a few seconds early.
    func resumePosition(_ streamId: String) -> Double {
        guard let e = entries[streamId], !e.finished, e.position > Self.resumeMin,
              e.duration <= 0 || e.position < e.duration * Self.finishedFraction else { return 0 }
        return max(0, e.position - Self.resumeRewind)
    }

    func isWatched(_ streamId: String) -> Bool { entries[streamId]?.finished ?? false }

    /// The latest entry per title, newest first.
    var latestPerTitle: [WatchEntry] {
        var best: [String: WatchEntry] = [:]
        for e in entries.values where (best[e.refPath]?.updatedAt ?? .distantPast) < e.updatedAt { best[e.refPath] = e }
        return best.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: key) }
    }
}

/// Small preference stores.
enum LocalPrefs {
    /// Remembered audio choice per title (original vs Persian dub).
    static func dubbed(_ ref: TitleRef) -> Bool { UserDefaults.standard.bool(forKey: "dub.\(ref.postId)") }
    static func setDubbed(_ ref: TitleRef, _ v: Bool) { UserDefaults.standard.set(v, forKey: "dub.\(ref.postId)") }

    static var recentSearches: [String] {
        get { UserDefaults.standard.stringArray(forKey: "search.recent") ?? [] }
        set { UserDefaults.standard.set(Array(newValue.prefix(12)), forKey: "search.recent") }
    }

    static func addRecentSearch(_ q: String) {
        let t = q.trimmed
        guard t.count >= 2 else { return }
        recentSearches = [t] + recentSearches.filter { $0.lowercased() != t.lowercased() }
    }
}
