//
//  Publisher+Defaults.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation

extension Publisher where Output: Equatable, Failure == Never {
    /// Binds publisher to UserDefaults, persisting each unique value.
    ///
    /// - Parameters:
    ///   - key: The Defaults key to persist to.
    ///   - cancellables: The set to store the subscription in.
    func persistToDefaults(
        key: Defaults.Key,
        in cancellables: inout Set<AnyCancellable>
    ) {
        self.removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { Defaults.set($0, forKey: key) }
            .store(in: &cancellables)
    }

    /// Binds publisher to UserDefaults with transform (e.g., for RawRepresentable enums).
    ///
    /// - Parameters:
    ///   - key: The Defaults key to persist to.
    ///   - transform: A closure that transforms the output before persisting.
    ///   - cancellables: The set to store the subscription in.
    func persistToDefaults(
        key: Defaults.Key,
        transform: @escaping (Output) -> some Any,
        in cancellables: inout Set<AnyCancellable>
    ) {
        self.removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { Defaults.set(transform($0), forKey: key) }
            .store(in: &cancellables)
    }

    /// Binds publisher to UserDefaults with an additional side effect.
    ///
    /// - Parameters:
    ///   - key: The Defaults key to persist to.
    ///   - sideEffect: A closure to execute after persisting.
    ///   - cancellables: The set to store the subscription in.
    func persistToDefaults(
        key: Defaults.Key,
        sideEffect: @escaping (Output) -> Void,
        in cancellables: inout Set<AnyCancellable>
    ) {
        self.removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { value in
                Defaults.set(value, forKey: key)
                sideEffect(value)
            }
            .store(in: &cancellables)
    }
}
