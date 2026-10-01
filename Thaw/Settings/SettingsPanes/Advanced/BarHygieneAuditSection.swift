//
//  BarHygieneAuditSection.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import SwiftUI
import ThawUI

/// Keep the experimental audit passive because its false-positive rate is unmeasured.
/// Call unclicked items quiet, not unused: only menu bar presses are observed; history also clears on settings reset.
struct BarHygieneAuditSection: View {
    /// Newly installed items need time before a lack of clicks means anything.
    private static let quietQualificationAge: TimeInterval = 60 * 60 * 24 * 30

    /// Limit the summary, not the ledger's retained history.
    private static let recentChangeLimit = 20

    /// A current item old enough to qualify, with no observed menu bar press.
    private struct QuietRow: Identifiable {
        let id: String
        let name: String
        let firstSeen: Date
    }

    @Environment(AppState.self) private var appState

    var body: some View {
        recentChanges
        quietItems
        clearHistory
    }

    // MARK: Recent changes

    private var recentChanges: some View {
        ThawSection("Recent changes") {
            let events = Array(appState.hygieneAudit.ledger.events.prefix(Self.recentChangeLimit))
            if events.isEmpty {
                ThawEmptyState(
                    systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    title: "Nothing has changed yet",
                    caption: "\(Constants.displayName) is watching your menu bar. Items appearing and disappearing will be listed here."
                )
            } else {
                ForEach(events) { event in
                    LabeledContent {
                        Text(event.date, format: .relative(presentation: .named))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    } label: {
                        Label {
                            Text(label(for: event))
                        } icon: {
                            Image(systemName: event.kind == .appeared ? "plus.circle" : "minus.circle")
                                .foregroundStyle(event.kind == .appeared ? Color.accentColor : .secondary)
                        }
                    }
                }
            }
        }
    }

    /// Describe observed arrival/departure and app correlation without claiming installation or removal.
    private func label(for event: HygieneEvent) -> LocalizedStringKey {
        switch (event.kind, event.correlation) {
        case (.appeared, .appLaunch):
            "\(event.displayName) appeared when its app started"
        case (.appeared, _):
            "\(event.displayName) appeared"
        case (.disappeared, .appTermination):
            "\(event.displayName) left when its app quit"
        case (.disappeared, _):
            "\(event.displayName) left the menu bar"
        }
    }

    // MARK: Quiet items

    private var quietItems: some View {
        ThawSection {
            Text("Quiet items")
                .font(ThawType.heading)
        } content: {
            let rows = quietRows()
            if rows.isEmpty {
                ThawEmptyState(
                    systemImage: "hand.tap",
                    title: "Nothing has gone quiet",
                    caption: "Items you have never clicked, and that have been around for a month, would be listed here."
                )
            } else {
                ForEach(rows) { row in
                    LabeledContent {
                        Text("since \(row.firstSeen, format: .dateTime.month().day().year())")
                            .foregroundStyle(.secondary)
                    } label: {
                        Text(row.name)
                    }
                }
            }
        } footer: {
            Text("\(Constants.displayName) can only see clicks that land on the menu bar. An item you open with a keyboard shortcut, or that does its job without ever being clicked, will show up here, and that does not make it unused.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// Require current, old-enough items; departed and newly installed items are not evidence of disuse.
    /// Exclude live clocks and metrics because looking at them, not clicking, is their purpose.
    private func quietRows() -> [QuietRow] {
        let records = appState.hygieneAudit.ledger.records
        let volatility = appState.imageCache.volatilityIndex
        let cutoff = Date().addingTimeInterval(-Self.quietQualificationAge)

        var seen = Set<String>()
        return appState.itemManager.itemCache.managedItems
            .compactMap { item -> QuietRow? in
                guard HygieneRosterDiff.isRecordable(item),
                      volatility.volatility(for: item.tag) != .live
                else {
                    return nil
                }
                let identifier = MenuBarItemTag.canonicalPersistentIdentifier(item.tag.tagIdentifier)
                guard seen.insert(identifier).inserted,
                      let record = records[identifier],
                      record.lastActivated == nil,
                      record.firstSeen < cutoff
                else {
                    return nil
                }
                return QuietRow(
                    id: identifier,
                    name: MenuBarItemDisplayName.displayName(for: item),
                    firstSeen: record.firstSeen
                )
            }
            .sorted { $0.firstSeen < $1.firstSeen }
    }

    // MARK: Clearing

    private var clearHistory: some View {
        ThawSection {
            LabeledContent {
                Button("Clear History", role: .destructive) {
                    appState.hygieneAudit.ledger.clear()
                }
                .buttonStyle(.settingsGlass)
                .disabled(appState.hygieneAudit.ledger.events.isEmpty
                    && appState.hygieneAudit.ledger.records.isEmpty)
            } label: {
                Text("Menu bar history")
            }
        } footer: {
            Text("Everything above is stored on this Mac in \(Constants.displayName)'s own settings, and nowhere else. Turning the experiment off clears it too.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
