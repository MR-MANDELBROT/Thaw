//
//  MenuBarHygieneAudit.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import Foundation
import MenuBarModel
import Observation

/// Polls the published cache independently, with no work when disabled; suppression and commit gates filter reflow, move, login, and display disturbances.
/// Report only "appeared"/"disappeared", not installs/removals, and avoid notifications because false positives would interrupt users.
@MainActor
@Observable
final class MenuBarHygieneAudit {
    private nonisolated let diagLog = DiagLog(category: "MenuBarHygieneAudit")

    /// In-memory roster comparisons are cheap; a clock advances confirmation and suppression handling even without cache changes.
    static let tickInterval: Duration = .seconds(1)

    /// Allow delayed post-launch items while keeping lifecycle correlation limited to the same event.
    static let correlationWindow: TimeInterval = 30

    /// The store, exposed so the Settings section can read it.
    let ledger = MenuBarHygieneLedger()

    private weak var appState: AppState?

    /// The settings slice this manager observes, injected at setup.
    private var advancedSettings: AdvancedSettings?
    private var cancellables = Set<AnyCancellable>()

    /// Held apart from cancellables because these come and go with the
    /// flag, while the flag observer itself has to outlive every stop.
    private var lifecycleObservers: [AnyCancellable] = []
    private var tickTask: Task<Void, Never>?

    private var gate = HygieneCommitGate()

    /// Uses the cache poll's signatureRecacheDecision flap gate with a longer grace because audit changes are not time-critical.
    private var pendingRoster: [String]?
    private var pendingFirstSeen: ContinuousClock.Instant?

    private var lastRestrictionApplied: Bool?
    private var lifecycle: [AppLifecycleEvent] = []

    var isEnabled: Bool {
        advancedSettings?.enableBarHygieneAudit ?? false
    }

    func performSetup(with appState: AppState) {
        self.appState = appState
        advancedSettings = appState.settings.advanced
        cancellables = [observeSettingFlips()]
        if isEnabled {
            start()
        }
    }

    // MARK: Lifecycle

