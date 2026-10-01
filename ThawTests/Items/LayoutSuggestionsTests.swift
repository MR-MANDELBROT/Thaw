//
//  LayoutSuggestionsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Testing
@testable import Thaw

@Suite("Layout suggestions")
struct LayoutSuggestionsTests {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    private func item(_ title: String, x: CGFloat = 100) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.\(title)"), title: title),
            windowID: 1,
            ownerPID: 100,
            sourcePID: 100,
            bounds: CGRect(x: x, y: 0, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    private func record(firstSeenDaysAgo: Double, lastClickedDaysAgo: Double?) -> HygieneItemRecord {
        HygieneItemRecord(
            firstSeen: now - firstSeenDaysAgo * day,
            lastSeen: now,
            lastActivated: lastClickedDaysAgo.map { now - $0 * day },
            displayNameAtFirstSight: "x"
        )
    }

    @Test("An item watched and unclicked for 30 days is suggested")
    func suggestsIdleItems() {
        let idle = item("Idle")
        let records = [LayoutSuggestions.usageKey(for: idle): record(firstSeenDaysAgo: 45, lastClickedDaysAgo: 40)]
        #expect(LayoutSuggestions.unusedItems([idle], records: records, now: now).count == 1)
    }

    @Test("A recently clicked item is not suggested")
    func skipsRecentlyClicked() {
        let used = item("Used")
        let records = [LayoutSuggestions.usageKey(for: used): record(firstSeenDaysAgo: 45, lastClickedDaysAgo: 2)]
        #expect(LayoutSuggestions.unusedItems([used], records: records, now: now).isEmpty)
    }

    @Test("An item watched for less than 30 days is never suggested, clicked or not")
    func needsAFullWindowOfRecord() {
        let new = item("New")
        let records = [LayoutSuggestions.usageKey(for: new): record(firstSeenDaysAgo: 10, lastClickedDaysAgo: nil)]
        #expect(LayoutSuggestions.unusedItems([new], records: records, now: now).isEmpty)
    }

    @Test("An item with no record is never suggested")
    func needsARecord() {
        #expect(LayoutSuggestions.unusedItems([item("Unknown")], records: [:], now: now).isEmpty)
    }

    @Test("Only items mostly under the notch are reported")
    func reportsItemsBehindTheNotch() {
        let notch = CGRect(x: 600, y: 0, width: 200, height: 37)
        let under = item("Under", x: 700)
        let beside = item("Beside", x: 900)
        let result = LayoutSuggestions.itemsBehindNotch([under, beside], notchRects: [notch])
        #expect(result.map(\.title) == ["Under"])
    }
}

@MainActor
@Suite("Thaw Bar keyboard focus")
struct ThawBarKeyboardFocusTests {
    @Test("Nothing is highlighted until the keyboard is used")
    func startsUnfocused() {
        let focus = ThawBarKeyboardFocus()
        focus.update(itemCount: 3, arrangement: .row)
        #expect(focus.index == nil)
        focus.begin()
        #expect(focus.index == 0)
    }

    @Test("A row moves left and right, stops at the ends, and ignores up and down")
    func rowMovement() {
        let focus = ThawBarKeyboardFocus()
        focus.update(itemCount: 3, arrangement: .row)
        focus.begin()
        focus.move(dx: -1, dy: 0)
        #expect(focus.index == 0)
        focus.move(dx: 1, dy: 0)
        focus.move(dx: 1, dy: 0)
        focus.move(dx: 1, dy: 0)
        #expect(focus.index == 2)
        focus.move(dx: 0, dy: -1)
        #expect(focus.index == 2)
    }

    @Test("A grid moves a whole row with up and down")
    func gridMovement() {
        let focus = ThawBarKeyboardFocus()
        focus.update(itemCount: 8, arrangement: .grid(columns: 3))
        focus.begin()
        focus.move(dx: 0, dy: 1)
        #expect(focus.index == 3)
        focus.move(dx: 1, dy: 0)
        #expect(focus.index == 4)
        focus.move(dx: 0, dy: 1)
        #expect(focus.index == 7)
    }

    @Test("Removing items keeps the highlight inside them")
    func clampsWhenItemsLeave() {
        let focus = ThawBarKeyboardFocus()
        focus.update(itemCount: 5, arrangement: .row)
        focus.begin()
        for _ in 0 ..< 4 {
            focus.move(dx: 1, dy: 0)
        }
        focus.update(itemCount: 2, arrangement: .row)
        #expect(focus.index == 1)
    }

    @Test("The pointer takes the highlight only while the keyboard is in use")
    func pointerTakesOver() {
        let focus = ThawBarKeyboardFocus()
        focus.update(itemCount: 4, arrangement: .row)
        focus.pointerEntered(2)
        #expect(focus.index == nil)
        focus.begin()
        focus.pointerEntered(2)
        #expect(focus.index == 2)
        focus.move(dx: 1, dy: 0)
        #expect(focus.index == 3)
    }

    @Test("Return only asks for a click while something is highlighted")
    func activation() {
        let focus = ThawBarKeyboardFocus()
        focus.update(itemCount: 2, arrangement: .row)
        focus.activate()
        #expect(focus.activationRequest == 0)
        focus.begin()
        focus.activate()
        #expect(focus.activationRequest == 1)
    }
}
