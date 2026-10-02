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
        let filePlist = access.readDictionary()
        let fromFile = filePlist.flatMap(Self.disallowedBundleIdentifiers(in:))
        let preferencesPlist = fromFile == nil ? Self.readPreferences() : nil
        let fromPreferences = preferencesPlist.flatMap(Self.disallowedBundleIdentifiers(in:))
        guard let disallowed = fromFile ?? fromPreferences else {
            cachedDisallowed = []
            if !loggedFailure {
                loggedFailure = true
                diagLog.warning(
                    """
                    Control Center's app list has no isAllowed entries Thaw can read; filtering nothing. \
                    \(access.accessDiagnostics()) file: \(Self.shapeDescription(of: filePlist)) \
                    preferences: \(Self.shapeDescription(of: preferencesPlist))
                    """
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

    /// Collects every entry with an isAllowed flag, wherever the list keeps
    /// it: keyed by bundle identifier or carrying one, nested, or encoded as
    /// JSON or property list data or text. Nil when no entry has the flag.
    nonisolated static func disallowedBundleIdentifiers(in plist: [String: Any]) -> Set<String>? {
        var sawEntry = false
        var disallowed = Set<String>()
        func visit(_ value: Any, key: String?, depth: Int) {
            guard depth < 8 else {
                return
            }
            let decoded = decodedContainer(value)
            if let entry = decoded as? [String: Any], let isAllowed = entry["isAllowed"] as? Bool {
                sawEntry = true
                guard !isAllowed else {
                    return
                }
                if let key {
                    disallowed.insert(key)
                }
                for idKey in ["rawBundleId", "bundleIdentifier", "bundleID", "bundleId"] {
                    if let bundleID = entry[idKey] as? String {
                        disallowed.insert(bundleID)
                    }
                }
            } else if let dictionary = decoded as? [String: Any] {
                for (childKey, child) in dictionary {
                    visit(child, key: childKey, depth: depth + 1)
                }
            } else if let array = decoded as? [Any] {
                for child in array {
                    visit(child, key: nil, depth: depth + 1)
                }
            }
        }
        visit(plist, key: nil, depth: 0)
        return sawEntry ? disallowed : nil
    }

    /// Data or text holding JSON or a property list, decoded; anything else
    /// as it is.
    private nonisolated static func decodedContainer(_ value: Any) -> Any {
        let data: Data
        if let value = value as? Data {
            data = value
        } else if let value = value as? String, let first = value.first, first == "{" || first == "[" {
            data = Data(value.utf8)
        } else {
            return value
        }
        if let object = try? JSONSerialization.jsonObject(with: data) {
            return object
        }
        if let object = try? PropertyListSerialization.propertyList(from: data, format: nil) {
            return object
        }
        return value
    }

    /// Top-level keys and value types, for the log when no entry is found.
    private static func shapeDescription(of plist: [String: Any]?) -> String {
        guard let plist else {
            return "unreadable"
        }
        let keys = plist.keys.sorted().map { key -> String in
            let value = plist[key]
            if let data = value as? Data {
                let prefix = String(decoding: data.prefix(12), as: UTF8.self)
                    .filter { $0.isASCII && !$0.isNewline }
                return "\(key)=Data(\(data.count) B, \"\(prefix)\")"
            }
            return "\(key)=\(value.map { String(describing: type(of: $0)) } ?? "nil")"
        }
        return "{" + keys.joined(separator: ", ") + "}"
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
