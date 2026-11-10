import AVFoundation
import AVKit
import Combine
import UIKit

/// What is being played.
struct PlaybackContext {
    let ref: TitleRef
    let detail: TitleDetail
    let dubbed: Bool
    var episode: Episode

    var seasons: [Season] { dubbed ? detail.catalog.dub : detail.catalog.main }
    var isSeries: Bool { ref.kind == .series }
}

enum SubtitleSelection: Equatable {
    case off
    case site(SiteSubtitleTrack)
    case online(OnlineSubtitle)
}

/// Drives the built-in player: AVPlayer with the buffer-ahead setting, site and online subtitles drawn
/// by the app, quality / speed / sync menus in the transport bar, resume, and next-episode autoplay.
@MainActor
final class PlayerController: NSObject, ObservableObject {
    let player = AVPlayer()
    private(set) var context: PlaybackContext
    private let site: SiteRepository
    private let online: OnlineSubtitles
    private let settings = AppSettings.shared
    private let watch = WatchStore.shared

    @Published private(set) var session: StreamSession?
    @Published private(set) var subtitle: SubtitleSelection = .off
    @Published private(set) var subtitleOffset: Double = 0
    @Published private(set) var onlineResults: [OnlineSubtitle] = []
    @Published private(set) var onlineState: OnlineState = .idle
    @Published private(set) var currentCues: [SubCue] = []
    @Published private(set) var speed: Float = 1
    /// Peak bitrate cap in kbps; nil = automatic.
    @Published private(set) var qualityKbps: Int?
    @Published var errorMessage: String?

    enum OnlineState: Equatable { case idle, searching, done, failed(String) }

    /// Called whenever menus need rebuilding (selection changed, results arrived).
    var onStateChange: (() -> Void)?
    var onFinished: (() -> Void)?

    private var timeline = SubtitleTimeline([])
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var startAt: Double = 0
    private var lastSave = Date.distantPast
    private var subtitleTask: Task<Void, Never>?

