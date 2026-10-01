//
//  PickedFileAccess.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import PlatformRuntimeKit
import UniformTypeIdentifiers

/// Access to one protected file the user picks in an open panel, kept across
/// launches as a bookmark.
///
/// Group containers of other apps refuse every read until the user selects the
/// file themselves; the panel runs in the system's process and hands the
/// selection back with the access. MenuBarLayoutTableAccess does the same
/// for the menu bar's layout table.
@MainActor
final class PickedFileAccess {
    /// Control Center's list of apps allowed in the menu bar, which native app
    /// hiding switches apps off in.
    static let controlCenterAppList = PickedFileAccess(
        fileURL: URL(fileURLWithPath: CFPreferencesTrackedApplications.defaultDomain + ".plist"),
        bookmarkKey: "NativeAppHidingAppListBookmark",
        title: String(localized: "Grant Access to Control Center's App List"),
        message: String(localized: "Select “group.com.apple.controlcenter.plist” to let \(Constants.displayName) hide apps the way System Settings does. \(Constants.displayName) is granted access to this one file only.")
    )

    private let fileURL: URL
    private let bookmarkKey: String
    private let title: String
    private let message: String
    private var scopedURL: URL?
    private let diagLog = DiagLog(category: "PickedFileAccess")

    init(fileURL: URL, bookmarkKey: String, title: String, message: String) {
        self.fileURL = fileURL
        self.bookmarkKey = bookmarkKey
        self.title = title
        self.message = message
    }

    /// Whether the file can be read now.
    var hasAccess: Bool {
        activateIfNeeded()
        return FileManager.default.isReadableFile(atPath: fileURL.path)
            && NSDictionary(contentsOf: fileURL) != nil
    }

    /// Resolves the stored bookmark and takes its scope, once.
    func activateIfNeeded() {
        guard scopedURL == nil, let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            return
        }
        if url.startAccessingSecurityScopedResource() {
            scopedURL = url
        }
        if isStale {
            store(url)
        }
    }

    /// Shows the panel on the file's folder. Returns whether the user picked
    /// that file.
    func requestAccessViaOpenPanel() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.propertyList]
        panel.directoryURL = fileURL.deletingLastPathComponent()
        panel.title = title
        panel.message = message
        panel.prompt = String(localized: "Grant Access")
        NSApp.activate()
        guard panel.runModal() == .OK, let picked = panel.url,
              picked.standardizedFileURL.path == fileURL.standardizedFileURL.path
        else {
            diagLog.info("No access to \(fileURL.lastPathComponent): the panel closed without that file")
            return false
        }
        store(picked)
        scopedURL = nil
        activateIfNeeded()
        diagLog.info("Access granted to \(fileURL.lastPathComponent)")
        return true
    }

    private func store(_ url: URL) {
        let data = (try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil))
            ?? (try? url.bookmarkData(includingResourceValuesForKeys: nil, relativeTo: nil))
        if let data {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        }
    }
}
