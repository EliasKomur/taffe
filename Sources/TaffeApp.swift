import SwiftUI

@main
struct TaffeApp: App {
    @StateObject private var detector: SoundDetector
    @AppStorage(SharedKeys.theme, store: TaffeShared.defaults) private var themeID = "neon"

    init() {
        PuffStore.migrateIfNeeded()
        _detector = StateObject(wrappedValue: SoundDetector())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(detector)
                .environment(\.theme, TaffeTheme.named(themeID))
                .preferredColorScheme(.dark)
        }
    }
}
