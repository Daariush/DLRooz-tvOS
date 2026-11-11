import SwiftUI

/// Title page for films and series: full-bleed backdrop, the facts, one adaptive Play button,
/// "Play with…" for other player apps, original/dub switch, My List, seasons and episodes, suggestions.
struct TitleDetailView: View {
    let ref: TitleRef
    var featuredBackdrop: String?

    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var watch: WatchStore

    @State private var detail: TitleDetail?
    @State private var error: String?
    @State private var dubbed = false
    @State private var season = 1
    @State private var inWatchlist: Bool?
    @State private var watchlistBusy = false
    @State private var starting = false
    @State private var playError: String?
    @State private var chooserEpisode: Episode?
    @FocusState private var playFocused: Bool

    var body: some View {
        ZStack {
            backdrop
            if let detail {
                content(detail)
            } else if let error {
                ErrorView(message: error) { Task { await load() } }
            } else {
                LoadingView()
            }
        }
        .ignoresSafeArea(edges: .top)
        .task { if detail == nil { await load() } }
        .confirmationDialog(L("پخش با…", "Play with…"), isPresented: Binding(
            get: { chooserEpisode != nil }, set: { if !$0 { chooserEpisode = nil } }
        ), presenting: chooserEpisode) { ep in
            Button(PlayerChoice.internal.label) { start(ep, with: .internal) }
            ForEach(PlayerChoice.externalApps.filter { $0 != .custom || !settings.customSchemeTemplate.trimmed.isEmpty }) { app in
                Button(app.label) { start(ep, with: app) }
            }
            Button(L("انصراف", "Cancel"), role: .cancel) {}
        }
        .alert(playError ?? "", isPresented: Binding(get: { playError != nil }, set: { if !$0 { playError = nil } })) {
            Button(L("باشه", "OK")) {}
        }
    }

    // MARK: Layout

    private var backdrop: some View {
        let url: URL? = featuredBackdrop.flatMap { ImageURLs.image($0, w: 1920, h: 1080) }
            ?? detail?.trailerThumbHash.flatMap { ImageURLs.trailerThumb($0, w: 1920, h: 1080) }
            ?? Theme.posterURL(detail?.card.posterHash, w: 1920, h: 1080)
        return ZStack {
            RemoteImage(url: url).blur(radius: featuredBackdrop == nil ? 12 : 0)
            LinearGradient(colors: [Theme.background.opacity(0.2), Theme.background.opacity(0.85), Theme.background],
                           startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [Theme.background.opacity(0.9), .clear], startPoint: .leading, endPoint: .trailing)
        }
        .ignoresSafeArea()
    }

