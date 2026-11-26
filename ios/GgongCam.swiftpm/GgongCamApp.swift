import SwiftUI

@main
struct GgongCamApp: App {
    @StateObject private var app = AppModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            ContentView(app: app)
                .preferredColorScheme(.dark)
                .onChange(of: phase) { _, p in
                    if p == .active { app.becameActive() } else if p == .background { app.wentBackground() }
                }
        }
    }
}
