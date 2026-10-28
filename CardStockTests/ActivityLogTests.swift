import Foundation
import Testing
@testable import CardStock

@MainActor
struct ActivityLogTests {
    let file = FileManager.default.temporaryDirectory.appending(path: "cardstock-log-\(UUID().uuidString)/activity-log.jsonl")

    @Test func savesAndReloads() throws {
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let log = ActivityLog(fileURL: file)
        log.add(LogEntry(kind: .edit, site: "A", sitePath: "/a", message: "Edited “Home”"))
        log.add(LogEntry(kind: .hosting, site: "A", sitePath: "/a", message: "Workers Builds: build failed",
                         link: "https://dash.cloudflare.com/x", key: "build:1", failed: true))
        // The same build is only logged once.
        log.add(LogEntry(kind: .hosting, message: "again", key: "build:1"))
        log.add(LogEntry(kind: .app, message: "Signed in"))
        #expect(log.entries.count == 3)
        #expect(log.entries[1].isProblem)

        let reloaded = ActivityLog(fileURL: file)
        #expect(reloaded.entries.map(\.message) == log.entries.map(\.message))
        #expect(reloaded.contains(key: "build:1"))

        reloaded.clear(sitePath: "/a")
        #expect(reloaded.entries.map(\.message) == ["Signed in"])
        #expect(ActivityLog(fileURL: file).entries.count == 1)
        reloaded.clear()
        #expect(ActivityLog(fileURL: file).entries.isEmpty)
    }

    @Test func keepsTheNewest() {
        let log = ActivityLog(fileURL: nil)
        for i in 0..<(ActivityLog.limit + 501) { log.add(LogEntry(kind: .edit, message: "\(i)")) }
        #expect(log.entries.count == ActivityLog.limit)
        #expect(log.entries.last?.message == "\(ActivityLog.limit + 500)")
    }

    @Test func exportsText() {
        let entry = LogEntry(kind: .error, site: "My Site", message: "Couldn't save", detail: "Disk full\nTry again",
                             link: "https://example.com")
        let text = ActivityLog.exportText([entry])
        #expect(text.contains("Error       [My Site]  Couldn't save"))
        #expect(text.contains("\n    Disk full\n    Try again\n    https://example.com"))
    }

    @Test func modelLogsWhatHappens() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "cardstock-logsite-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = AppModel()
        model.createSite(at: dir.appending(path: "Field Notes"))
        model.newItem(.page, title: "Contact")
        model.errorMessage = "Something broke"
        let messages = model.activityLog.entries.map(\.message)
        #expect(messages.contains("Opened the site"))
        #expect(messages.contains("Made a new static page: “Contact”"))
        #expect(model.activityLog.entries.last?.kind == .error)
        #expect(model.activityLog.entries.allSatisfy { $0.sitePath == dir.appending(path: "Field Notes").path })
    }
}
