//
//  MenuBarItemManager+OrderRecording.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

extension MenuBarItemManager {
    /// Use observed order, not stale pane order; AX-missing members retain proposed slots.
    /// A vanished mover cannot commit; the controller still filters and preserves overflow.
    static nonisolated func sectionOrderAfterCompletedMove(
        of item: MenuBarItem,
        proposedOrder: [MenuBarItem],
        liveItems: [MenuBarItem]
    ) -> [MenuBarItem]? {
        let proposedIDs = Set(proposedOrder.map(\.uniqueIdentifier))
        var observedIDs = Set<String>()
        let observed = MenuBarItem.sortByLeadingEdge(liveItems).filter {
            proposedIDs.contains($0.uniqueIdentifier) &&
                $0.isOnScreen && !$0.bounds.isEmpty && !$0.isSystemClone &&
                observedIDs.insert($0.uniqueIdentifier).inserted
        }
        guard observedIDs.contains(item.uniqueIdentifier) else { return nil }
        var iterator = observed.makeIterator()
        return proposedOrder.map { member in
            guard observedIDs.contains(member.uniqueIdentifier) else { return member }
            return iterator.next() ?? member
        }
    }

    /// User drops already verified their position; only structural edits and repairs need another rewrite.
    static nonisolated func shouldNormalizeStructureAfterMove(
        item: MenuBarItem,
        destination: MoveDestination,
        isUserInitiated: Bool
    ) -> Bool {
        !isUserInitiated || item.isControlItem || destination.targetItem.isControlItem
    }
}
