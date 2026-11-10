import SwiftUI

@main
struct DLRoozApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var settings = AppSettings.shared
    @StateObject private var watch = WatchStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(settings)
                .environmentObject(watch)
                .environment(\.layoutDirection, settings.layoutDirection)
                .environment(\.locale, Locale(identifier: settings.language == .fa ? "fa_IR" : "en_US"))
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                // Changing the language rebuilds every screen with the new copy.
                .id(settings.language)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            switch model.phase {
            case .signedOut: LoginView().transition(.opacity)
            case .signedIn: MainTabView().transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.phase)
    }
}
