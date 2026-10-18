import Dependencies
import Domain
import Observation
import OSLog
import PocketNetworking
import PocketSync
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    let startup = AppStartup()
    private var supervisor: Supervisor?

    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Task { await start() }
        return true
    }

    func sync() async { await supervisor?.sync(.foreground) }

    /// SQLite opens, migrates and reads off the main actor. The main actor only registers the
    /// services and publishes readiness, and no feature resolves a dependency before that.
    private func start() async {
        do {
            let database = try await PocketDB.live()
            #if DEBUG
                Logger(subsystem: "PocketDemo", category: "Database")
                    .debug("SQLite database: \(database.reader.path, privacy: .public)")
            #endif
            let deviceID = try await database.reader.read { try SyncStateRecord.load(in: $0).deviceID }
            let client = RestClient(.init(baseURL: URL(string: "http://127.0.0.1:8787")!, adapters: [StaticHeaders(["X-Device-Id": deviceID])]))
            let supervisor = Supervisor(database: database, client: client)
            prepareDependencies {
                $0.pocketDB = database
                $0.supervisor = supervisor
            }
            self.supervisor = supervisor
            startup.state = .ready
            await supervisor.start()
        } catch {
            Logger(subsystem: "PocketDemo", category: "Database").error("Could not open the recordings database: \(String(describing: error), privacy: .public)")
            startup.state = .failed
        }
    }
}

@Observable
final class AppStartup {
    enum State { case starting, ready, failed }
    var state = State.starting
}
