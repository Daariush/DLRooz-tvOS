import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var watch: WatchStore
    @State private var confirmSignOut = false
    @State private var cleared = false
    @State private var historyCleared = false

    var body: some View {
        HStack(alignment: .top, spacing: 60) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsHeader(L("حساب", "Account"))
                    SettingsInfoRow(title: L("نام کاربری", "Username"), value: model.username ?? "—")
                    SettingsRow(title: L("خروج از حساب", "Sign Out"), value: "") { confirmSignOut = true }

                    SettingsHeader(L("پخش", "Playback"))
                    CycleRow(title: L("پخش‌کننده پیش‌فرض", "Default player"), options: PlayerChoice.allCases,
                             selection: $settings.playerChoice) { $0.label }
                    if settings.playerChoice == .custom {
                        TextField(L("URL scheme برنامه دلخواه، مثل myplayer://play?url={url}", "Custom app URL, e.g. myplayer://play?url={url}"),
                                  text: $settings.customSchemeTemplate)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                    }
                    CycleRow(title: L("بافر پخش‌کننده داخلی", "Built-in player buffer"), options: AppSettings.bufferOptions,
                             selection: $settings.bufferMinutes) { L("\(N($0)) دقیقه جلوتر", "\($0) minutes ahead") }
                    CycleRow(title: L("بیشترین کیفیت شروع", "Start quality limit"), options: [0, 1080, 720, 480],
                             selection: $settings.maxHeight) { $0 == 0 ? L("خودکار", "Automatic") : "\($0)p" }
                    CycleRow(title: L("پخش خودکار قسمت بعد", "Autoplay next episode"), options: [true, false],
                             selection: $settings.autoplayNext) { $0 ? L("روشن", "On") : L("خاموش", "Off") }

                    SettingsHeader(L("زیرنویس", "Subtitles"))
                    CycleRow(title: L("زیرنویس پیش‌فرض", "Default subtitle"), options: SubtitlePreference.allCases,
                             selection: $settings.subtitlePreference) { $0.label }
                    CycleRow(title: L("اندازه", "Size"), options: AppSettings.sizeOptions,
                             selection: $settings.subtitleSize) { L("\(N($0))٪", "\($0)%") }
                    CycleRow(title: L("رنگ", "Colour"), options: SubtitleColor.allCases,
                             selection: $settings.subtitleColor) { $0.label }
                    CycleRow(title: L("پس‌زمینه", "Background"), options: AppSettings.backgroundOptions,
                             selection: $settings.subtitleBackground) { L("\(N($0))٪", "\($0)%") }
                    NavigationLink(value: Route.subtitleSources) {
                        SettingsRowLabel(title: L("منابع زیرنویس آنلاین", "Online subtitle sources"),
                                         value: "SubDL · SubSource · OpenSubtitles")
                    }

                    SettingsHeader(L("امتیازها", "Ratings"))
                    NavigationLink(value: Route.ratingSources) {
                        SettingsRowLabel(title: "Rotten Tomatoes",
                                         value: settings.omdbKey.isEmpty ? (ExternalRatings.builtInKey.isEmpty ? L("کلید OMDb لازم است", "Needs an OMDb key") : L("فعال (کلید داخلی)", "On (built-in key)")) : L("فعال", "On"))
                    }

                    SettingsHeader(L("برنامه", "App"))
                    CycleRow(title: L("زبان", "Language"), options: AppLanguage.allCases,
                             selection: $settings.language) { $0.label }
                    SettingsRow(title: L("پاک کردن حافظه موقت", "Clear cache"), value: cleared ? "✓" : "") {
                        ImageLoader.shared.clear()
                        URLCache.shared.removeAllCachedResponses()
                        RatingStore.shared.clear()
                        ExternalRatings.shared.clear()
                        cleared = true
                    }
                    SettingsRow(title: L("پاک کردن سابقه تماشا در این دستگاه", "Clear watch history on this device"),
                                value: historyCleared ? "✓" : "") {
                        watch.clear()
                        historyCleared = true
                    }
                    SettingsInfoRow(title: L("نسخه", "Version"),
                                    value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    Text(L("روی هر گزینه کلیک کنید تا مقدار بعدی انتخاب شود.", "Click an option to switch to its next value."))
                        .font(.caption).foregroundStyle(Theme.secondaryText).padding(.top, 10)
                }
                .padding(.vertical, 40)
                .padding(.horizontal, 20)
            }
            SubtitlePreview().frame(width: 640).padding(.top, 60)
        }
        .padding(.horizontal, 60)
        .alert(L("از حساب خارج می‌شوید؟", "Sign out?"), isPresented: $confirmSignOut) {
            Button(L("خروج", "Sign Out"), role: .destructive) { Task { await model.signOut() } }
            Button(L("انصراف", "Cancel"), role: .cancel) {}
        }
    }
}

