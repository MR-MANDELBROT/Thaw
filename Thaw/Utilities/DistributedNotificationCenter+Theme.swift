//
//  DistributedNotificationCenter+Theme.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

extension DistributedNotificationCenter {
    /// Posted system-wide whenever the user switches between light and dark
    /// appearance.
    static let interfaceThemeChangedNotification = Notification.Name("AppleInterfaceThemeChangedNotification")
}
