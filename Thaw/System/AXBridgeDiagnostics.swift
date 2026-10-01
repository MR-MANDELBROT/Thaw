//
//  AXBridgeDiagnostics.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import OSLog

/// Writes before the Objective-C bridge so an abort cannot discard a queued breadcrumb.
final nonisolated class AXBridgeDiagnostics: @unchecked Sendable {
    private static let shared = AXBridgeDiagnostics()
    private static let logger = Logger(subsystem: "com.stonerl.Thaw", category: "AXBridgeDiagnostics")

    static func record(_ message: String) {
        shared.append(message)
    }

    private let lock = NSLock()
    private let directory: URL
    private let session: String
    private let maxBytes: Int
    private let header: String
    private var handle: FileHandle?
    private var bytesWritten = 0
    private var generation = 0
    private var initialized = false
    private var reportedFailure = false

    init(
        directory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Thaw", isDirectory: true),
        maxBytes: Int = 512 * 1024,
        session: String = UUID().uuidString,
        header: String? = nil
    ) {
        precondition(maxBytes >= 128)
        precondition(UUID(uuidString: session) != nil)
        self.directory = directory
        self.maxBytes = maxBytes
        self.session = session
        self.header = header ?? Self.runMetadata
    }

    deinit {
        try? handle?.close()
    }

    func append(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        guard !reportedFailure else { return }
        do {
            if !initialized {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try prunePreviousSessions()
                try openGeneration()
                initialized = true
            }
            let line = Self.line(message, limit: maxBytes / 2)
            if bytesWritten + line.count > maxBytes {
                generation += 1
                try openGeneration()
            }
            // FileHandle writes synchronously to the OS; no DispatchQueue or userspace buffer.
            try handle?.write(contentsOf: line)
            bytesWritten += line.count
        } catch {
            if !reportedFailure {
                reportedFailure = true
                Self.logger.error("AX bridge breadcrumb file write failed; subsequent failures suppressed")
            }
        }
    }

    private func openGeneration() throws {
        try handle?.close()
        handle = nil
        // DiagnosticLogger owns and prunes .log files; breadcrumbs use .txt independently.
        let url = directory.appendingPathComponent("ax-bridge-\(session)-\(generation % 2).txt")
        if !FileManager.default.fileExists(atPath: url.path) {
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let opened = try FileHandle(forWritingTo: url)
        handle = opened
        try opened.truncate(atOffset: 0)
        let data = Self.line("generation=\(generation) \(header)", limit: maxBytes / 4)
        try opened.write(contentsOf: data)
        bytesWritten = data.count
    }

    private func prunePreviousSessions() throws {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        )
        var sessions: [String: [(URL, Date)]] = [:]
        for url in urls {
            let name = url.lastPathComponent
            guard name.hasPrefix("ax-bridge-"),
                  name.hasSuffix("-0.txt") || name.hasSuffix("-1.txt") else { continue }
            let id = String(name.dropFirst("ax-bridge-".count).dropLast("-0.txt".count))
            guard UUID(uuidString: id) != nil, id != session else { continue }
            let date = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            sessions[id, default: []].append((url, date))
        }
        let ordered = sessions.values.sorted {
            ($0.map(\.1).max() ?? .distantPast) > ($1.map(\.1).max() ?? .distantPast)
        }
        for files in ordered.dropFirst(2) {
            for (url, _) in files {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func line(_ text: String, limit: Int) -> Data {
        let sanitized = text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        let prefix = "t=\(Date().timeIntervalSince1970) "
        var data = Data((prefix + sanitized).utf8.prefix(limit - 1))
        // A truncation may split a UTF-8 code point; metadata is normally ASCII.
        while String(data: data, encoding: .utf8) == nil, !data.isEmpty {
            data.removeLast()
        }
        data.append(10)
        return data
    }

    private static var runMetadata: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info["CFBundleVersion"] as? String ?? "unknown"
        let sha = info["GitCommitSHA"] as? String ?? "unknown"
        let process = ProcessInfo.processInfo
        return "version=\(version) build=\(build) sha=\(sha) os=\(process.operatingSystemVersionString) pid=\(process.processIdentifier)"
    }
}
