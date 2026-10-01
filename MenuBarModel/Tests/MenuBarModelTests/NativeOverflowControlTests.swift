//
//  NativeOverflowControlTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing

/// Accessibility exposes the native overflow chevron as a MenuBarAgent extra.
/// Treat it as chrome: excluded from sections and never physically orderable.
@Suite("Native overflow control")
struct NativeOverflowControlTests {
    private func agentItem(_ title: String) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .menuBarAgent, title: title),
            windowID: 0x8000_0001,
            ownerPID: 500,
            sourcePID: 500,
            bounds: CGRect(x: 900, y: 0, width: 24, height: 22),
            title: title,
            isOnScreen: true
        )
    }

    @Test("Recognizes every title form the control has been seen with", arguments: [
        "AXOverflowButton",
        "axoverflowbutton",
        "Double backward chevron",
        "<",
        "<<",
        "‹ ›",
        "»",
        "Show Hidden Menu Bar Items",
        " Show Hidden Menu Bar Items ",
    ])
    func recognizesTheControlUnderMenuBarAgent(title: String) {
        let tag = MenuBarItemTag(namespace: .menuBarAgent, title: title)
        #expect(tag.isNativeOverflowControl)
        #expect(MenuBarItemTag.isNativeOverflowControlTitle(title))
    }

    @Test("Real MenuBarAgent extras are not the control", arguments: [
        "com.apple.menuextra.clock",
        "com.apple.menuextra.controlcenter",
        "com.apple.menuextra.sound",
        "Item-0",
        "Wi-Fi",
        "<<<<<",
        "",
        "   ",
    ])
    func leavesRealExtrasAlone(title: String) {
        let tag = MenuBarItemTag(namespace: .menuBarAgent, title: title)
        #expect(!tag.isNativeOverflowControl)
    }

    @Test("Only MenuBarAgent hosts the control")
    func requiresTheMenuBarAgentNamespace() {
        let thirdParty = MenuBarItemTag(namespace: .string("com.example.app"), title: "Show Hidden Menu Bar Items")
        #expect(!thirdParty.isNativeOverflowControl)
        let glyph = MenuBarItemTag(namespace: .string("com.example.app"), title: "<")
        #expect(!glyph.isNativeOverflowControl)
        let controlCenter = MenuBarItemTag(namespace: .controlCenter, title: "AXOverflowButton")
        #expect(!controlCenter.isNativeOverflowControl)
    }

    @Test("The control is excluded from section management")
    func policyIsExcluded() {
        let item = agentItem("Show Hidden Menu Bar Items")
        #expect(item.isNativeOverflowControl)
        #expect(item.sectionManagementPolicy == .excluded)
        #expect(item.sectionManagementPolicy(experimentalSystemItemHiding: true) == .excluded)
        #expect(!item.canBeHidden)
        #expect(!item.canBeHidden(experimentalSystemItemHiding: true))
    }

    @Test("The control is never physically orderable, whatever the experimental gate says")
    func refusesPhysicalOrdering() {
        let item = agentItem("Show Hidden Menu Bar Items")
        // The tag is movable because it is not an anchor; the overflow-control check must refuse ordering.
        #expect(item.isMovable)
        #expect(item.orderabilityRefusal(experimentalSystemItemHiding: false) == .nativeOverflowControl)
        #expect(item.orderabilityRefusal(experimentalSystemItemHiding: true) == .nativeOverflowControl)
        #expect(!item.isPhysicallyOrderable(experimentalSystemItemHiding: false))
        #expect(!item.isPhysicallyOrderable(experimentalSystemItemHiding: true))
    }

    @Test("An ordinary MenuBarAgent module keeps its existing verdicts")
    func ordinaryModulesAreUnaffected() {
        let sound = agentItem("com.apple.menuextra.sound")
        #expect(!sound.isNativeOverflowControl)
        #expect(sound.sectionManagementPolicy != .excluded)
        #expect(sound.orderabilityRefusal(experimentalSystemItemHiding: false) != .nativeOverflowControl)
    }
}
