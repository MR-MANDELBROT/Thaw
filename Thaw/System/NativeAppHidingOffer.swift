//
//  NativeAppHidingOffer.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// Offer native app hiding once; it is off by default during beta.
@MainActor
enum NativeAppHidingOffer {
    static func presentIfNeeded(settings: AdvancedSettings, hints: FirstRunHintStore = .shared) {
        guard hints.isPending(.nativeAppHidingOffer) else { return }
        hints.dismiss(.nativeAppHidingOffer)
        guard !settings.enableNativeAppHiding else { return }

        let alert = NSAlert()
        alert.messageText = String(localized: "Try the new way to hide apps")
        alert.informativeText = String(
            localized: """
            \(Constants.displayName) can keep Live Activities and the camera indicator on the menu bar \
            while apps are hidden, and stop hidden items from flashing when Notification Center opens. \
            It's still in beta because it has had limited testing, but it's promising. You can change \
            this any time in Settings > General.
            """
        )
        alert.addButton(withTitle: String(localized: "Turn It On"))
        alert.addButton(withTitle: String(localized: "Not Now"))

        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            settings.enableNativeAppHiding = true
        }
    }
}
