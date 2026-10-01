//
//  MenuBarAppearanceItemsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
struct MenuBarAppearanceItemsTests {
    @Test("A partial on-screen snapshot cannot limit a reveal's owner read", arguments: [false, true])
    func revealReadsOwnersMissingFromOnScreenSnapshot(snapshotAfterReveal: Bool) async throws {
        let visible = [item(1, x: 300), item(2, x: 400)]
        let concealed = [item(3, x: -1, onScreen: false), item(4, x: -1, onScreen: false)]
        let physical = visible + [item(3, x: 100), item(4, x: 200)]
        let onScreen = OnScreenItemSnapshot()
        if !snapshotAfterReveal { onScreen.update(visible) }
        let revealAt = ContinuousClock.now
        if snapshotAfterReveal { onScreen.update(visible) }
        var requestedOwners = Set<pid_t>()
        let result = try #require(await MenuBarAppearanceItems.read(
            knownItems: visible + concealed,
            onScreenSnapshot: onScreen,
            notBefore: revealAt,
            readOwners: { owners in
                requestedOwners = owners
                return physical.filter { owners.contains($0.sourcePID ?? $0.ownerPID) }
            },
            discover: { Issue.record("A reveal must not wait for discovery"); return [] }
        ))

        #expect(requestedOwners == [1, 2, 3, 4])
        let bounds = MenuBarSplitPillGeometry.trailingPillBounds(
            from: result.items,
            context: .init(revealedSection: .hidden, section: { ($0.sourcePID ?? 0) > 2 ? .hidden : .visible })
        )
        #expect(bounds.map(\.minX).min() == 100, "The first read must cover the newly revealed items")
    }

    @Test("An empty on-screen snapshot still reads known concealed owners")
    func knownInventoryDoesNotFallBackToDiscovery() async throws {
        let known = item(3, x: -1, onScreen: false)
        var requestedOwners = Set<pid_t>()
        let result = try #require(await MenuBarAppearanceItems.read(
            knownItems: [known], onScreenSnapshot: nil, notBefore: nil,
            readOwners: { owners in requestedOwners = owners; return [item(3, x: 100)] },
            discover: { Issue.record("Known owners do not require discovery"); return [] }
        ))
        #expect(requestedOwners == [3])
        #expect(result.items.count == 1)
    }

    @Test("A recent complete snapshot avoids another AX read")
    func completeSnapshotIsReused() async throws {
        let items = [item(1, x: 300), item(2, x: 400)]
        let revealAt = ContinuousClock.now
        let onScreen = OnScreenItemSnapshot()
        onScreen.update(items)
        let result = try #require(await MenuBarAppearanceItems.read(
            knownItems: items, onScreenSnapshot: onScreen, notBefore: revealAt,
            readOwners: { _ in Issue.record("The complete snapshot is already fresh"); return nil },
            discover: { Issue.record("Unexpected discovery"); return [] }
        ))
        #expect(result.items == items)
        #expect(result.readAt == onScreen.timestamp)
    }

    @Test("An incomplete requested-owner read preserves the previous geometry")
    func incompleteReadDoesNotPublishPartialGeometry() async {
        let known = item(3, x: -1, onScreen: false)
        let result = await MenuBarAppearanceItems.read(
            knownItems: [known], onScreenSnapshot: nil, notBefore: nil,
            readOwners: { _ in nil },
            discover: { Issue.record("Do not turn a failed read into discovery"); return [] }
        )
        #expect(result == nil)
    }

    private func item(_ sourcePID: pid_t, x: CGFloat, onScreen: Bool = true) -> MenuBarItem {
        MenuBarItem(
            tag: .init(namespace: .string("com.example.owner\(sourcePID)"), title: "Status", instanceIndex: 0),
            windowID: UInt32(sourcePID), ownerPID: 99, sourcePID: sourcePID,
            bounds: CGRect(x: x, y: 3, width: 24, height: 24), title: "Status", isOnScreen: onScreen
        )
    }
}
