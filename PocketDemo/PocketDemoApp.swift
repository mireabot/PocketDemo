import PocketRecordings
import SwiftUI

@main
struct PocketDemoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            switch appDelegate.startup.state {
            case .starting: ProgressView()
            case .ready: RecordingsRootView()
            case .failed:
                ContentUnavailableView("Couldn't open recordings", systemImage: "externaldrive.badge.exclamationmark",
                                       description: Text("The recordings database on this device could not be opened."))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await appDelegate.sync() } }
        }
    }
}
