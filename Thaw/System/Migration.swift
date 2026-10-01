//
//  Migration.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import MenuBarModel

/// Brings settings written by older builds up to the current shape. Each step
/// has its own "already migrated" flag, so it runs once per installation.
/// There are no Ice migrations: the app only reads its own defaults domain.
@MainActor
struct MigrationManager {
    private let diagLog = DiagLog(category: "Migration")

    let encoder = JSONEncoder()
}

// MARK: - Entry Point

extension MigrationManager {
    /// Runs every outstanding migration and logs whatever each one reported.
    func migrateAll() {
        let results = [
            migratePerDisplayThawBar(),
        ]
        for case let .failureAndLogError(error) in results {
            diagLog.error("Migration failed with error \(error)")
        }
    }
}

// MARK: - Migrate Per-Display Thaw Bar

extension MigrationManager {
    /// Migrates legacy global Thaw Bar settings to per-display configurations.
    private func migratePerDisplayThawBar() -> MigrationResult {
        guard !Defaults.bool(forKey: .hasMigratedPerDisplayThawBar) else {
            return .success
        }

        let useThawBar = Defaults.bool(forKey: .useThawBar)
        let useOnlyOnNotched = Defaults.bool(forKey: .useThawBarOnlyOnNotchedDisplay)
        let thawBarLocationRaw = Defaults.integer(forKey: .thawBarLocation)
        let thawBarLocation = ThawBarLocation(rawValue: thawBarLocationRaw) ?? .dynamic

        // Only create per-display configs if the user had Thaw Bar enabled.
        guard useThawBar else {
            Defaults.set(true, forKey: .hasMigratedPerDisplayThawBar)
            diagLog.info("Per-display Thaw Bar migration: Thaw Bar was disabled, nothing to migrate")
            return .success
        }

        let configs = DisplayThawBarConfiguration.buildConfigurations(
            onlyOnNotched: useOnlyOnNotched,
            location: thawBarLocation
        )

        do {
            let data = try encoder.encode(configs)
            Defaults.set(data, forKey: .displayThawBarConfigurations)
            Defaults.set(true, forKey: .hasMigratedPerDisplayThawBar)
            diagLog.info("Per-display Thaw Bar migration: migrated \(configs.count) display(s)")
        } catch {
            return .failureAndLogError(.perDisplayThawBarMigrationError(error))
        }

        return .success
    }
}

// MARK: - Step Outcomes

extension MigrationManager {
    /// What a migration step has to say for itself once it is finished.
    enum MigrationResult {
        /// The step finished with nothing to report.
        case success

        /// The step could not finish, and should be attempted again later.
        case failureAndLogError(MigrationError)
    }
}

// MARK: - Step Failures

extension MigrationManager {
    enum MigrationError: Error, CustomStringConvertible {
        case perDisplayThawBarMigrationError(any Error)

        var description: String {
            switch self {
            case let .perDisplayThawBarMigrationError(error):
                "Error migrating per-display Thaw Bar configuration: \(error)"
            }
        }
    }
}