    private func content(_ d: TitleDetail) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 50) {
                header(d).padding(.top, 260)
                if ref.kind == .series { episodes(d) }
                if !d.suggestions.isEmpty {
                    CardRow(title: L("آثار پیشنهادی", "You May Also Like"), items: d.suggestions.map { SuggestionItem(ref: $0, poster: d.suggestionPosters[$0]) }) { s in
                        PosterCard(ref: s.ref, title: s.ref.displayName, posterHash: s.poster)
                    }
                    .padding(.horizontal, -80)
                }
            }
            .padding(.horizontal, 80)
            .padding(.bottom, 60)
        }
    }

    private func header(_ d: TitleDetail) -> some View {
        let c = d.card
        return VStack(alignment: .leading, spacing: 22) {
            Text(c.title).font(.system(size: 64, weight: .bold)).lineLimit(2)
                .environment(\.layoutDirection, .leftToRight)
            HStack(spacing: 14) {
                if let r = c.imdb { RatingBadge(score: r.score) }
                if let meta = c.criticsScore.map({ "\($0)/100" }) { MetacriticBadge(value: meta) }
                if !d.catalog.dub.isEmpty { Pill(text: L("دوبله", "Dubbed")) }
                if d.catalog.main.first?.episodes.first?.subtitles.isEmpty == false { Pill(text: L("زیرنویس", "Subtitles")) }
                if let ch = d.channel { Pill(text: ch) }
                Text(c.metaLine).font(.callout).foregroundStyle(Theme.secondaryText)
            }
            if let status = c.status ?? c.episodeLabel { Text(status).font(.callout).foregroundStyle(Theme.secondaryText) }
            if let s = c.synopsis {
                Text(s).font(.body).lineLimit(4).frame(maxWidth: 1100, alignment: .leading)
            }
            if let dir = c.director {
                Text(L("کارگردان: ", "Director: ") + dir).font(.caption).foregroundStyle(Theme.secondaryText)
            }
            if !c.stars.isEmpty {
                Text(L("بازیگران: ", "Cast: ") + c.stars.prefix(5).joined(separator: ", ")).font(.caption)
                    .foregroundStyle(Theme.secondaryText).lineLimit(1)
            }
            if let award = d.awards.first { Text("🏆 " + award).font(.caption).foregroundStyle(Theme.secondaryText) }
            actions(d).padding(.top, 16)
        }
    }

    private func actions(_ d: TitleDetail) -> some View {
        HStack(spacing: 30) {
            if let ep = primaryEpisode(d) {
                Button { play(ep) } label: {
                    HStack {
                        if starting { ProgressView() } else { Image(systemName: "play.fill") }
                        Text(primaryLabel(d, ep))
                    }
                    .padding(.horizontal, 20)
                }
                .focused($playFocused)
                .disabled(starting)
                Button { chooserEpisode = ep } label: {
                    Label(L("پخش با…", "Play with…"), systemImage: "arrow.up.forward.app")
                }
                .disabled(starting)
            }
            if !d.catalog.dub.isEmpty {
                Picker(L("صدا", "Audio"), selection: $dubbed) {
                    Text(L("زبان اصلی", "Original")).tag(false)
                    Text(L("دوبله فارسی", "Persian dub")).tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 520)
                .onChange(of: dubbed) { _, v in
                    LocalPrefs.setDubbed(ref, v)
                    season = defaultSeason(d)
                }
            }
            Button { toggleWatchlist() } label: {
                Label(inWatchlist == true ? L("در لیست من", "In My List") : L("افزودن به لیست من", "Add to My List"),
                      systemImage: inWatchlist == true ? "bookmark.fill" : "bookmark")
            }
            .disabled(watchlistBusy)
        }
        .focusSection()
    }

    private func episodes(_ d: TitleDetail) -> some View {
        let seasons = dubbed ? d.catalog.dub : d.catalog.main
        let current = seasons.first { $0.number == season } ?? seasons.first
        return VStack(alignment: .leading, spacing: 24) {
            if seasons.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        ForEach(seasons) { s in
                            Button { season = s.number } label: {
                                Text(L("فصل \(N(s.number))", "Season \(s.number)"))
                            }
                            .buttonStyle(TVButtonStyle(selected: s.number == current?.number))
                        }
                    }
                    .padding(.vertical, 16)
                }
                .focusSection()
            }
            if let current {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 30) {
                            ForEach(current.episodes.sorted { $0.number < $1.number }) { ep in
                                EpisodeTile(episode: ep, watched: ep.played || watch.isWatched(ep.streamId),
                                            progress: watch.entry(ep.streamId)?.progress ?? 0) { play(ep) }
                                    .id(ep.streamId)
                            }
                        }
                        .padding(.vertical, 30)
                    }
                    .onAppear {
                        if let next = primaryEpisode(d), next.season == current.number { proxy.scrollTo(next.streamId, anchor: .center) }
                    }
                }
                .focusSection()
            }
        }
    }

    // MARK: Logic

    private func load() async {
        do {
            let d = try await model.site.title(ref)
            dubbed = !d.catalog.dub.isEmpty && LocalPrefs.dubbed(ref)
            detail = d
            RatingStore.shared.remember(ref, score: d.card.imdb?.score, title: d.card.title)
            inWatchlist = d.inWatchlist
            season = defaultSeason(d)
            error = nil
            try? await Task.sleep(nanoseconds: 150_000_000)
            playFocused = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func defaultSeason(_ d: TitleDetail) -> Int {
        primaryEpisode(d)?.season ?? (dubbed ? d.catalog.dub : d.catalog.main).first?.number ?? 1
    }

    /// Film: its stream. Series: the episode in progress, else the one after the last watched, else the first.
    private func primaryEpisode(_ d: TitleDetail) -> Episode? {
        let seasons = (dubbed ? d.catalog.dub : d.catalog.main).sorted { $0.number < $1.number }
        let all = seasons.flatMap { $0.episodes.sorted { $0.number < $1.number } }
        guard ref.kind == .series else { return all.first }
        let local = all.compactMap { e in watch.entry(e.streamId).map { (e, $0) } }
        if let inProgress = local.filter({ !$0.1.finished }).max(by: { $0.1.updatedAt < $1.1.updatedAt }) { return inProgress.0 }
        if let lastWatched = all.lastIndex(where: { $0.played || watch.isWatched($0.streamId) }) {
            return lastWatched + 1 < all.count ? all[lastWatched + 1] : all.first
        }
        return all.first
    }

    private func primaryLabel(_ d: TitleDetail, _ ep: Episode) -> String {
        let resume = watch.resumePosition(ep.streamId)
        if ref.kind == .film {
            if resume > 0, let e = watch.entry(ep.streamId), e.duration > 0 {
                let left = Int((e.duration - e.position) / 60)
                return L("ادامه (\(N(left)) دقیقه مانده)", "Resume (\(left) min left)")
            }
            return watch.isWatched(ep.streamId) || ep.played ? L("تماشای دوباره", "Watch Again") : L("پخش", "Play")
        }
        let label = UIStrings.episodeLabel(season: ep.season, episode: ep.number)
        return resume > 0 ? L("ادامه ", "Resume ") + label : L("پخش ", "Play ") + label
    }

    private func play(_ ep: Episode) {
        switch settings.playerChoice {
        case .ask: chooserEpisode = ep
        default: start(ep, with: settings.playerChoice)
        }
    }

    private func start(_ ep: Episode, with choice: PlayerChoice) {
        guard let d = detail, !starting else { return }
        starting = true
        let context = PlaybackContext(ref: ref, detail: d, dubbed: dubbed, episode: ep)
        Task {
            defer { starting = false }
            do {
                if choice == .internal || choice == .ask {
                    let controller = PlayerController(context: context, site: model.site, online: model.onlineSubtitles)
                    try await controller.start()
                    PlayerPresenter.shared.present(controller)
                } else {
                    // A fresh link right before handing over: it expires after about a minute.
                    let s = try await model.site.openStream(ep, ref: ref, dubbed: dubbed)
                    let ok = await ExternalPlayers.open(choice, streamURL: s.masterURL, template: settings.customSchemeTemplate)
                    if ok {
                        watch.save(WatchEntry(streamId: ep.streamId, refPath: ref.path, title: d.card.title, posterHash: d.card.posterHash,
                                              season: ep.season, episode: ep.number, isSeries: ref.kind == .series, dubbed: dubbed,
                                              position: 0, duration: 0, updatedAt: Date(), finished: false,
                                              subtitleOffset: watch.entry(ep.streamId)?.subtitleOffset ?? 0))
                    } else {
                        playError = L("\(choice.label) روی این Apple TV نصب نیست یا لینک را نپذیرفت",
                                      "\(choice.label) isn't installed on this Apple TV or refused the link")
                    }
                }
            } catch {
                playError = error.localizedDescription
            }
        }
    }

    /// The site's bookmark is a toggle. After toggling, the title page is read again so the button shows
    /// what the site actually stored (and a toggle that didn't stick is reported).
    private func toggleWatchlist() {
        guard !watchlistBusy else { return }
        let before = inWatchlist
        let wanted = !(before ?? false)
        inWatchlist = wanted
        watchlistBusy = true
        Task {
            defer { watchlistBusy = false }
            do {
                try await model.site.toggleWatchlist(postId: ref.postId, from: ref.path)
                if let confirmed = try? await model.site.title(ref).inWatchlist {
                    inWatchlist = confirmed
                    if confirmed != wanted {
                        playError = L("سایت تغییر لیست را ذخیره نکرد", "The site didn't save the change to your list")
                    }
                }
            } catch {
                inWatchlist = before
                playError = error.localizedDescription
            }
        }
    }
}

private struct SuggestionItem: Identifiable {
    let ref: TitleRef
    let poster: String?
    var id: TitleRef { ref }
}

/// A numbered episode tile: ✓ when watched (on the site or here), red bar when partly watched.
struct EpisodeTile: View {
    let episode: Episode
    let watched: Bool
    let progress: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottom) {
                VStack(spacing: 6) {
                    Text(L("قسمت", "Episode")).font(.caption2).foregroundStyle(Theme.secondaryText)
                    Text(N(episode.number)).font(.system(size: 52, weight: .bold))
                }
                .frame(width: 220, height: 140)
                if watched {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(12)
                } else if progress > 0.01 {
                    ProgressBar(value: progress).padding(12)
                }
            }
            .frame(width: 220, height: 140)
            .background(Color.white.opacity(0.08))
        }
        .buttonStyle(.card)
    }
}
