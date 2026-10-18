import Foundation

public struct SyncStatus: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case idle(lastSyncedAt: Date?)
        case syncing
        case waitingForNetwork
        case retrying(message: String)
    }

    public let phase: Phase
    public let isAirplaneModeOn: Bool
    public let pendingCount: Int
    public let conflictCount: Int
    public let failedCount: Int

    public init(
        phase: Phase,
        isAirplaneModeOn: Bool,
        pendingCount: Int,
        conflictCount: Int,
        failedCount: Int
    ) {
        self.phase = phase
        self.isAirplaneModeOn = isAirplaneModeOn
        self.pendingCount = pendingCount
        self.conflictCount = conflictCount
        self.failedCount = failedCount
    }
}

public enum SyncTrigger: Sendable {
    case foreground
    case userRefresh
}
