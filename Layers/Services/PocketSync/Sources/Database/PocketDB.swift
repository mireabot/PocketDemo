import Domain
import Foundation
@_exported import GRDB

public struct PocketDB: Sendable {
    public let reader: any DatabaseReader
    public let writer: any DatabaseWriter

    public init(_ writer: any DatabaseWriter) throws {
        reader = writer
        self.writer = writer
        var migrator = DatabaseMigrator()
        for table in allTables {
            migrator.registerMigration(for: table)
        }
        migrator.registerMigration("initialize_sync_state") { db in
            try SyncStateRecord().insert(db)
        }
        try migrator.migrate(writer)
    }
}

public extension PocketDB {
    static func open(_ url: URL?) throws -> PocketDB {
        if let url {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            return try PocketDB(DatabasePool(path: url.path))
        }
        return try PocketDB(DatabaseQueue())
    }

    /// Opens and migrates the app database away from the caller's actor, so launch never blocks the main thread.
    @concurrent static func live() async throws -> PocketDB {
        let directory = URL.applicationSupportDirectory.appending(path: "PocketDemo", directoryHint: .isDirectory)
        return try open(directory.appending(path: "pocket.sqlite"))
    }
}
