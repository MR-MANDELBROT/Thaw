//
//  NoRoomParkTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// MenuBarItemGeometry.isNoRoomPark(_:): macOS parks a Visible item it has no
/// room for at the leading edge of an off-bar row, a wide one at x == -1 and
/// a square icon at x == 7 or 8. Field frames from a 14-inch notched bar.
@Suite("No-room park")
struct NoRoomParkTests {
    @Test("The sentinel is a no-room park in any band")
    func sentinelIsNoRoom() {
        #expect(MenuBarItemGeometry.isNoRoomPark(CGRect(x: -1, y: 970, width: 38, height: 24)))
        #expect(MenuBarItemGeometry.isNoRoomPark(CGRect(x: -1, y: 4, width: 31, height: 24)))
    }

    @Test("A square icon inset from the sentinel below the bar is a no-room park")
    func squareIconIsNoRoom() {
        #expect(MenuBarItemGeometry.isNoRoomPark(CGRect(x: 7, y: 970, width: 24, height: 24)))
        #expect(MenuBarItemGeometry.isNoRoomPark(CGRect(x: 7, y: 970, width: 20, height: 24)))
        #expect(MenuBarItemGeometry.isNoRoomPark(CGRect(x: 8, y: 971, width: 22, height: 22)))
    }

    @Test("Reflow collateral keeps its hidden-side X and stays repairable")
    func collateralIsNotNoRoom() {
        #expect(!MenuBarItemGeometry.isNoRoomPark(CGRect(x: 1200, y: 1400, width: 24, height: 22)))
        #expect(!MenuBarItemGeometry.isNoRoomPark(CGRect(x: 830, y: 1400, width: 24, height: 24)))
    }

    @Test("A seat on the bar is not a park")
    func barSeatIsNotNoRoom() {
        #expect(!MenuBarItemGeometry.isNoRoomPark(CGRect(x: 1071, y: 4.5, width: 36.5, height: 24)))
        #expect(!MenuBarItemGeometry.isNoRoomPark(CGRect(x: 7, y: 4, width: 24, height: 24)))
    }
}