    private func start() {
        guard tickTask == nil else {
            return
        }
        diagLog.info("bar hygiene audit on")
        gate = HygieneCommitGate()
        lastRestrictionApplied = nil
        observeApplicationLifecycle()

        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: Self.tickInterval)
            }
        }
    }

    private func stop() {
        tickTask?.cancel()
        tickTask = nil
        lifecycleObservers = []
        gate = HygieneCommitGate()
        pendingRoster = nil
        pendingFirstSeen = nil
        lifecycle = []
        // Disabling collection also clears history so no disabled audit data remains.
        ledger.clear()
        diagLog.info("bar hygiene audit off")
    }

    // MARK: The tick

    private func tick() {
        guard let appState else {
            return
        }

        // Suppress restriction transitions, not the lasting flag; persistent concealment must not disable the audit.
        let restrictionApplied = appState.menuBarManager.sectionController.isRestrictionApplied
        let restrictionChanged = lastRestrictionApplied.map { $0 != restrictionApplied } ?? false
        lastRestrictionApplied = restrictionApplied

        if let reason = Self.suppressionReason(appState: appState) ?? (restrictionChanged ? "restriction reflow" : nil) {
            // Pause confirmation without reseeding or dropping the candidate, so frequent reflows cannot erase real changes.
            // A changed roster restarts the persistence clock on the next trusted tick.
            if pendingRoster != nil {
                diagLog.debug("tick suppressed (\(reason)); persistence clock paused")
            }
            pendingFirstSeen = pendingFirstSeen?.advanced(by: Self.tickInterval)
            return
        }

        let entries = HygieneRosterDiff.roster(
            from: appState.itemManager.itemCache.managedItems,
            name: MenuBarItemDisplayName.displayName(for:)
        )

        // An empty roster means an unbuilt or between-pass cache, not that every item departed.
        guard !entries.isEmpty else {
            return
        }

        let identifiers = Set(entries.keys)

        guard gate.isSeeded else {
            gate.seed(identifiers)
            let now = Date()
            for entry in entries.values {
                ledger.observe(entry, at: now)
            }
            diagLog.debug("baseline seeded with \(identifiers.count) item(s)")
            return
        }

        let baseline = gate.baseline ?? []
        let decision = MenuBarItemManager.signatureRecacheDecision(
            cached: baseline.sorted(),
            current: identifiers.sorted(),
            pending: pendingRoster,
            firstSeen: pendingFirstSeen,
            now: .now,
            grace: Constants.MenuBarTuning.hygieneConfirmationGrace
        )
        pendingRoster = decision.newPending
        pendingFirstSeen = decision.newFirstSeen

        // Register pending sightings to admit arrivals after one persistence window, not two with a suppression gap.
        if decision.newPending != nil {
            gate.noteSighting(identifiers)
        }

        let now = Date()
        for entry in entries.values {
            ledger.observe(entry, at: now)
        }

        guard decision.recache else {
            ledger.saveIfNeeded()
            return
        }
        commit(gate.admit(identifiers), entries: entries, at: now)
        ledger.saveIfNeeded()
    }

    /// Confirmed departures use the last recorded name because the item is no longer in entries.
    private func commit(
        _ change: HygieneRosterChange,
        entries: [String: HygieneRosterEntry],
        at date: Date
    ) {
        guard !change.isEmpty else {
            return
        }
        pruneLifecycle(before: date)

        for identifier in change.appeared {
            guard let entry = entries[identifier] else {
                continue
            }
            ledger.record(
                HygieneEvent(
                    identifier: identifier,
                    kind: .appeared,
                    date: date,
                    displayName: entry.displayName,
                    ownerBundleIdentifier: entry.ownerBundleIdentifier,
                    correlation: HygieneRosterDiff.correlation(
                        for: .appeared,
                        ownerBundleIdentifier: entry.ownerBundleIdentifier,
                        among: lifecycle,
                        now: date,
                        window: Self.correlationWindow
                    )
                )
            )
        }

        for identifier in change.disappeared {
            let name = ledger.records[identifier]?.displayNameAtFirstSight ?? identifier
            // The namespace is the owner, and it is the leading segment of the
            // identifier, the only owner still readable for an item that left.
            let owner = identifier.split(separator: ":", maxSplits: 1).first.map(String.init)
            ledger.record(
                HygieneEvent(
                    identifier: identifier,
                    kind: .disappeared,
                    date: date,
                    displayName: name,
                    ownerBundleIdentifier: owner,
                    correlation: HygieneRosterDiff.correlation(
                        for: .disappeared,
                        ownerBundleIdentifier: owner,
                        among: lifecycle,
                        now: date,
                        window: Self.correlationWindow
                    )
                )
            )
        }
    }

    // MARK: Suppression

    /// Suppress unsettled bar states so Thaw or macOS reflows are not attributed to item owners.
    static func suppressionReason(appState: AppState) -> String? {
        let itemManager = appState.itemManager
        if itemManager.isInStartupSettling {
            return "startup settling"
        }
        if itemManager.areControlItemsMissing {
            return "control items missing"
        }
        if appState.isDraggingMenuBarItem {
            return "drag in flight"
        }
        if itemManager.lastMoveOperationOccurred(within: .seconds(5)) {
            return "recent move"
        }
        return nil
    }

    // MARK: Activation

    /// Observes presses without consuming them; a hit records neither a successful action nor proof of disuse.
    func noteActivation(at location: CGPoint) {
        guard isEnabled, let appState else {
            return
        }
        let items = appState.itemManager.onScreenItemSnapshot.items
        guard let item = items.first(where: { $0.isOnScreen && !$0.bounds.isEmpty && $0.bounds.contains(location) }),
              HygieneRosterDiff.isRecordable(item)
        else {
            return
        }
        ledger.noteActivation(
            of: MenuBarItemTag.canonicalPersistentIdentifier(item.tag.tagIdentifier),
            at: Date()
        )
    }

    // MARK: Application lifecycle

    /// Lifecycle correlation explains roster changes; subscriptions exist only while the experiment is enabled.
    private func observeApplicationLifecycle() {
        lifecycleObservers = [
            (NSWorkspace.didLaunchApplicationNotification, AppLifecycleEvent.Kind.launched),
            (NSWorkspace.didTerminateApplicationNotification, AppLifecycleEvent.Kind.terminated),
        ].map(observeWorkspace)
    }

    /// Bridge lifecycle timestamps and bundle IDs to MainActor without debounce, which would discard login-storm correlations.
    private func observeWorkspace(
        _ notification: Notification.Name,
        as kind: AppLifecycleEvent.Kind
    ) -> AnyCancellable {
        let (events, continuation) = AsyncStream<String>.makeStream()
        let task = Task { @MainActor [weak self] in
            let observer = NSWorkspace.shared.notificationCenter.addObserver(
                forName: notification,
                object: nil,
                queue: .main
            ) { notification in
                let application = notification
                    .userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                if let bundleIdentifier = application?.bundleIdentifier {
                    continuation.yield(bundleIdentifier)
                }
            }
            defer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
            for await bundleIdentifier in events {
                self?.noteLifecycle(bundleIdentifier: bundleIdentifier, kind: kind)
            }
        }
        return AnyCancellable { task.cancel() }
    }

    private func noteLifecycle(bundleIdentifier: String, kind: AppLifecycleEvent.Kind) {
        let now = Date()
        pruneLifecycle(before: now)
        lifecycle.append(AppLifecycleEvent(bundleIdentifier: bundleIdentifier, kind: kind, date: now))
    }

    /// Drops lifecycle events too old to explain anything, which is the only
    /// thing bounding this list.
    private func pruneLifecycle(before date: Date) {
        lifecycle.removeAll { date.timeIntervalSince($0.date) > Self.correlationWindow }
    }

    // MARK: Flag

    /// Observe the Lab setting so UI bindings, thaw:// changes, and profile applies share the same lifecycle.
    private func observeSettingFlips() -> AnyCancellable {
        guard let advanced = advancedSettings else { return AnyCancellable {} }
        return advanced.observe(\.enableBarHygieneAudit) { [weak self] enabled in
            if enabled {
                self?.start()
            } else {
                self?.stop()
            }
        }
    }
}
