import SwiftUI

@main
struct TaffeApp: App {
    @StateObject private var detector = SoundDetector()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(detector)
        }
    }
}
