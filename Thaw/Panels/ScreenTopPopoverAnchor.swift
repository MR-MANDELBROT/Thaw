//
//  ScreenTopPopoverAnchor.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// Hangs an NSPopover from the top edge of a screen.
///
/// NSPopover needs a view, so this parks a one-pixel click-through window at
/// the screen's top center for the popover to hang from like a menu.
///
/// Reused across shows; a fresh anchor each time flickers the popover's arrow.
@MainActor
final class ScreenTopPopoverAnchor {
    /// The screen a summoned surface hangs from when the caller names none.
    ///
    /// The pointer's screen wins over .main: the user expects the surface
    /// where they made the gesture.
    static var defaultScreen: NSScreen? {
        NSScreen.screenWithMouse ?? NSScreen.main
    }

    /// The invisible window the popover points at.
    private var window: NSWindow?

    /// Moves the anchor to the top of screen and returns the view a popover
    /// can be shown relative to.
    func view(for screen: NSScreen) -> NSView? {
        let window: NSWindow
        if let anchorWindow = self.window {
            window = anchorWindow
        } else {
            let newWindow = NSWindow(
                contentRect: .init(origin: .zero, size: .init(width: 1, height: 1)),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            newWindow.isReleasedWhenClosed = false
            newWindow.isOpaque = false
            newWindow.backgroundColor = .clear
            newWindow.level = .statusBar
            newWindow.ignoresMouseEvents = true
            newWindow.hasShadow = false
            newWindow.contentView = NSView(
                frame: .init(origin: .zero, size: .init(width: 1, height: 1))
            )
            self.window = newWindow
            window = newWindow
        }

        let frame = screen.visibleFrame
        let origin = CGPoint(x: frame.midX, y: frame.maxY - window.frame.height)
        window.setFrameOrigin(origin)
        window.orderFrontRegardless()

        return window.contentView
    }

    /// Takes the anchor off screen once the popover it held is gone.
    func hide() {
        window?.orderOut(nil)
    }
}