    init(context: PlaybackContext, site: SiteRepository, online: OnlineSubtitles) {
        self.context = context
        self.site = site
        self.online = online
        super.init()
        player.automaticallyWaitsToMinimizeStalling = true
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) { [weak self] t in
            MainActor.assumeIsolated { self?.tick(t.seconds) }
        }
    }

    func tearDown() {
        saveProgress(force: true)
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        statusObservation = nil
        subtitleTask?.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    // MARK: Loading

    /// Fetches a fresh stream page (its link lives about a minute) and starts playback.
    func start() async throws {
        let s = try await site.openStream(context.episode, ref: context.ref, dubbed: context.dubbed)
        session = s
        startAt = watch.resumePosition(s.streamId)
        subtitleOffset = watch.entry(s.streamId)?.subtitleOffset ?? 0
        try load(s)
        chooseInitialSubtitle(s)
        searchOnlineSubtitles()
        onStateChange?()
    }

    private func load(_ s: StreamSession) throws {
        guard let url = URL(string: s.masterURL) else { throw SiteError.parse("m3u8") }
        var options: [String: Any] = [
            AVURLAssetHTTPCookiesKey: site.http.jar.httpCookies(for: url),
            AVURLAssetHTTPUserAgentKey: SiteConfig.userAgent,
        ]
        options[AVURLAssetPreferPreciseDurationAndTimingKey] = false
        let asset = AVURLAsset(url: url, options: options)
        let item = AVPlayerItem(asset: asset)
        applyBuffer(to: item)
        // Start on the first variant in the playlist (fast start); adaptive bitrate takes over from there.
        item.startsOnFirstEligibleVariant = true
        if settings.maxHeight > 0 { item.preferredMaximumResolution = CGSize(width: settings.maxHeight * 16 / 9, height: settings.maxHeight) }
        if let kbps = qualityKbps { item.preferredPeakBitRate = Double(kbps) * 1000 * 1.2 }
        item.externalMetadata = metadata()

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in self?.statusChanged(item) }
        }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.playedToEnd() }
        }
        player.replaceCurrentItem(with: item)
    }

    /// How far ahead the player downloads: the Settings choice of 5, 10 or 20 minutes.
    private func applyBuffer(to item: AVPlayerItem) {
        item.preferredForwardBufferDuration = TimeInterval(settings.bufferMinutes * 60)
    }

    func setBuffer(minutes: Int) {
        settings.bufferMinutes = minutes
        if let item = player.currentItem { applyBuffer(to: item) }
        onStateChange?()
    }

    /// Seconds of video already downloaded ahead of the play head.
    var bufferedAhead: Double {
        guard let item = player.currentItem else { return 0 }
        let now = item.currentTime().seconds
        for v in item.loadedTimeRanges {
            let r = v.timeRangeValue
            if r.start.seconds <= now + 1 && r.end.seconds >= now { return max(0, r.end.seconds - now) }
        }
        return 0
    }

    private func statusChanged(_ item: AVPlayerItem) {
        guard item === player.currentItem else { return }
        switch item.status {
        case .readyToPlay:
            Task { await selectAudio(item) }
            if startAt > 0 {
                let target = CMTime(seconds: startAt, preferredTimescale: 600)
                startAt = 0
                player.seek(to: target) { [weak self] _ in
                    Task { @MainActor in self?.play() }
                }
            } else {
                play()
            }
        case .failed:
            let msg = item.error?.localizedDescription ?? "error"
            errorMessage = L("پخش با مشکل روبه‌رو شد", "Playback failed") + "\n" + msg
            if let s = session {
                Task { await site.reportStreamError(streamId: s.streamId, event: "error", message: msg) }
            }
        default:
            break
        }
    }

    private func play() {
        player.defaultRate = speed
        player.playImmediately(atRate: speed)
    }

    /// Dubbed titles start on the Persian dub; otherwise the stream's default (original) audio.
    private func selectAudio(_ item: AVPlayerItem) async {
        guard let group = try? await item.asset.loadMediaSelectionGroup(for: .audible) else { return }
        let options = group.options
        let wanted: AVMediaSelectionOption?
        if context.dubbed {
            wanted = options.first { $0.displayName.lowercased().contains("dub") || $0.extendedLanguageTag?.hasPrefix("fa") == true }
        } else {
            wanted = options.first { $0.displayName.lowercased().contains("original") && !$0.displayName.contains("6CH") }
                ?? options.first { !$0.displayName.lowercased().contains("dub") }
        }
        if let wanted { item.select(wanted, in: group) }
        // Subtitles are drawn by the app (its own menu), so the stream's own text tracks stay off.
        if let legible = try? await item.asset.loadMediaSelectionGroup(for: .legible) {
            item.select(nil, in: legible)
        }
    }

    private func metadata() -> [AVMetadataItem] {
        func item(_ id: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
            let m = AVMutableMetadataItem()
            m.identifier = id
            m.value = value as NSString
            m.extendedLanguageTag = "und"
            return m
        }
        var out = [item(.commonIdentifierTitle, context.detail.card.title)]
        if context.isSeries {
            out.append(item(.iTunesMetadataTrackSubTitle, UIStrings.episodeLabel(season: context.episode.season, episode: context.episode.number)))
        }
        if let synopsis = context.detail.card.synopsis { out.append(item(.commonIdentifierDescription, synopsis)) }
        return out
    }

    // MARK: Time

    private func tick(_ t: Double) {
        guard t.isFinite else { return }
        let cues = timeline.isEmpty ? [] : timeline.at(t - subtitleOffset)
        if cues != currentCues { currentCues = cues }
        if Date().timeIntervalSince(lastSave) > 5 { saveProgress(force: false) }
    }

    func saveProgress(force: Bool) {
        guard let s = session, let item = player.currentItem else { return }
        let pos = item.currentTime().seconds
        let dur = item.duration.seconds
        guard pos.isFinite, pos > 1 || force else { return }
        if !force && player.rate == 0 { return }
        lastSave = Date()
        watch.save(WatchEntry(
            streamId: s.streamId, refPath: context.ref.path, title: context.detail.card.title,
            posterHash: context.detail.card.posterHash, season: context.episode.season, episode: context.episode.number,
            isSeries: context.isSeries, dubbed: context.dubbed, position: pos.isFinite ? pos : 0,
            duration: dur.isFinite ? dur : 0, updatedAt: Date(), finished: false, subtitleOffset: subtitleOffset))
    }

    private func playedToEnd() {
        saveProgress(force: true)
        if settings.autoplayNext, nextEpisode != nil {
            Task { await playNext() }
        } else {
            onFinished?()
        }
    }

    var nextEpisode: Episode? {
        context.isSeries ? context.seasons.nextEpisode(after: context.episode.streamId) : nil
    }

    func playNext() async {
        guard let next = nextEpisode else { return }
        saveProgress(force: true)
        context.episode = next
        currentCues = []
        timeline = SubtitleTimeline([])
        onlineResults = []
        onlineState = .idle
        do {
            try await start()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Playback options

    func setSpeed(_ s: Float) {
        speed = s
        player.defaultRate = s
        if player.rate != 0 { player.rate = s }
        onStateChange?()
    }

    func setQuality(kbps: Int?) {
        qualityKbps = kbps
        player.currentItem?.preferredPeakBitRate = kbps.map { Double($0) * 1000 * 1.2 } ?? 0
        if kbps != nil { player.currentItem?.preferredMaximumResolution = .zero }
        onStateChange?()
    }

    /// The site's labels, highest first: (kbps, "1080 [ 2.48 GB ]").
    var qualityOptions: [(Int, String)] {
        (session?.qualityLabels ?? [:]).sorted { $0.key > $1.key }.map { ($0.key, $0.value) }
    }

    func shiftSubtitles(by delta: Double) {
        subtitleOffset = delta == 0 ? 0 : subtitleOffset + delta
        saveProgress(force: true)
        onStateChange?()
    }

    // MARK: Subtitles

    var siteTracks: [SiteSubtitleTrack] { session?.subtitles ?? [] }

    private func chooseInitialSubtitle(_ s: StreamSession) {
        let tracks = s.subtitles
        func find(_ label: String) -> SiteSubtitleTrack? { tracks.first { $0.label.trimmed == label } }
        let pick: SiteSubtitleTrack?
        if context.dubbed {
            pick = find("Farsi for Dub")
        } else {
            switch settings.subtitlePreference {
            case .fa: pick = find("Farsi") ?? find("English + Farsi")
            case .en: pick = find("English")
            case .dual: pick = find("English + Farsi") ?? find("Farsi")
            case .off: pick = nil
            }
        }
        if let pick { select(.site(pick)) } else { select(.off) }
    }

    func select(_ sel: SubtitleSelection) {
        subtitle = sel
        subtitleTask?.cancel()
        timeline = SubtitleTimeline([])
        currentCues = []
        onStateChange?()
        guard sel != .off else { return }
        let site = self.site, online = self.online
        let query = subtitleQuery
        subtitleTask = Task { [weak self] in
            do {
                let text: String
                switch sel {
                case .site(let track): text = try await site.subtitle(track.url)
                case .online(let sub): text = try await online.download(sub, query: query, creds: SubtitleCredentials.load())
                case .off: return
                }
                let cues = SubtitleParser.parse(text)
                guard !Task.isCancelled, let self, self.subtitle == sel else { return }
                self.timeline = SubtitleTimeline(cues)
                if cues.isEmpty { self.errorMessage = L("زیرنویس قابل خواندن نبود", "Couldn't read that subtitle file") }
            } catch is CancellationError {
            } catch {
                guard let self, self.subtitle == sel else { return }
                self.errorMessage = error.localizedDescription
                self.subtitle = .off
                self.onStateChange?()
            }
        }
    }

    var subtitleQuery: SubtitleQuery {
        SubtitleQuery(imdbID: context.detail.imdbID, title: context.detail.card.title, year: context.detail.card.year,
                      season: context.isSeries ? context.episode.season : nil,
                      episode: context.isSeries ? context.episode.number : nil,
                      languages: settings.onlineSubtitleLanguages)
    }

    /// Looks on SubDL / SubSource / OpenSubtitles in the background, for the subtitle menu.
    func searchOnlineSubtitles() {
        let creds = SubtitleCredentials.load()
        guard SubtitleSource.allCases.contains(where: creds.isConfigured) else { onlineState = .idle; return }
        onlineState = .searching
        let q = subtitleQuery
        let online = self.online
        let streamId = context.episode.streamId
        Task { [weak self] in
            let (results, errors) = await online.searchAll(q, creds: creds)
            guard let self, self.context.episode.streamId == streamId else { return }
            self.onlineResults = results
            self.onlineState = results.isEmpty && !errors.isEmpty ? .failed(errors.joined(separator: "\n")) : .done
            // The site has no subtitle in the preferred language: use the best online one.
            if self.subtitle == .off, self.settings.subtitlePreference != .off, !self.context.dubbed,
               let lang = self.preferredLanguage, let best = results.first(where: { $0.language == lang }) {
                self.select(.online(best))
            }
            self.onStateChange?()
        }
    }

    private var preferredLanguage: String? {
        switch settings.subtitlePreference {
        case .fa, .dual: return "fa"
        case .en: return "en"
        case .off: return nil
        }
    }
}
