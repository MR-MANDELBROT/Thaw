//
//  RunningApplicationSnapshot.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

nonisolated struct RunningApplicationSnapshot: Sendable, Equatable {
    let processIDs: Set<pid_t>
    let bundleIdentifiers: Set<String>

    @concurrent
    static func current(
        collect: @Sendable () -> Self = readSystem
    ) async -> Self {
        collect()
    }

    private static func readSystem() -> Self {
        let applications = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        return Self(
            processIDs: Set(applications.map(\.processIdentifier)),
            bundleIdentifiers: Set(applications.compactMap(\.bundleIdentifier))
        )
    }
}