// Settings rows are plain buttons. Navigation-style pickers inside a Form pushed a blank screen on tvOS,
// so every option changes in place: a click moves to the next value.

struct SettingsHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.headline).foregroundStyle(Theme.secondaryText).padding(.top, 26)
    }
}

struct SettingsRowLabel: View {
    let title: String
    let value: String
    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 30)
            Text(value).foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
    }
}

struct SettingsRow: View {
    let title: String
    let value: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { SettingsRowLabel(title: title, value: value) }
    }
}

struct SettingsInfoRow: View {
    let title: String
    let value: String
    var body: some View {
        SettingsRowLabel(title: title, value: value).padding(.horizontal, 40).padding(.vertical, 12)
    }
}

/// A row that moves to the next option on each click (wrapping around).
struct CycleRow<T: Equatable>: View {
    let title: String
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String

    var body: some View {
        SettingsRow(title: title, value: label(selection)) {
            guard !options.isEmpty else { return }
            let i = options.firstIndex(of: selection) ?? -1
            selection = options[(i + 1) % options.count]
        }
    }
}

/// Live preview of the subtitle style.
struct SubtitlePreview: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [.indigo.opacity(0.6), .black], startPoint: .top, endPoint: .bottom)
            Text("زندگی همین لحظه‌هاست\nLife is these moments")
                .font(.custom("Vazirmatn-Bold", size: 30 * CGFloat(settings.subtitleSize) / 100))
                .multilineTextAlignment(.center)
                .foregroundStyle(settings.subtitleColor.color)
                .shadow(color: .black, radius: 3, y: 1)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.black.opacity(Double(settings.subtitleBackground) / 100))
                .padding(.bottom, 30)
        }
        .frame(height: 360)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// API keys and logins for the online subtitle sites (stored in the Keychain).
