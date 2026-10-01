//
//  MenuBarHygieneLedger.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Observation

// MARK: - HygieneItemRecord

/// What the ledger remembers about one item across its whole life.
nonisolated struct HygieneItemRecord: Codable, Equatable, Sendable {
    var firstSeen: Date
    var lastSeen: Date

    /// Last press inside the item's bounds. Nil means no press seen, not
    /// unused: hotkey and Shortcut activations are invisible to Thaw.
    var lastActivated: Date?

    /// Kept because nothing can name an item whose owner has quit.
    var displayNameAtFirstSight: String
}

// MARK: - HygieneEvent

/// One committed observation of an item arriving or leaving.
nonisolated struct HygieneEvent: Codable, Equatable, Sendable, Identifiable {
    let identifier: String
    let kind: HygieneEventKind
    let date: Date
    let displayName: String
    let ownerBundleIdentifier: String?
    let correlation: HygieneCorrelation?

    /// Stable enough for ForEach: an item cannot appear twice at the same
    /// instant, and the ledger never rewrites an event once committed.
    var id: String {
        "\(identifier)|\(kind.rawValue)|\(date.timeIntervalSinceReferenceDate)"
    }
}

// MARK: - MenuBarHygieneLedger

/// The audit's only persisted state: one local JSON blob in Thaw's defaults,
/// with no network or telemetry, all visible and clearable in Settings.
///
/// records holds one entry per item, pruned by age; events is a capped tail,
/// newest first. A schema change drops the blob instead of migrating, since
/// watching the bar for a few seconds rebuilds it.
@MainActor
@Observable
final class MenuBarHygieneLedger {
    /// Bumping currentVersion discards whatever is on disk.
    private struct PersistedLedger: Codable {
        var version: Int
        var records: [String: HygieneItemRecord]
        var events: [HygieneEvent]
    }

    private static let currentVersion = 1

    /// Enough for a login storm and a week of ordinary use.
    static let maxEvents = 200

    /// How long a record survives without the item being seen again.
    static let recordLifetime: TimeInterval = 60 * 60 * 24 * 90

    private static nonisolated let diagLog = DiagLog(category: "MenuBarHygieneAudit")

    /// How stale lastSeen may get before a sighting is recorded. Sightings
    /// arrive at 1 Hz and would otherwise invalidate observing views each time.
    static let observationCoalescing: TimeInterval = 60

    /// How long unsaved sightings may sit in memory. Events save immediately;
    /// sightings wait so an idle bar does not encode JSON every minute.
    static let saveInterval: TimeInterval = 300

    private(set) var records: [String: HygieneItemRecord] = [:]

    private var hasUnsavedSightings = false
    private var lastSaved = Date.distantPast

    /// Newest first, so the cap drops the oldest.
    private(set) var events: [HygieneEvent] = []

    init() {
        load()
    }

    // MARK: Recording

    /// Called for every item in every confirmed roster, since the quiet list
    /// and age prune read lastSeen even when nothing changed.
    func observe(_ entry: HygieneRosterEntry, at date: Date) {
        if var record = records[entry.identifier] {
            guard date.timeIntervalSince(record.lastSeen) >= Self.observationCoalescing else {
                return
            }
            record.lastSeen = date
            records[entry.identifier] = record
            hasUnsavedSightings = true
        } else {
            records[entry.identifier] = HygieneItemRecord(
                firstSeen: date,
                lastSeen: date,
                lastActivated: nil,
                displayNameAtFirstSight: entry.displayName
            )
            hasUnsavedSightings = true
        }
    }

    /// Flushes coalesced sightings, at most once per saveInterval.
    func saveIfNeeded() {
        guard hasUnsavedSightings,
              Date().timeIntervalSince(lastSaved) >= Self.saveInterval
        else {
            return
        }
        save()
    }

    func record(_ event: HygieneEvent) {
        events.insert(event, at: 0)
        if events.count > Self.maxEvents {
            events.removeLast(events.count - Self.maxEvents)
        }
        let correlation = event.correlation.map { " (\($0.rawValue))" } ?? ""
        Self.diagLog.notice("\(event.kind.rawValue): \(event.displayName)\(correlation)")
        save()
    }

    /// Runs on the mouse path, so it never writes to disk.
    func noteActivation(of identifier: String, at date: Date) {
        guard var record = records[identifier] else {
            return
        }
        record.lastActivated = date
        records[identifier] = record
    }

    // MARK: Clearing

    /// Also runs when the experiment is switched off, so off means never on.
    func clear() {
        records = [:]
        events = []
        hasUnsavedSightings = false
        lastSaved = .distantPast
        Defaults.removeObject(forKey: .menuBarHygieneLedger)
        Self.diagLog.notice("ledger cleared")
    }

    // MARK: Persistence

    /// Prunes records older than recordLifetime, then writes. Called on
    /// commit, which is rare, not on a timer.
    func save() {
        hasUnsavedSightings = false
        lastSaved = Date()
        let cutoff = Date().addingTimeInterval(-Self.recordLifetime)
        let live = records.filter { $0.value.lastSeen > cutoff }
        if live.count != records.count {
            Self.diagLog.notice("pruned \(self.records.count - live.count) record(s) past their lifetime")
            records = live
        }

        guard !live.isEmpty || !events.isEmpty else {
            Defaults.removeObject(forKey: .menuBarHygieneLedger)
            return
        }

        let ledger = PersistedLedger(version: Self.currentVersion, records: live, events: events)
        do {
            try Defaults.set(JSONEncoder().encode(ledger), forKey: .menuBarHygieneLedger)
        } catch {
            Self.diagLog.error("failed to encode ledger: \(error)")
        }
    }

    private func load() {
        guard let data = Defaults.data(forKey: .menuBarHygieneLedger) else {
            return
        }
        let ledger: PersistedLedger
        do {
            ledger = try JSONDecoder().decode(PersistedLedger.self, from: data)
        } catch {
            Self.diagLog.error("failed to decode ledger: \(error)")
            Defaults.removeObject(forKey: .menuBarHygieneLedger)
            return
        }
        guard ledger.version == Self.currentVersion else {
            Self.diagLog.notice("dropping ledger (version \(ledger.version) != \(Self.currentVersion))")
            Defaults.removeObject(forKey: .menuBarHygieneLedger)
            return
        }
        let cutoff = Date().addingTimeInterval(-Self.recordLifetime)
        records = ledger.records.filter { $0.value.lastSeen > cutoff }
        events = Array(ledger.events.prefix(Self.maxEvents))
        Self.diagLog.notice("loaded \(self.records.count) record(s), \(self.events.count) event(s)")
    }
}
