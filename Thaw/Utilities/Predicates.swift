//
//  Predicates.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

enum Predicates<Input> {
    typealias ThrowingPredicate = (Input) throws -> Bool

    typealias NonThrowingPredicate = (Input) -> Bool

    static func predicate(_ body: @escaping (Input) throws -> Bool) -> ThrowingPredicate {
        return body
    }

    static func predicate(_ body: @escaping (Input) -> Bool) -> NonThrowingPredicate {
        return body
    }

    static func predicate(_ body: @escaping () throws -> Bool) -> ThrowingPredicate {
        predicate { _ in try body() }
    }

    static func predicate(_ body: @escaping () -> Bool) -> NonThrowingPredicate {
        predicate { _ in body() }
    }
}

// MARK: - Control Item Predicates

extension Predicates where Input == NSLayoutConstraint {
    @MainActor
    static func controlItemConstraint(button: NSStatusBarButton) -> NonThrowingPredicate {
        let target = button.superview
        return predicate { constraint in
            constraint.secondItem === target
        }
    }
}
