//
//  MenuBarArrangementMode.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// macOS 27 prefers granted TrailingItemPreferredPositions writes over synthetic drags, which hold physical mouse input.
/// Manual mode preserves user Command-drag order without moves or table writes, while still hiding and revealing.
nonisolated enum MenuBarArrangementMode: Int, CaseIterable, Identifiable {
    /// Layout drops, profiles, and saved order move real items.
    case automatic = 0
    /// Thaw never moves an item. You arrange the bar yourself with ⌘-drag;
    /// Thaw records what it observes and confines itself to hiding.
    case manual = 1

    var id: Int {
        rawValue
    }

    var localized: LocalizedStringKey {
        switch self {
        case .automatic: "Automatic"
        case .manual: "Manual"
        }
    }

    var explanation: LocalizedStringKey {
        switch self {
        case .automatic:
            "Thaw keeps items in the order you set in Layout. To move another app’s item it sometimes has to drag it for you, and your mouse is briefly unavailable while it does."
        case .manual:
            "You set the order yourself by ⌘-dragging items in the menu bar. Thaw still hides and shows items, but never moves them or changes the order macOS has saved."
        }
    }

    /// Whether Thaw may move items and write preferred positions in this mode.
    var permitsOrderEnforcement: Bool {
        self == .automatic
    }
}
