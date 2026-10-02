//
//  MenuBarAllowList.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import PlatformRuntimeKit

/// Apps switched off under System Settings > Menu Bar > Allow in the Menu Bar.
///
/// macOS 27 still publishes their items through accessibility, parked off the
/// bar, so without this list they turn up in Layout, the Thaw Bar and search
/// with the app's icon in place of a picture macOS never draws. The list is
/// Control Center's tracked applications, read through the same picked-file
/// access native app hiding uses; without that access nothing is filtered.
@MainActor
final class MenuBarAllowList {
    static let shared = MenuBarAllowList()

    /// Re-read at most this often when the file's date cannot be read.
    private static let undatedRereadInterval: TimeInterval = 5

    private let access = PickedFileAccess.controlCenterAppList
    private var cachedModificationDate: Date?
    private var lastReadDate: Date?
    private var cachedDisallowed: Set<String> = []
    private var loggedDisallowed: Set<String>?
    private var loggedFailure = false
    private let diagLog = DiagLog(category: "MenuBarAllowList")

    /// Bundle identifiers macOS keeps off the menu bar, empty when the list
    /// cannot be read. Re-reads the list only after it changes.
    func disallowedBundleIdentifiers() -> Set<String> {
        let now = Date()
        let modified = access.modificationDate()
        if let modified, modified == cachedModificationDate {
            return cachedDisallowed
        }
        if modified == nil, let lastReadDate,
           now.timeIntervalSince(lastReadDate) < Self.undatedRereadInterval
        {
            return cachedDisallowed
        }
        cachedModificationDate = modified
        lastReadDate = now
        // cfprefsd serves the domain even where a direct read is refused.
        let fromFile = access.readDictionary().flatMap(Self.disallowedBundleIdentifiers(in:))
        let fromPreferences = fromFile == nil ? Self.readPreferences().flatMap(Self.disallowedBundleIdentifiers(in:)) : nil
        guard let disallowed = fromFile ?? fromPreferences else {
            cachedDisallowed = []
            if !loggedFailure {
                loggedFailure = true
                diagLog.warning(
                    "Control Center's app list is not readable; filtering nothing. \(access.accessDiagnostics())"
                )
            }
            return []
        }
        loggedFailure = false
        cachedDisallowed = disallowed
        if loggedDisallowed != disallowed {
            loggedDisallowed = disallowed
            diagLog.info(
                "Apps not allowed in the menu bar by macOS (\(fromFile != nil ? "file" : "preferences")): \(disallowed.sorted())"
            )
        }
        return disallowed
    }

    /// Control Center's domain through cfprefsd, keyed like the plist file.
    private static func readPreferences() -> [String: Any]? {
        let domain = CFPreferencesTrackedApplications.defaultDomain as CFString
        guard let keys = CFPreferencesCopyKeyList(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String],
              !keys.isEmpty
        else {
            return nil
        }
        return CFPreferencesCopyMultiple(
            keys as CFArray,
            domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) as? [String: Any]
    }

    /// Reads the tracked applications as JSON data, a JSON string or a
    /// dictionary keyed by bundle identifier, each with an isAllowed flag.
    nonisolated static func disallowedBundleIdentifiers(in plist: [String: Any]) -> Set<String>? {
        guard let value = plist.first(where: {
            $0.key.caseInsensitiveCompare("TrackedApplications") == .orderedSame
        })?.value else {
            return nil
        }
        var decoded: Any? = value
        if let data = value as? Data {
            decoded = try? JSONSerialization.jsonObject(with: data)
        } else if let string = value as? String {
            decoded = try? JSONSerialization.jsonObject(with: Data(string.utf8))
        }
        var entries: [(String?, [String: Any])] = []
        if let dictionary = decoded as? [String: Any] {
            for (key, entry) in dictionary {
                if let entry = entry as? [String: Any] {
                    entries.append((key, entry))
                }
            }
        } else if let array = decoded as? [[String: Any]] {
            for entry in array {
                entries.append((nil, entry))
            }
        } else {
            return nil
        }
        var disallowed = Set<String>()
        for (key, entry) in entries {
            guard let isAllowed = entry["isAllowed"] as? Bool, !isAllowed else {
                continue
            }
            if let key {
                disallowed.insert(key)
            }
            if let rawBundleID = entry["rawBundleId"] as? String {
                disallowed.insert(rawBundleID)
            }
        }
        return disallowed
    }

    /// Whether macOS keeps the item's app off the menu bar. Thaw's own items
    /// and the system hosts are never on the list.
    static func isDisallowed(_ item: MenuBarItem, in disallowed: Set<String>) -> Bool {
        guard !disallowed.isEmpty, !item.isControlItem else {
            return false
        }
        switch item.tag.namespace {
        case .thaw, .menuBarAgent, .controlCenter, .systemUIServer:
            return false
        default:
            break
        }
        if disallowed.contains(item.tag.namespace.description) {
            return true
        }
        if let bundleID = item.sourceApplication?.bundleIdentifier {
            return disallowed.contains(bundleID)
        }
        return false
    }
}
