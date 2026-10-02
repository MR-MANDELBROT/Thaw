//
//  ParkedLaneDeficitTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("Parked lane deficit")
struct ParkedLaneDeficitTests {
    // Field fixture: four Visible items parked at x == -1 despite 924 pt modeled capacity for 324 pt of items.
    // A 320 pt per-item cap cannot absorb that modeled headroom.
    private let visible: Set<String> = ["spark", "antishort", "cider", "slidepad", "walld", "mole"]

    @Test("Parked items withhold the whole modeled headroom plus their own width")
    func absorbsHeadroom() throws {
        let deficit = try #require(MenuBarItemManager.parkedLaneDeficit(
            previous: nil,
            parkedWidths: [32, 38, 38, 41],
            modeledHeadroom: 600,
            concealedWidth: 0,
            visibleUIDs: visible,
            overflowUIDs: []
        ))
        let expected: CGFloat = 600 + 149 + 4 * 8
        #expect(deficit.width == expected)
    }

    @Test("Once the parked items are concealed the deficit carries, so they stay out")
    func carriesAfterConcealing() throws {
        let previous = (width: CGFloat(781), visibleUIDs: visible)
        let held = try #require(MenuBarItemManager.parkedLaneDeficit(
            previous: previous,
            parkedWidths: [],
            modeledHeadroom: 900,
            concealedWidth: 149,
            visibleUIDs: ["walld", "mole"],
            overflowUIDs: ["spark", "antishort", "cider", "slidepad"]
        ))
        #expect(held.width == 781)
    }

    @Test("A collapsed width is charged as a nominal item")
    func collapsedWidthIsNominal() throws {
        let deficit = try #require(MenuBarItemManager.parkedLaneDeficit(
            previous: nil,
            parkedWidths: [2],
            modeledHeadroom: 0,
            concealedWidth: 0,
            visibleUIDs: ["a"],
            overflowUIDs: []
        ))
        #expect(deficit.width == MenuBarItemManager.nominalStatusItemWidth + 8)
    }

    @Test("An item arriving or leaving drops the deficit")
    func dropsOnMembershipChange() {
        let previous = (width: CGFloat(80), visibleUIDs: Set(["a", "b", "c"]))
        #expect(MenuBarItemManager.parkedLaneDeficit(
            previous: previous,
            parkedWidths: [],
            modeledHeadroom: 500,
            concealedWidth: 0,
            visibleUIDs: ["a", "b"],
            overflowUIDs: []
        ) == nil)
    }

    // After launch nothing is concealed yet: the model already wants 120 pt
    // concealed, and the parked items are that same missing room.
    @Test("A modeled shortfall nothing conceals yet offsets the parked width")
    func uncoveredShortfallIsNotWithheldTwice() throws {
        let deficit = try #require(MenuBarItemManager.parkedLaneDeficit(
            previous: nil,
            parkedWidths: [32, 38, 38, 41],
            modeledHeadroom: -120,
            concealedWidth: 0,
            visibleUIDs: visible,
            overflowUIDs: []
        ))
        let expected: CGFloat = 149 + 4 * 8 - 120
        #expect(deficit.width == expected)
    }

    @Test("A shortfall the concealed items cover leaves the parked width whole")
    func coveredShortfallKeepsParkedWidth() throws {
        let deficit = try #require(MenuBarItemManager.parkedLaneDeficit(
            previous: nil,
            parkedWidths: [32, 38],
            modeledHeadroom: -60,
            concealedWidth: 79,
            visibleUIDs: visible,
            overflowUIDs: ["cider", "slidepad"]
        ))
        let expected: CGFloat = 70 + 2 * 8
        #expect(deficit.width == expected)
    }

    @Test("Parked items inside the modeled shortfall withhold nothing more")
    func parkedWithinShortfallWithholdsNothing() {
        #expect(MenuBarItemManager.parkedLaneDeficit(
            previous: nil,
            parkedWidths: [32],
            modeledHeadroom: -200,
            concealedWidth: 0,
            visibleUIDs: ["a"],
            overflowUIDs: []
        ) == nil)
    }
}
