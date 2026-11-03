import Foundation
import Testing
@testable import UsageCore

@Suite struct StoreTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func tempFile() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("usage-store-\(UUID().uuidString)")
        // Deliberately not created: the store must create its own directory.
        return dir.appendingPathComponent("usage.json")
    }

    @Test func roundTripsThroughDisk() throws {
        let url = try tempFile()
        let store = StateStore(url: url)
        #expect(store.load() == nil)

        let written = try store.update(with: ["five_hour": RateLimitReading(usedPercentage: 7, resetsAt: now.addingTimeInterval(3600))], now: now)
        #expect(written)
        #expect(store.load()?.windows["five_hour"]?.usedPercentage == 7)
    }

    @Test func unchangedStateIsNotRewritten() throws {
        let url = try tempFile()
        let store = StateStore(url: url)
        let r = ["five_hour": RateLimitReading(usedPercentage: 7, resetsAt: now.addingTimeInterval(3600))]
        #expect(try store.update(with: r, now: now))
        #expect(try store.update(with: [:], now: now) == false)
    }

    @Test func fileUsesSnakeCaseEpochSeconds() throws {
        let url = try tempFile()
        _ = try StateStore(url: url).update(with: ["seven_day": RateLimitReading(usedPercentage: 16, resetsAt: now.addingTimeInterval(60))], now: now)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let window = (json?["windows"] as? [String: Any])?["seven_day"] as? [String: Any]
        #expect(json?["updated_at"] as? Double == 1_800_000_000)
        #expect(window?["resets_at"] as? Double == 1_800_000_060)
        #expect(window?["used_percentage"] as? Double == 16)
    }

    @Test func corruptFileIsTreatedAsEmpty() throws {
        let url = try tempFile()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{garbage".utf8).write(to: url)
        let store = StateStore(url: url)
        #expect(store.load() == nil)
        #expect(try store.update(with: ["five_hour": RateLimitReading(usedPercentage: 1, resetsAt: now.addingTimeInterval(60))], now: now))
        #expect(store.load()?.windows["five_hour"]?.usedPercentage == 1)
    }
}
