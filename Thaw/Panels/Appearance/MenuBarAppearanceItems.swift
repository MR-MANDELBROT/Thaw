//
//  MenuBarAppearanceItems.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

@MainActor
enum MenuBarAppearanceItems {
    struct Snapshot {
        let items: [MenuBarItem]
        let readAt: ContinuousClock.Instant
    }

    static func read(
        knownItems: [MenuBarItem],
        onScreenSnapshot: OnScreenItemSnapshot?,
        notBefore minimumReadTime: ContinuousClock.Instant?,
        readOwners: (Set<pid_t>) async -> [MenuBarItem]?,
        discover: () async -> [MenuBarItem]
    ) async -> Snapshot? {
        let readAt = ContinuousClock.now
        let recentItems = onScreenSnapshot?.items ?? []
        let recentOwners = Set(recentItems.map { $0.sourcePID ?? $0.ownerPID })
        let owners = recentOwners.union(knownItems.map { $0.sourcePID ?? $0.ownerPID })
        // Recent truncated or concealed snapshots can omit owners whose icons are about to appear.
        if owners.isSubset(of: recentOwners),
           let recentAt = onScreenSnapshot?.timestamp,
           recentAt.duration(to: readAt) < .milliseconds(200),
           minimumReadTime.map({ recentAt >= $0 }) ?? true
        {
            return Snapshot(items: recentItems, readAt: recentAt)
        }
        if !owners.isEmpty {
            guard let fresh = await readOwners(owners) else { return nil }
            return Snapshot(items: fresh, readAt: readAt)
        }
        return await Snapshot(items: discover(), readAt: readAt)
    }
}
