//
//  ScreenCapture+Permissions.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import CoreGraphics
import MenuBarModel
import ScreenCaptureKit

public extension ScreenCapture {
    // MARK: Permissions

    static func checkPermissions() -> Bool {
        // Status items have no windows or titles to probe; only preflight signals permission.
        // Keep permissionGranted as the tested decision point.
        let preflightResult = CGPreflightScreenCaptureAccess()
        let result = permissionGranted(
            windowTitles: [],
            preflightResult: preflightResult
        )
        diagLog.debug("checkPermissions: CGPreflightScreenCaptureAccess()=\(preflightResult) → \(result)")
        return result
    }

    /// An untitled window must not mask a later titled window proving access.
    internal static func permissionGranted(
        windowTitles: [String?],
        preflightResult: Bool
    ) -> Bool {
        preflightResult || windowTitles.contains { $0 != nil }
    }

    /// Cache the initial result; recomputeCachedScreenRecordingPermission refreshes it.
    static var hasCachedScreenRecordingPermission: Bool {
        if let result = cachedPermissionResult.withLock({ $0 }) {
            return result
        }
        return recomputeCachedScreenRecordingPermission()
    }

    @discardableResult
    static func recomputeCachedScreenRecordingPermission() -> Bool {
        let result = checkPermissions()
        diagLog.debug("recomputeCachedScreenRecordingPermission: computed fresh result = \(result) (wasCached=\(cachedPermissionResult.withLock { $0 != nil }))")
        cachedPermissionResult.withLock { $0 = result }
        return result
    }

    private static func setCachedPermissionResult(_ result: Bool?) {
        cachedPermissionResult.withLock { $0 = result }
    }

    /// ScreenCaptureKit can detect a System Settings grant without restarting the process.
    static func refreshPermissions() async -> Bool {
        let preflightResult = CGPreflightScreenCaptureAccess()
        if preflightResult {
            setCachedPermissionResult(true)
            return true
        }

        do {
            _ = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            setCachedPermissionResult(true)
            return true
        } catch {
            diagLog.debug("refreshPermissions: ScreenCaptureKit probe failed: \(error)")
            setCachedPermissionResult(false)
            return false
        }
    }

    static func restoreActivationPolicyAfterScreenCapturePrompt(
        currentPolicy: NSApplication.ActivationPolicy,
        setActivationPolicy: @escaping (NSApplication.ActivationPolicy) -> Bool,
        activate: () -> Void
    ) -> (() -> Void)? {
        guard currentPolicy != .regular else {
            activate()
            return nil
        }

        _ = setActivationPolicy(.regular)
        activate()

        return {
            _ = setActivationPolicy(currentPolicy)
        }
    }

    /// Complete exactly once with granted/prompted flags so declining does not open Settings; infer prompting by duration (macOS 15 can refuse instantly).
    /// On macOS 27 this registers the app; an extra SCShareableContent request would prompt again after Deny.
    @MainActor
    static func requestPermissions(
        completion: @escaping @MainActor @Sendable (Bool, Bool) -> Void = { _, _ in }
    ) {
        diagLog.debug("requestPermissions: requesting screen capture access")
        setCachedPermissionResult(nil)

        // Leave LSUIElement agent mode temporarily: prompts and Settings registration require a normal frontmost app.
        let restoreActivationPolicy = restoreActivationPolicyAfterScreenCapturePrompt(
            currentPolicy: NSApp.activationPolicy(),
            setActivationPolicy: { NSApp.setActivationPolicy($0) },
            activate: { NSApp.activate(ignoringOtherApps: true) }
        )

        let requestStarted = ContinuousClock.now
        let cgResult = CGRequestScreenCaptureAccess()
        let promptElapsed = ContinuousClock.now - requestStarted
        let prompted = cgResult || promptElapsed > promptShownThreshold
        setCachedPermissionResult(cgResult)
        diagLog.debug(
            "requestPermissions: CGRequestScreenCaptureAccess()=\(cgResult) after \(promptElapsed) → prompted=\(prompted)"
        )

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            restoreActivationPolicy?()
        }
        completion(cgResult, prompted)
    }

    /// Distinguish human prompt-response time from fast API refusal to prompt.
    static nonisolated let promptShownThreshold: Duration = .milliseconds(750)
}
