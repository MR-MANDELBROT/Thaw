//
//  MenuBarAllowListTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// MenuBarAllowList.disallowedBundleIdentifiers(in:): Control Center's tracked
/// applications, keyed by bundle identifier with an isAllowed flag per app.
@Suite("Menu bar allow list")
struct MenuBarAllowListTests {
    private static let json = """
    {"com.microsoft.OneDrive":{"isAllowed":false,"rawBundleId":"com.microsoft.OneDrive","lastKnownLocalizedName":"OneDrive"},\
    "notion.id":{"isAllowed":false,"rawBundleId":"notion.id","lastKnownLocalizedName":"Notion"},\
    "com.apphousekitchen.aldente-pro":{"isAllowed":true,"rawBundleId":"com.apphousekitchen.aldente-pro","lastKnownLocalizedName":"AlDente"}}
    """

    @Test("JSON data lists only the apps switched off")
    func jsonData() throws {
        let plist: [String: Any] = ["TrackedApplications": Data(Self.json.utf8)]
        let disallowed = try #require(MenuBarAllowList.disallowedBundleIdentifiers(in: plist))
        #expect(disallowed == ["com.microsoft.OneDrive", "notion.id"])
    }

    @Test("A JSON string and a lower-case key read the same")
    func jsonStringLowerCaseKey() throws {
        let plist: [String: Any] = ["trackedApplications": Self.json]
        let disallowed = try #require(MenuBarAllowList.disallowedBundleIdentifiers(in: plist))
        #expect(disallowed == ["com.microsoft.OneDrive", "notion.id"])
    }

    @Test("A dictionary value and the raw bundle identifier are honoured")
    func dictionaryValueWithRawBundleID() throws {
        let plist: [String: Any] = [
            "TrackedApplications": [
                "Displaperture": ["isAllowed": false, "rawBundleId": "com.manytricks.Displaperture"],
                "com.hegenberg.BetterTouchTool": ["isAllowed": true],
            ],
        ]
        let disallowed = try #require(MenuBarAllowList.disallowedBundleIdentifiers(in: plist))
        #expect(disallowed == ["Displaperture", "com.manytricks.Displaperture"])
    }

    @Test("An array of entries is read by raw bundle identifier")
    func arrayOfEntries() throws {
        let plist: [String: Any] = [
            "TrackedApplications": [
                ["isAllowed": false, "rawBundleId": "com.anthropic.claudefordesktop"],
                ["isAllowed": true, "rawBundleId": "org.hammerspoon.Hammerspoon"],
            ],
        ]
        let disallowed = try #require(MenuBarAllowList.disallowedBundleIdentifiers(in: plist))
        #expect(disallowed == ["com.anthropic.claudefordesktop"])
    }

    @Test("Entries without an isAllowed flag mean nothing is readable")
    func missingFlagReadsNothing() {
        let plist: [String: Any] = ["TrackedApplications": #"{"com.example.app":{"rawBundleId":"com.example.app"}}"#]
        #expect(MenuBarAllowList.disallowedBundleIdentifiers(in: plist) == nil)
    }

    @Test("Entries nested under another key are found")
    func nestedEntries() throws {
        let plist: [String: Any] = [
            "MenuBarApps": ["apps": [["isAllowed": false, "bundleIdentifier": "io.fadel.MissionControlPlus"]]],
            "ShowWeather": true,
        ]
        let disallowed = try #require(MenuBarAllowList.disallowedBundleIdentifiers(in: plist))
        #expect(disallowed == ["io.fadel.MissionControlPlus"])
    }

    @Test("Property list data is decoded like JSON")
    func propertyListData() throws {
        let entries: [String: Any] = ["org.hammerspoon.Hammerspoon": ["isAllowed": false]]
        let data = try PropertyListSerialization.data(fromPropertyList: entries, format: .binary, options: 0)
        let disallowed = try #require(MenuBarAllowList.disallowedBundleIdentifiers(in: ["TrackedApplications": data]))
        #expect(disallowed == ["org.hammerspoon.Hammerspoon"])
    }

    @Test("A list without tracked applications or with garbage filters nothing")
    func unreadableList() {
        #expect(MenuBarAllowList.disallowedBundleIdentifiers(in: ["ShowWeather": true]) == nil)
        #expect(MenuBarAllowList.disallowedBundleIdentifiers(in: ["TrackedApplications": "not json"]) == nil)
    }
}
