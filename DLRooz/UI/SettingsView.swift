import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var watch: WatchStore
    @State private var confirmSignOut = false
    @State private var cleared = false

    var body: some View {
        HStack(alignment: .top, spacing: 60) {
            Form {
                Section(L("حساب", "Account")) {
                    LabeledContent(L("نام کاربری", "Username"), value: model.username ?? "—")
                    Button(L("خروج از حساب", "Sign Out"), role: .destructive) { confirmSignOut = true }
                }

                Section(L("پخش", "Playback")) {
                    Picker(L("پخش‌کننده پیش‌فرض", "Default player"), selection: $settings.playerChoice) {
                        ForEach(PlayerChoice.allCases) { Text($0.label).tag($0) }
                    }
                    if settings.playerChoice == .custom || !settings.customSchemeTemplate.isEmpty {
                        TextField(L("URL scheme برنامه دلخواه، مثل myplayer://play?url={url}", "Custom app URL, e.g. myplayer://play?url={url}"),
                                  text: $settings.customSchemeTemplate)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                    }
                    Picker(L("بافر پخش‌کننده داخلی", "Built-in player buffer"), selection: $settings.bufferMinutes) {
                        ForEach(AppSettings.bufferOptions, id: \.self) { m in
                            Text(L("\(N(m)) دقیقه جلوتر", "\(m) minutes ahead")).tag(m)
                        }
                    }
                    Picker(L("بیشترین کیفیت شروع", "Start quality limit"), selection: $settings.maxHeight) {
                        Text(L("خودکار", "Automatic")).tag(0)
                        Text("1080p").tag(1080)
                        Text("720p").tag(720)
                        Text("480p").tag(480)
                    }
                    Toggle(L("پخش خودکار قسمت بعد", "Autoplay next episode"), isOn: $settings.autoplayNext)
                }

                Section(L("زیرنویس", "Subtitles")) {
                    Picker(L("زیرنویس پیش‌فرض", "Default subtitle"), selection: $settings.subtitlePreference) {
                        ForEach(SubtitlePreference.allCases) { Text($0.label).tag($0) }
                    }
                    Picker(L("اندازه", "Size"), selection: $settings.subtitleSize) {
                        ForEach(AppSettings.sizeOptions, id: \.self) { Text(L("\(N($0))٪", "\($0)%")).tag($0) }
                    }
                    Picker(L("رنگ", "Colour"), selection: $settings.subtitleColor) {
                        ForEach(SubtitleColor.allCases) { Text($0.label).tag($0) }
                    }
                    Picker(L("پس‌زمینه", "Background"), selection: $settings.subtitleBackground) {
                        ForEach(AppSettings.backgroundOptions, id: \.self) { Text(L("\(N($0))٪", "\($0)%")).tag($0) }
                    }
                }

                Section {
                    NavigationLink(L("منابع زیرنویس آنلاین", "Online subtitle sources")) { SubtitleSourcesView() }
                } footer: {
                    Text(L("وقتی سایت زیرنویس مناسب ندارد، از SubDL، SubSource و OpenSubtitles جستجو می‌شود.",
                           "Used when the site has no suitable subtitle: SubDL, SubSource and OpenSubtitles."))
                }

                Section(L("برنامه", "App")) {
                    Picker(L("زبان", "Language"), selection: $settings.language) {
                        ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                    }
                    Button(cleared ? L("پاک شد", "Cleared") : L("پاک کردن حافظه موقت", "Clear cache")) {
                        ImageLoader.shared.clear()
                        URLCache.shared.removeAllCachedResponses()
                        cleared = true
                    }
                    Button(L("پاک کردن سابقه تماشا در این دستگاه", "Clear watch history on this device")) { watch.clear() }
                    LabeledContent(L("نسخه", "Version"),
                                   value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                }
            }
            SubtitlePreview().frame(width: 640)
        }
        .padding(.horizontal, 60)
        .confirmationDialog(L("از حساب خارج می‌شوید؟", "Sign out?"), isPresented: $confirmSignOut) {
            Button(L("خروج", "Sign Out"), role: .destructive) { Task { await model.signOut() } }
            Button(L("انصراف", "Cancel"), role: .cancel) {}
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
        Form {
            Section {
                SecureField(L("کلید API", "API key"), text: $settings.subdlKey)
            } header: { Text("SubDL") } footer: { Text(L("کلید رایگان از ", "Free key at ") + SubtitleSource.subdl.signupURL) }

            Section {
                SecureField(L("کلید API", "API key"), text: $settings.subsourceKey)
            } header: { Text("SubSource") } footer: { Text(L("کلید از ", "Key from ") + SubtitleSource.subsource.signupURL) }

            Section {
                SecureField(L("کلید API", "API key"), text: $settings.openSubtitlesKey)
                TextField(L("نام کاربری", "Username"), text: $settings.openSubtitlesUser)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                SecureField(L("رمز عبور", "Password"), text: $settings.openSubtitlesPassword)
            } header: { Text("OpenSubtitles") } footer: {
                Text(L("کلید API از ", "API key from ") + SubtitleSource.opensubtitles.signupURL
                     + L("؛ برای دانلود، نام کاربری و رمز opensubtitles.com لازم است.", ". Downloads need your opensubtitles.com username and password."))
            }

            Section(L("زبان‌های جستجو", "Languages to search")) {
                Toggle(L("فارسی", "Persian"), isOn: lang("fa"))
                Toggle(L("انگلیسی", "English"), isOn: lang("en"))
                Toggle(L("عربی", "Arabic"), isOn: lang("ar"))
                Toggle(L("ترکی", "Turkish"), isOn: lang("tr"))
            }

            Section {
                Button(testing ? L("در حال آزمایش…", "Testing…") : L("آزمایش با یک فیلم", "Test with a film")) { test() }
                    .disabled(testing)
                if let testResult { Text(testResult).font(.caption) }
            }
        }
        .navigationTitle(L("منابع زیرنویس", "Subtitle sources"))
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
