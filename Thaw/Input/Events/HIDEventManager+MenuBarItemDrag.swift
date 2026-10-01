//
//  HIDEventManager+MenuBarItemDrag.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import AppKit
import Foundation

extension HIDEventManager {
    // MARK: Handle Menu Bar Item Drag Stop

    /// Ends an item drag, and arranges for the cache to catch up with wherever
    /// the user dropped things.
    func handleMenuBarItemDragStop() {
        guard isDraggingMenuBarItem else {
            return
        }
        isDraggingMenuBarItem = false

        guard let appState else {
            return
        }
        // Suppresses caching for 1 s and order restoration for 2 s, then
        // recaches to pick up the new positions.
        appState.itemManager.recordExternalMoveOperation()
        Task { [weak appState] in
            try? await Task.sleep(for: .milliseconds(500))
            await appState?.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
        }
    }

    // MARK: Handle Menu Bar Item Drag Start

    /// Notices the start of an item drag.
    ///
    /// Holding command is what makes a drag in the menu bar a move of the item
    /// rather than a drag inside whichever app owns it.
    func handleMenuBarItemDragStart(
        with event: NSEvent,
        appState: AppState,
        screen: NSScreen
    ) {
        guard
            !isDraggingMenuBarItem,
            event.modifierFlags.contains(.command),
            isMouseInsideMenuBarItem(appState: appState, screen: screen)
        else {
            return
        }

        isDraggingMenuBarItem = true

        // Optionally bring every section out for the duration of the drag, so
        // the user can drop an item into one that is currently put away.
        guard configuration.showAllSectionsOnUserDrag else {
            return
        }
        for section in appState.menuBarManager.sections {
            section.controlItem.state = .showSection
        }
    }
}
