import Foundation
import Testing
@testable import Thaw

struct AXBridgeDiagnosticsTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func breadcrumbIsReadableBeforeLoggerIsClosed() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = UUID().uuidString
        let logger = AXBridgeDiagnostics(directory: directory, session: session, header: "test-build")
        logger.append("request=42 stage=before-bridge\nshape=array")
        let file = directory.appendingPathComponent("ax-bridge-\(session)-0.txt")
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("test-build"))
        #expect(text.contains("request=42 stage=before-bridge shape=array"))
        #expect(text.split(separator: "\n").count == 2)
    }

    @Test func rotationKeepsTwoBoundedFilesWithNewestBreadcrumb() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let logger = AXBridgeDiagnostics(directory: directory, maxBytes: 256, header: "test-build")
        for index in 0 ..< 30 {
            logger.append("request=\(index) " + String(repeating: "x", count: 400))
        }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        #expect(files.count == 2)
        var combined = ""
        for file in files {
            let data = try Data(contentsOf: file)
            #expect(data.count <= 256)
            let text = try #require(String(data: data, encoding: .utf8))
            #expect(text.contains("generation="))
            combined += text
        }
        #expect(combined.contains("request=29"))
        #expect(!combined.contains("request=0 "))
    }

    @Test func retentionPreservesTwoPreviousRunsAndUnrelatedFiles() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var oldSessions: [String] = []
        for index in 0 ..< 4 {
            let session = UUID().uuidString
            oldSessions.append(session)
            for slot in 0 ..< 2 {
                let file = directory.appendingPathComponent("ax-bridge-\(session)-\(slot).txt")
                try Data("previous-run".utf8).write(to: file)
                try FileManager.default.setAttributes(
                    [.modificationDate: Date(timeIntervalSince1970: Double(index))], ofItemAtPath: file.path
                )
            }
        }
        let unrelated = directory.appendingPathComponent("ax-bridge-user-notes-0.txt")
        try Data("keep".utf8).write(to: unrelated)
        let logger = AXBridgeDiagnostics(directory: directory, header: "new-run")
        logger.append("stage=before-bridge")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(names.count == 6)
        #expect(names.contains(unrelated.lastPathComponent))
        #expect(!names.contains(where: { $0.contains(oldSessions[0]) || $0.contains(oldSessions[1]) }))
        #expect(names.contains(where: { $0.contains(oldSessions[2]) }))
        #expect(names.contains(where: { $0.contains(oldSessions[3]) }))
    }

    @Test func concurrentWritersKeepEveryRecordWhole() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = UUID().uuidString
        let logger = AXBridgeDiagnostics(directory: directory, session: session, header: "test")
        DispatchQueue.concurrentPerform(iterations: 100) { index in
            logger.append("request=\(index) stage=before-bridge")
        }
        let text = try String(
            contentsOf: directory.appendingPathComponent("ax-bridge-\(session)-0.txt"), encoding: .utf8
        )
        #expect(text.split(separator: "\n").count == 101)
        for index in 0 ..< 100 {
            #expect(text.contains("request=\(index) stage=before-bridge\n"))
        }
    }
}
