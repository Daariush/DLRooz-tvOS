import SwiftUI

/// App-wide dependencies and sign-in state.
@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable { case signedOut, signedIn }

    let jar: CookieJar
    let http: SiteHTTP
    let auth: AuthService
    let site: SiteRepository
    let onlineSubtitles = OnlineSubtitles()

    @Published var phase: Phase
    @Published var username: String?
    /// Last home page, shown instantly while a fresh one loads.
    @Published var cachedHome: HomePage?

    init() {
        jar = CookieJar()
        http = SiteHTTP(jar: jar)
        auth = AuthService(http: http)
        site = SiteRepository(http: http, auth: auth)
        ImageLoader.shared.jar = jar
        phase = auth.isLoggedIn ? .signedIn : .signedOut
        username = auth.storedUsername
        if let data = UserDefaults.standard.data(forKey: "home.cache") {
            cachedHome = try? JSONDecoder().decode(HomePage.self, from: data)
        }
        site.onSessionLost = { [weak self] in
            Task { @MainActor in self?.phase = .signedOut }
        }
    }

    func didSignIn() {
        username = auth.storedUsername
        phase = .signedIn
    }

    func signOut() async {
        await auth.logout()
        cachedHome = nil
        UserDefaults.standard.removeObject(forKey: "home.cache")
        username = nil
        phase = .signedOut
    }

    func rememberHome(_ page: HomePage) {
        cachedHome = page
        if let data = try? JSONEncoder().encode(page) { UserDefaults.standard.set(data, forKey: "home.cache") }
    }
}
