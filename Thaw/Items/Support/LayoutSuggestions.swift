//
//  LayoutSuggestions.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import PlatformRuntimeKit

/// Pure idle-item and notch suggestions allow testing thresholds without a live menu bar.
nonisolated enum LayoutSuggestions {
    /// How long an item must go unclicked before it is suggested for Hidden.
    static let idleInterval: TimeInterval = 30 * 24 * 60 * 60

    /// The key an item's usage record is stored under.
    static func usageKey(for item: MenuBarItem) -> String {
        MenuBarItemTag.canonicalPersistentIdentifier(item.tag.tagIdentifier)
    }

    /// Suggest only after a full idleInterval of observation; shorter records cannot prove inactivity.
    /// Shortcuts and Thaw Bar clicks may be unseen, so this is a review suggestion, not a verdict.
    static func unusedItems(
        _ visibleItems: [MenuBarItem],
        records: [String: HygieneItemRecord],
        now: Date
    ) -> [MenuBarItem] {
        visibleItems.filter { item in
            guard !item.isControlItem,
                  let record = records[usageKey(for: item)],
                  now.timeIntervalSince(record.firstSeen) >= idleInterval
            else { return false }
            let lastUse = record.lastActivated ?? record.firstSeen
            return now.timeIntervalSince(lastUse) >= idleInterval
        }
    }

    /// Visible items a notch covers, per MenuBarNotchGeometry.
    static func itemsBehindNotch(_ visibleItems: [MenuBarItem], notchRects: [CGRect]) -> [MenuBarItem] {
        visibleItems.filter { item in
            !item.isControlItem && item.isOnScreen && MenuBarNotchGeometry.isOccluded(item, by: notchRects)
        }
    }

    /// A short, locale-formatted list of names, with "and N more" past three.
    @MainActor
    static func names(of items: [MenuBarItem]) -> String {
        let names = items.map { MenuBarItemDisplayName.displayName(for: $0) }
        guard names.count > 3 else {
            return names.formatted(.list(type: .and))
        }
        // The count is the list's last entry, so the locale joins it like
        // any other name: "A, B, C and 2 more".
        let more = String(localized: "\(names.count - 3) more", comment: "Last entry of a shortened list of menu bar item names")
        return (Array(names.prefix(3)) + [more]).formatted(.list(type: .and))
    }
}

/// When the user last dismissed a suggestion, so "Not Now" holds for a
/// while instead of returning on the next visit.
@MainActor
enum LayoutSuggestionDismissal {
    enum Kind: String {
        case unusedItems
        case itemsBehindNotch
    }

    /// How long a dismissal holds.
    static let quietInterval: TimeInterval = 30 * 24 * 60 * 60

    private static func key(_ kind: Kind) -> String {
        "LayoutSuggestions.dismissed.\(kind.rawValue)"
    }

    static func isQuiet(_ kind: Kind, now: Date = .now) -> Bool {
        guard let date = UserDefaults.standard.object(forKey: key(kind)) as? Date else { return false }
        return now.timeIntervalSince(date) < quietInterval
    }

    static func dismiss(_ kind: Kind) {
        UserDefaults.standard.set(Date.now, forKey: key(kind))
    }
}
