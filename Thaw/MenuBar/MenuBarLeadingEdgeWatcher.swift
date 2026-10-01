//
//  MenuBarLeadingEdgeWatcher.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Observation

/// Follows the live left edge of the first visible menu bar item, so overlays
/// like the appearance pill do not lag until the next cache walk.
///
/// Menu bar items post no AX notifications when they move, so one element's
/// position is polled off the main actor. The visible run is right-anchored,
/// so any change moves this edge; a failed read counts as a change too.
@MainActor
@Observable
final class MenuBarLeadingEdgeWatcher {
    /// The first visible item's live left edge, in CG-global points, or nil
    /// when it could not be read. Changes only when the edge moves.
    private(set) var leadingEdge: MenuBarLeadingEdgeSample?

    @ObservationIgnored private weak var appState: AppState?
    @ObservationIgnored private var anchor: LeadingEdgeAnchor?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var walkObservation: Task<Void, Never>?
    @ObservationIgnored private var anchorTask: Task<Void, Never>?
    @ObservationIgnored private let diagLog = DiagLog(category: "MenuBarLeadingEdgeWatcher")

    /// Short enough that a follower is at most half a second behind the bar,
    /// long enough that an idle bar costs two reads a second.
    static let pollInterval = Duration.milliseconds(500)

    deinit {
        pollTask?.cancel()
        walkObservation?.cancel()
        anchorTask?.cancel()
    }

    func performSetup(with appState: AppState) {
        self.appState = appState
        walkObservation = Task { @MainActor [weak self] in
            let itemManager = appState.itemManager
            // A walk may have changed which item is first.
            for await _ in Observations({ itemManager.managedItems.map(\.tag) }) {
                self?.refindAnchor()
            }
        }
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval, tolerance: .milliseconds(100))
                await self?.poll()
            }
        }
    }

    /// Reads the edge now, on the calling thread. For callers that cannot
    /// wait for the next poll, such as an event tap about to change the bar.
    func readNow() -> CGFloat? {
        guard let anchor else { return nil }
        return Self.position(of: anchor.element, within: anchor.screen, timeout: 0.05)
    }

    private func poll() async {
        guard let anchor else {
            refindAnchor()
            return
        }
        let edge = await Self.read(anchor)
        guard let current = self.anchor,
              current.screen == anchor.screen, CFEqual(current.element, anchor.element)
        else { return }
        if edge == nil {
            // The anchor left the bar or was re-created: find it again, and
            // report the change so followers re-measure.
            refindAnchor()
        }
        let sample = edge.map { MenuBarLeadingEdgeSample(x: $0, screenFrame: anchor.screen) }
        if let sample, let previous = leadingEdge,
           sample.screenFrame == previous.screenFrame, abs(sample.x - previous.x) < 1 {
            return
        }
        guard sample != leadingEdge else { return }
        diagLog.debug("leading edge moved \(leadingEdge.map { "\(Int($0.x))" } ?? "nil") → \(edge.map { "\(Int($0))" } ?? "nil")")
        leadingEdge = sample
    }

    /// Picks the element to watch: of the first visible item's owner, the
    /// on-screen child nearest the cached bounds. Nearest rather than
    /// leftmost, because one owner (MenuBarAgent) hosts many items.
    private func refindAnchor() {
        anchorTask?.cancel()
        anchorTask = nil
        guard let appState else { return }
        let controller = appState.menuBarManager.sectionController
        let visible = appState.itemManager.managedItems.filter { item in
            item.bounds.width > 0
                && (item.tag.matchesVisibleControlItem || (item.isOnScreen && controller.section(for: item) == .visible))
        }
        // Seated items only, as in ClockBridgeCover: an item parked at the
        // x == -1 sentinel would sort first, sit on no screen and leave the
        // edge unwatched.
        let screenFrames = NSScreen.screens.map(\.cgFrame)
        let seated = visible.compactMap { item in
            MenuBarItemGeometry.barScreen(holding: item.bounds, among: screenFrames).map { (item: item, screen: $0) }
        }
        guard let first = seated.min(by: { $0.item.bounds.minX < $1.item.bounds.minX }) else {
            anchor = nil
            return
        }
        let screen = first.screen
        let pid = first.item.sourcePID ?? first.item.ownerPID
        let expected = first.item.bounds.minX
        anchorTask = Task { [weak self] in
            let found = await Self.nearestChild(of: pid, to: expected, within: screen)
            guard !Task.isCancelled else { return }
            self?.anchor = found
        }
    }

    // MARK: Accessibility

    @concurrent
    private static nonisolated func read(_ anchor: LeadingEdgeAnchor) async -> CGFloat? {
        position(of: anchor.element, within: anchor.screen, timeout: 0.25)
    }

    @concurrent
    private static nonisolated func nearestChild(
        of pid: pid_t,
        to x: CGFloat,
        within screen: CGRect
    ) async -> LeadingEdgeAnchor? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var bar: AnyObject?
        guard AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &bar) == .success,
              // The type check is what makes the downcast below safe.
              let bar, CFGetTypeID(bar) == AXUIElementGetTypeID()
        else {
            return nil
        }
        var children: AnyObject?
        guard AXUIElementCopyAttributeValue(unsafeDowncast(bar, to: AXUIElement.self), kAXChildrenAttribute as CFString, &children) == .success,
              let children = children as? [AXUIElement]
        else {
            return nil
        }
        return children
            .compactMap { child in position(of: child, within: screen, timeout: 0.25).map { (child, abs($0 - x)) } }
            .min { $0.1 < $1.1 }
            .map { LeadingEdgeAnchor(element: $0.0, screen: screen) }
    }

    /// The element's left edge, when it is on screen within screen.
    /// Concealed items report a position at or left of the screen's edge.
    static nonisolated func position(of element: AXUIElement, within screen: CGRect, timeout: Float) -> CGFloat? {
        AXUIElementSetMessagingTimeout(element, timeout)
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cgPoint, &point),
              point.x != MenuBarItemGeometry.transientSentinelX,
              point.x > screen.minX, screen.contains(point),
              point.y - screen.minY <= MenuBarItemGeometry.maxOnBarMidY
        else {
            return nil
        }
        return point.x
    }
}

/// The authored Visible section's edge, not the edge of a revealed section.
nonisolated struct MenuBarLeadingEdgeSample: Equatable, Sendable {
    let x: CGFloat
    let screenFrame: CGRect
}

/// The watched element and the screen it sits on.
nonisolated struct LeadingEdgeAnchor: @unchecked Sendable {
    // AXUIElement is an immutable CF handle, safe to use from any thread.
    let element: AXUIElement
    let screen: CGRect
}

extension NSScreen {
    /// The screen's frame in top-left CG-global coordinates, the space the
    /// window server and menu bar item bounds use.
    var cgFrame: CGRect {
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? frame.maxY
        return CGRect(x: frame.minX, y: primaryMaxY - frame.maxY, width: frame.width, height: frame.height)
    }

    /// cgRect, from top-left CG-global coordinates into the bottom-left
    /// Cocoa-global ones windows are placed in, or nil with no screens. Both
    /// share the primary display's left origin and differ only by a flip about
    /// its height.
    static func cocoaRect(fromCG cgRect: CGRect) -> CGRect? {
        guard let primaryMaxY = screens.first?.frame.maxY else { return nil }
        return CGRect(x: cgRect.minX, y: primaryMaxY - cgRect.maxY, width: cgRect.width, height: cgRect.height)
    }
}
