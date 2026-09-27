import SwiftUI

@main
struct RecorderProbeApp: App {
    @StateObject private var capture = CaptureCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(capture)
        }
    }
}