struct SubtitleSourcesView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var model: AppModel
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                Text(L("منابع زیرنویس آنلاین", "Online subtitle sources")).font(.title2.bold())
                Text(L("وقتی سایت زیرنویس مناسب ندارد، از این سایت‌ها جستجو می‌شود. کلیدها در Keychain همین دستگاه می‌مانند.",
                       "Searched when the site has no suitable subtitle. Keys stay in this Apple TV's Keychain."))
                    .font(.caption).foregroundStyle(Theme.secondaryText)

                SettingsHeader("SubDL — " + SubtitleSource.subdl.signupURL)
                SecureField(L("کلید API", "API key"), text: $settings.subdlKey)

                SettingsHeader("SubSource — " + SubtitleSource.subsource.signupURL)
                SecureField(L("کلید API", "API key"), text: $settings.subsourceKey)

                SettingsHeader("OpenSubtitles — " + SubtitleSource.opensubtitles.signupURL)
                SecureField(L("کلید API", "API key"), text: $settings.openSubtitlesKey)
                TextField(L("نام کاربری (برای دانلود)", "Username (for downloads)"), text: $settings.openSubtitlesUser)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                SecureField(L("رمز عبور (برای دانلود)", "Password (for downloads)"), text: $settings.openSubtitlesPassword)

                SettingsHeader(L("زبان‌های جستجو", "Languages to search"))
                langRow(L("فارسی", "Persian"), "fa")
                langRow(L("انگلیسی", "English"), "en")
                langRow(L("عربی", "Arabic"), "ar")
                langRow(L("ترکی", "Turkish"), "tr")

                SettingsHeader(L("آزمایش", "Test"))
                SettingsRow(title: testing ? L("در حال آزمایش…", "Testing…") : L("آزمایش کلیدها با یک فیلم", "Test the keys with a film"),
                            value: "") { if !testing { test() } }
                if let testResult { Text(testResult).font(.caption).padding(.horizontal, 20) }
            }
            .padding(.horizontal, 200)
            .padding(.vertical, 40)
        }
    }

    private func langRow(_ title: String, _ code: String) -> some View {
        let binding = lang(code)
        return SettingsRow(title: title, value: binding.wrappedValue ? L("روشن", "On") : L("خاموش", "Off")) {
            binding.wrappedValue.toggle()
        }
    }

    private func lang(_ code: String) -> Binding<Bool> {
        Binding(
            get: { settings.onlineSubtitleLanguages.contains(code) },
            set: { on in
                var l = settings.onlineSubtitleLanguages.filter { $0 != code }
                if on { l.append(code) }
                settings.onlineSubtitleLanguages = l.isEmpty ? ["en"] : l
            }
        )
    }

    /// Searches every configured site for Inception (tt1375666) and reports counts per site.
    private func test() {
        testing = true
        let q = SubtitleQuery(imdbID: "tt1375666", title: "Inception", year: 2010, season: nil, episode: nil,
                              languages: settings.onlineSubtitleLanguages)
        let creds = SubtitleCredentials.load()
        Task {
            var lines: [String] = []
            for source in SubtitleSource.allCases {
                guard creds.isConfigured(source) else {
                    lines.append("\(source.rawValue): " + L("تنظیم نشده", "not set up"))
                    continue
                }
                do {
                    let n = try await model.onlineSubtitles.search(source, q, creds: creds).count
                    lines.append("\(source.rawValue): ✓ " + L("\(N(n)) زیرنویس", "\(n) subtitles"))
                } catch {
                    lines.append("\(source.rawValue): ✗ \(error.localizedDescription)")
                }
            }
            testResult = lines.joined(separator: "\n")
            testing = false
        }
    }
}

/// The OMDb key used to show Rotten Tomatoes scores on title pages.
struct RatingSourcesView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Rotten Tomatoes").font(.title2.bold())
                Text(L("سایت دی‌ال‌روز فقط امتیاز IMDb و منتقدین (Metacritic) را دارد. امتیاز Rotten Tomatoes از OMDb گرفته می‌شود که یک کلید رایگان می‌خواهد (روزانه ۱۰۰۰ درخواست): omdbapi.com/apikey.aspx",
                       "DLRooz only shows IMDb and critics (Metacritic) scores. Rotten Tomatoes scores come from OMDb, which needs a free key (1,000 lookups a day): omdbapi.com/apikey.aspx"))
                    .font(.caption).foregroundStyle(Theme.secondaryText)
                SettingsHeader("OMDb")
                SecureField(L("کلید API", "API key"), text: $settings.omdbKey)
                SettingsRow(title: testing ? L("در حال آزمایش…", "Testing…") : L("آزمایش کلید", "Test the key"), value: "") {
                    guard !testing else { return }
                    testing = true
                    Task {
                        let error = await ExternalRatings.shared.test(key: settings.omdbKey.trimmed)
                        testResult = error.map { "✗ " + $0 } ?? "✓ " + L("کلید کار می‌کند", "The key works")
                        testing = false
                    }
                }
                if let testResult { Text(testResult).font(.caption).padding(.horizontal, 20) }
            }
            .padding(.horizontal, 200)
            .padding(.vertical, 40)
        }
    }
}
