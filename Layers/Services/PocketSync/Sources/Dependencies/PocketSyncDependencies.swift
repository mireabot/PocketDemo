import Dependencies
import Foundation
import PocketNetworking

extension PocketDB: DependencyKey {
    public static var liveValue: Self { preconditionFailure("Register PocketDB in AppDelegate") }
}

extension Supervisor: DependencyKey {
    public static var liveValue: Supervisor { preconditionFailure("Register the Supervisor in AppDelegate") }
}

public extension DependencyValues {
    var pocketDB: PocketDB {
        get { self[PocketDB.self] }
        set { self[PocketDB.self] = newValue }
    }

    var supervisor: Supervisor {
        get { self[Supervisor.self] }
        set { self[Supervisor.self] = newValue }
    }
}
