//
//  AXPrimitivesTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import ThawAXCore

struct AXPrimitivesTests {
    @Test
    func `frame is within uses the midpoint`() {
        let display = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(AXPrimitives.frame(CGRect(x: 90, y: 90, width: 20, height: 20), isWithin: display))
        #expect(!AXPrimitives.frame(CGRect(x: 95, y: 95, width: 20, height: 20), isWithin: display))
    }

    @Test
    func `a parked frame belongs to no display`() {
        let display = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(AXPrimitives.frame(CGRect(x: -1, y: 500, width: 20, height: 20), isWithin: display))
    }

    @Test
    func `press treats success as opened`() {
        var askedOwner = false
        let opened = AXPrimitives.press(perform: { .success }, ownerPID: {
            askedOwner = true
            return nil
        })
        #expect(opened)
        #expect(!askedOwner)
    }

    @Test
    func `press treats a plain failure as not opened`() {
        #expect(!AXPrimitives.press(perform: { .failure }, ownerPID: { nil }))
    }

    @Test
    func `press cannot complete without an owner is not opened`() {
        #expect(!AXPrimitives.press(perform: { .cannotComplete }, ownerPID: { nil }))
    }

    @Test
    func `press cannot complete without an open menu is not opened`() {
        // The test process has no window on the popup menu layer, so a
        // cannotComplete that no open menu explains is a failure.
        #expect(!AXPrimitives.press(perform: { .cannotComplete }, ownerPID: { getpid() }))
    }

    @Test
    func `no process is tracking an open menu at a bogus pid`() {
        #expect(!AXPrimitives.isTrackingOpenMenu(pid: -1))
    }
}
