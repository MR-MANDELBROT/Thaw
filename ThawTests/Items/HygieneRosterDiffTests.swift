//
//  HygieneRosterDiffTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// Pins the exclusion rules and the commit gate, the only decisions the
/// audit makes.
@Suite("Bar hygiene roster diff")
struct HygieneRosterDiffTests {
    // MARK: Fixtures

    private static func item(
        namespace: MenuBarItemTag.Namespace = .string("com.example.App"),
        title: String = "Item-0",
        sourcePID: pid_t? = 501,
        instanceIndex: Int = 0
    ) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: namespace, title: title, instanceIndex: instanceIndex),
            windowID: 1,
            ownerPID: 100,
            sourcePID: sourcePID,
            bounds: CGRect(x: 0, y: 0, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    // MARK: Eligibility

    @Test("An ordinary third-party item is recordable")
    func ordinaryItemIsRecordable() {
        #expect(HygieneRosterDiff.isRecordable(Self.item()))
    }

    @Test("An item whose owner has not resolved yet is skipped")
    func unresolvedSourceIsSkipped() {
        #expect(!HygieneRosterDiff.isRecordable(Self.item(sourcePID: nil)))
    }

    @Test("A UUID namespace is skipped: it does not survive a restart")
    func uuidNamespaceIsSkipped() {
        #expect(!HygieneRosterDiff.isRecordable(Self.item(namespace: .uuid(UUID()))))
    }

    @Test("The null namespace is skipped")
    func nullNamespaceIsSkipped() {
        #expect(!HygieneRosterDiff.isRecordable(Self.item(namespace: .null)))
    }

    @Test("Thaw's own control items are furniture, not inventory")
    func controlItemIsSkipped() {
        let control = MenuBarItem(
            tag: .hiddenControlItem,
            windowID: 2,
            ownerPID: 100,
            sourcePID: 501,
            bounds: .zero,
            title: nil,
            isOnScreen: false
        )
        #expect(!HygieneRosterDiff.isRecordable(control))
    }

    @Test("A system clone is the same item counted twice")
    func systemCloneIsSkipped() {
        #expect(!HygieneRosterDiff.isRecordable(Self.item(title: "System Status Item Clone")))
    }

    @Test("A MenuBarAgent child that is not a known module is a re-vend")
    func unknownMenuBarAgentChildIsSkipped() {
        #expect(!HygieneRosterDiff.isRecordable(
            Self.item(namespace: .menuBarAgent, title: "SomethingUnrecognised")
        ))
    }

    @Test("A MenuBarAgent child the catalog recognises is genuinely its own")
    func knownMenuBarAgentModuleIsRecordable() {
        #expect(HygieneRosterDiff.isRecordable(
            Self.item(namespace: .menuBarAgent, title: "Clock")
        ))
    }

    @Test("A process-name namespace is kept, it is still stable across launches")
    func processNameNamespaceIsRecordable() {
        #expect(HygieneRosterDiff.isRecordable(
            Self.item(namespace: .string("iStatMenusMenubar"))
        ))
    }

    // MARK: Roster

    @Test("The roster keys on the canonical identifier and drops the ineligible")
    func rosterFiltersAndKeys() {
        let roster = HygieneRosterDiff.roster(
            from: [
                Self.item(namespace: .string("com.example.App"), title: "Main"),
                Self.item(namespace: .uuid(UUID()), title: "Transient"),
                Self.item(namespace: .string("com.example.Other"), title: "Other", sourcePID: nil),
            ],
            name: { $0.tag.title }
        )
        #expect(roster.count == 1)
        #expect(roster["com.example.App:Main"]?.displayName == "Main")
        #expect(roster["com.example.App:Main"]?.ownerBundleIdentifier == "com.example.App")
    }

    @Test("Two items collapsing to one key are recorded once")
    func duplicateKeysCollapse() {
        let roster = HygieneRosterDiff.roster(
            from: [
                Self.item(title: "Main"),
                Self.item(title: "Main"),
            ],
            name: { _ in "Main" }
        )
        #expect(roster.count == 1)
    }

    // MARK: Correlation

    private static let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    @Test("An arrival within the window of its owner launching is explained")
    func arrivalCorrelatesWithLaunch() {
        let lifecycle = [
            AppLifecycleEvent(
                bundleIdentifier: "com.example.App",
                kind: .launched,
                date: Self.now.addingTimeInterval(-5)
            ),
        ]
        #expect(HygieneRosterDiff.correlation(
            for: .appeared,
            ownerBundleIdentifier: "com.example.App",
            among: lifecycle,
            now: Self.now,
            window: 30
        ) == .appLaunch)
    }

    @Test("An arrival while its owner quit is not explained by the quit")
    func arrivalDoesNotCorrelateWithTermination() {
        let lifecycle = [
            AppLifecycleEvent(
                bundleIdentifier: "com.example.App",
                kind: .terminated,
                date: Self.now.addingTimeInterval(-5)
            ),
        ]
        #expect(HygieneRosterDiff.correlation(
            for: .appeared,
            ownerBundleIdentifier: "com.example.App",
            among: lifecycle,
            now: Self.now,
            window: 30
        ) == nil)
    }

    @Test("A launch outside the window explains nothing")
    func staleLifecycleDoesNotCorrelate() {
        let lifecycle = [
            AppLifecycleEvent(
                bundleIdentifier: "com.example.App",
                kind: .launched,
                date: Self.now.addingTimeInterval(-120)
            ),
        ]
        #expect(HygieneRosterDiff.correlation(
            for: .appeared,
            ownerBundleIdentifier: "com.example.App",
            among: lifecycle,
            now: Self.now,
            window: 30
        ) == nil)
    }

    @Test("Another app's launch explains nothing")
    func otherAppDoesNotCorrelate() {
        let lifecycle = [
            AppLifecycleEvent(
                bundleIdentifier: "com.example.Unrelated",
                kind: .launched,
                date: Self.now
            ),
        ]
        #expect(HygieneRosterDiff.correlation(
            for: .appeared,
            ownerBundleIdentifier: "com.example.App",
            among: lifecycle,
            now: Self.now,
            window: 30
        ) == nil)
    }

    @Test("A departure correlates with its owner terminating")
    func departureCorrelatesWithTermination() {
        let lifecycle = [
            AppLifecycleEvent(
                bundleIdentifier: "com.example.App",
                kind: .terminated,
                date: Self.now
            ),
        ]
        #expect(HygieneRosterDiff.correlation(
            for: .disappeared,
            ownerBundleIdentifier: "com.example.App",
            among: lifecycle,
            now: Self.now,
            window: 30
        ) == .appTermination)
    }

    // MARK: Commit gate

    @Test("The first roster seeds the baseline and announces nothing")
    func firstRosterIsSilent() {
        var gate = HygieneCommitGate()
        let change = gate.admit(["a", "b"])
        #expect(change.isEmpty)
        #expect(gate.isSeeded)
        #expect(gate.baseline == ["a", "b"])
    }

    @Test("An explicit seed also announces nothing and clears provisionals")
    func seedIsSilent() {
        var gate = HygieneCommitGate()
        gate.seed(["a"])
        _ = gate.admit(["a", "b"])
        gate.seed(["a", "b", "c"])
        #expect(gate.provisionalArrivals.isEmpty)
        #expect(gate.admit(["a", "b", "c"]).isEmpty)
    }

    @Test("An arrival needs two consecutive rosters before it commits")
    func arrivalNeedsTwoRosters() {
        var gate = HygieneCommitGate()
        gate.seed(["a"])

        let first = gate.admit(["a", "b"])
        #expect(first.isEmpty)
        #expect(gate.provisionalArrivals == ["b"])

        let second = gate.admit(["a", "b"])
        #expect(second.appeared == ["b"])
        #expect(gate.baseline == ["a", "b"])
    }

    @Test("An item that flaps in and out is never recorded")
    func flapIsNeverRecorded() {
        var gate = HygieneCommitGate()
        gate.seed(["a"])

        #expect(gate.admit(["a", "b"]).isEmpty)
        #expect(gate.admit(["a"]).isEmpty)
        #expect(gate.admit(["a", "b"]).isEmpty)
        #expect(gate.admit(["a"]).isEmpty)
        #expect(gate.baseline == ["a"])
    }

    @Test("A departure commits on the first roster that misses it")
    func departureCommitsImmediately() {
        var gate = HygieneCommitGate()
        gate.seed(["a", "b"])

        let change = gate.admit(["a"])
        #expect(change.disappeared == ["b"])
        #expect(change.appeared.isEmpty)
        #expect(gate.baseline == ["a"])
    }

    @Test("An item that leaves and returns has to earn its arrival again")
    func returnRequiresConfirmationAgain() {
        var gate = HygieneCommitGate()
        gate.seed(["a", "b"])

        #expect(gate.admit(["a"]).disappeared == ["b"])
        #expect(gate.admit(["a", "b"]).isEmpty)
        #expect(gate.admit(["a", "b"]).appeared == ["b"])
    }

    @Test("A confirmed arrival is announced once, not on every later roster")
    func arrivalAnnouncesOnce() {
        var gate = HygieneCommitGate()
        gate.seed([])
        _ = gate.admit(["a"])
        #expect(gate.admit(["a"]).appeared == ["a"])
        #expect(gate.admit(["a"]).isEmpty)
        #expect(gate.admit(["a"]).isEmpty)
    }

    @Test("Arrivals and departures in one roster are both reported")
    func mixedChange() {
        var gate = HygieneCommitGate()
        gate.seed(["a", "b"])

        #expect(gate.admit(["a", "c"]).disappeared == ["b"])
        let change = gate.admit(["a", "c"])
        #expect(change.appeared == ["c"])
        #expect(change.disappeared.isEmpty)
    }

    @Test("Reported identifiers are sorted, so the ledger order is stable")
    func changesAreSorted() {
        var gate = HygieneCommitGate()
        gate.seed(["z", "y", "x"])
        let change = gate.admit([])
        #expect(change.disappeared == ["x", "y", "z"])
    }

    // MARK: Sightings

    /// The persistence window counts as a sighting, or an arrival would need
    /// two windows and never survive a reflowing bar.
    @Test("A sighted arrival is confirmed on the first admission")
    func sightedArrivalConfirmsImmediately() {
        var gate = HygieneCommitGate()
        gate.seed(["a", "b"])
        gate.noteSighting(["a", "b", "c"])
        #expect(gate.admit(["a", "b", "c"]).appeared == ["c"])
    }

    @Test("An unsighted arrival still needs a second roster")
    func unsightedArrivalStillWaits() {
        var gate = HygieneCommitGate()
        gate.seed(["a", "b"])
        #expect(gate.admit(["a", "b", "c"]).isEmpty)
    }

    @Test("A sighting names only what the baseline does not already hold")
    func sightingIgnoresKnownItems() {
        var gate = HygieneCommitGate()
        gate.seed(["a", "b"])
        gate.noteSighting(["a", "b"])
        #expect(gate.provisionalArrivals.isEmpty)
    }

    /// The candidate changing between the sighting and the admission is the
    /// flap case: what was sighted is not what arrived, so it is not confirmed.
    @Test("A sighting does not vouch for a different arrival")
    func sightingDoesNotVouchForSomethingElse() {
        var gate = HygieneCommitGate()
        gate.seed(["a"])
        gate.noteSighting(["a", "b"])
        #expect(gate.admit(["a", "c"]).appeared.isEmpty)
    }

    @Test("A sighting before the baseline exists claims nothing")
    func sightingBeforeSeedingIsInert() {
        var gate = HygieneCommitGate()
        gate.noteSighting(["a", "b"])
        #expect(gate.provisionalArrivals.isEmpty)
        #expect(gate.admit(["a", "b"]).isEmpty)
    }

    @Test("A sighting never fabricates a departure")
    func sightingDoesNotAffectDepartures() {
        var gate = HygieneCommitGate()
        gate.seed(["a", "b"])
        gate.noteSighting(["a", "b", "c"])
        let change = gate.admit(["a", "c"])
        #expect(change.disappeared == ["b"])
        #expect(change.appeared == ["c"])
    }
}
