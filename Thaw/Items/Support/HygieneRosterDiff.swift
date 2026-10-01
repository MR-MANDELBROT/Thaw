//
//  HygieneRosterDiff.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

// MARK: - HygieneRosterEntry

/// One item as the audit records it: a stable key, the name to show if the
/// item is never seen again, and whoever owns it.
///
/// Not a MenuBarItem, whose window ID and bounds mean nothing once the owner
/// quits.
nonisolated struct HygieneRosterEntry: Equatable, Sendable {
    /// The canonical identifier, so an item with a live title (a clock) keeps
    /// one identity instead of arriving and departing every tick.
    let identifier: String

    /// The name at the moment of recording, stored because nothing can name
    /// an item that is gone.
    let displayName: String

    /// The owning app's bundle identifier, when the namespace is one. Used to
    /// correlate a change with that app launching or quitting.
    let ownerBundleIdentifier: String?
}

// MARK: - HygieneRosterChange

/// What one confirmed roster differs by. Observational on purpose: the audit
/// cannot tell an install from a relaunch or a settings change.
nonisolated struct HygieneRosterChange: Equatable, Sendable {
    var appeared: [String] = []
    var disappeared: [String] = []

    var isEmpty: Bool {
        appeared.isEmpty && disappeared.isEmpty
    }
}

// MARK: - HygieneEventKind

nonisolated enum HygieneEventKind: String, Codable, Sendable {
    case appeared
    case disappeared
}

// MARK: - HygieneCorrelation

/// The uninteresting explanation for a change, when there is one.
///
/// Marked so the interesting case stands out: an item appearing while its
/// owner was already running.
nonisolated enum HygieneCorrelation: String, Codable, Sendable {
    case appLaunch
    case appTermination
}

// MARK: - AppLifecycleEvent

/// An app launching or quitting, as NSWorkspace reports it.
nonisolated struct AppLifecycleEvent: Equatable, Sendable {
    enum Kind: Sendable {
        case launched
        case terminated
    }

    let bundleIdentifier: String
    let kind: Kind
    let date: Date
}

// MARK: - HygieneRosterDiff

/// Pure roster construction and diffing, kept apart from MenuBarHygieneAudit
/// so it can be tested without a live menu bar.
nonisolated enum HygieneRosterDiff {
    // MARK: Eligibility

    /// Whether the audit records an item. Every rule prevents a false arrival.
    ///
    /// A nil sourcePID means the owner is unresolved and would book a second
    /// arrival later; non-string namespaces do not survive a restart. On macOS 27
    /// MenuBarAgent is also the fallback namespace, so only catalog modules count.
    static func isRecordable(_ item: MenuBarItem) -> Bool {
        guard !item.isControlItem,
              !item.tag.isThawOwnedNamespace,
              !item.isSystemClone,
              !item.isNativeOverflowControl,
              !item.tag.isCaptureActivityIndicator,
              !item.isTransientControlCenterItem,
              !item.isBentoBox,
              item.sourcePID != nil,
              item.tag.namespace.isString
        else {
            return false
        }
        guard item.tag.namespace == .menuBarAgent else {
            return true
        }
        return SystemMenuBarModuleCatalog.moduleName(matching: item.tag.title) != nil
    }

    /// The recordable items, keyed by canonical identifier.
    ///
    /// name is injected so this stays pure; the display name is main-actor.
    static func roster(
        from items: [MenuBarItem],
        name: (MenuBarItem) -> String
    ) -> [String: HygieneRosterEntry] {
        items.reduce(into: [:]) { roster, item in
            guard isRecordable(item) else {
                return
            }
            let identifier = MenuBarItemTag.canonicalPersistentIdentifier(item.tag.tagIdentifier)
            // First writer wins: two items sharing a key are one item seen twice.
            guard roster[identifier] == nil else {
                return
            }
            roster[identifier] = HygieneRosterEntry(
                identifier: identifier,
                displayName: name(item),
                ownerBundleIdentifier: ownerBundleIdentifier(for: item)
            )
        }
    }

    /// The bundle identifier behind an item's namespace.
    ///
    /// Read from the namespace because sourceApplication needs a live process
    /// and answers nil for departures.
    static func ownerBundleIdentifier(for item: MenuBarItem) -> String? {
        guard case let .string(bundleIdentifier) = item.tag.namespace else {
            return nil
        }
        return bundleIdentifier
    }

    // MARK: Correlation

    /// The uninteresting explanation for kind happening to an item owned by
    /// ownerBundleIdentifier, if one is on the recent lifecycle list.
    ///
    /// Only the matching direction counts: a quit does not explain an arrival.
    static func correlation(
        for kind: HygieneEventKind,
        ownerBundleIdentifier: String?,
        among lifecycle: [AppLifecycleEvent],
        now: Date,
        window: TimeInterval
    ) -> HygieneCorrelation? {
        guard let ownerBundleIdentifier else {
            return nil
        }
        let wanted: AppLifecycleEvent.Kind = kind == .appeared ? .launched : .terminated
        let matched = lifecycle.contains { event in
            event.bundleIdentifier == ownerBundleIdentifier
                && event.kind == wanted
                && now.timeIntervalSince(event.date) <= window
                && now >= event.date
        }
        guard matched else {
            return nil
        }
        return kind == .appeared ? .appLaunch : .appTermination
    }
}

// MARK: - HygieneCommitGate

/// The two-sided gate between "the roster changed" and "write it down".
///
/// Asymmetric on purpose. Arrivals need a prior sighting (noteSighting(_:))
/// so a flapping item is never reported. Departures need one roster, since a
/// wrong one self-corrects as an arrival. The first baseline is seeded silently.
nonisolated struct HygieneCommitGate: Equatable, Sendable {
    /// The last committed roster. nil until seeded, which is what makes the
    /// first roster of a session silent.
    private(set) var baseline: Set<String>?

    /// Identifiers seen in one roster and waiting on a second.
    private(set) var provisionalArrivals: Set<String> = []

    var isSeeded: Bool {
        baseline != nil
    }

    /// Adopts roster as truth without announcing any of it.
    ///
    /// Used at startup and after every suppression window.
    mutating func seed(_ roster: Set<String>) {
        baseline = roster
        provisionalArrivals = []
    }

    /// Marks whatever in roster is not in the baseline as seen once, without
    /// admitting anything.
    ///
    /// The caller's persistence window counts as the first sighting, so an
    /// arrival needs one window rather than two. No-op before the baseline.
    mutating func noteSighting(_ roster: Set<String>) {
        guard let baseline else {
            return
        }
        provisionalArrivals = roster.subtracting(baseline)
    }

    /// Offers a confirmed roster and returns what it is worth recording.
    mutating func admit(_ roster: Set<String>) -> HygieneRosterChange {
        guard let baseline else {
            seed(roster)
            return HygieneRosterChange()
        }

        let departed = baseline.subtracting(roster)
        let candidates = roster.subtracting(baseline)
        let confirmed = candidates.intersection(provisionalArrivals)

        // Unconfirmed candidates are dropped, not carried, or a flapping item
        // would accumulate confirmations.
        provisionalArrivals = candidates.subtracting(confirmed)
        self.baseline = baseline.subtracting(departed).union(confirmed)

        return HygieneRosterChange(
            appeared: confirmed.sorted(),
            disappeared: departed.sorted()
        )
    }
}
