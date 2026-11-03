import Foundation
import Testing
@testable import UsageCore

@Suite struct OAuthUsageParseTests {
    func fixture() throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/oauth-usage.sample.json")
        return try Data(contentsOf: url)
    }

    @Test func readsWindowsFromRealResponse() throws {
        let readings = parseOAuthUsage(try fixture())
        #expect(readings["five_hour"]?.usedPercentage == 7)
        #expect(readings["seven_day"]?.usedPercentage == 17)
        // 2026-11-03T11:40:00.449944Z, microseconds kept to the millisecond.
        let resets = try #require(readings["five_hour"]?.resetsAt.timeIntervalSince1970)
        #expect(abs(resets - 1_793_706_000.449944) < 0.001)
    }

    @Test func skipsNullWindowsAndNonWindowObjects() throws {
        let readings = parseOAuthUsage(try fixture())
        #expect(Set(readings.keys) == ["five_hour", "seven_day"])
    }

    @Test func acceptsZuluTimestampsWithoutFraction() {
        let json = #"{"seven_day_opus":{"utilization":42,"resets_at":"2026-11-05T05:00:00Z"}}"#
        let reading = parseOAuthUsage(Data(json.utf8))["seven_day_opus"]
        #expect(reading?.usedPercentage == 42)
        #expect(reading?.resetsAt == Date(timeIntervalSince1970: 1_793_854_800))
    }

    @Test func garbageYieldsNothing() {
        #expect(parseOAuthUsage(Data("<html>".utf8)).isEmpty)
    }
}

@Suite struct CredentialTests {
    @Test func defaultServiceWithoutConfigDir() {
        #expect(credentialService(configDir: nil) == "Claude Code-credentials")
        #expect(credentialService(configDir: "") == "Claude Code-credentials")
    }

    @Test func configDirAddsHashSuffix() {
        // printf %s "/Users/me/.claude-work" | shasum -a 256 | cut -c1-8
        #expect(credentialService(configDir: "/Users/me/.claude-work") == "Claude Code-credentials-1e91dd84")
    }

    @Test(arguments: [
        ("Claude Code-credentials", true), ("Claude Code-credentials-1e91dd84", true),
        ("Claude Code-credentials-1E91DD84", false), ("Claude Code-credentials-1e91dd8", false),
        ("Claude Code", false), ("login.keychain", false), ("Claude Code-credentials-1e91dd84x", false),
    ])
    func onlyClaudeCodeCredentialItemsAreAccepted(name: String, valid: Bool) {
        #expect(isValidCredentialService(name) == valid)
    }

    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func extractsAccessTokenFromKeychainJSON() {
        let json = #"{"claudeAiOauth":{"accessToken":"tok","refreshToken":"r","expiresAt":1800003600000}}"#
        #expect(accessToken(fromKeychainData: Data(json.utf8), now: now) == .valid("tok"))
    }

    @Test func expiredTokenIsReportedNotUsed() {
        let json = #"{"claudeAiOauth":{"accessToken":"tok","expiresAt":1799999999000}}"#
        #expect(accessToken(fromKeychainData: Data(json.utf8), now: now) == .expired)
    }

    @Test func missingTokenIsReported() {
        #expect(accessToken(fromKeychainData: Data(#"{"other":{}}"#.utf8), now: now) == .missing)
        #expect(accessToken(fromKeychainData: Data("nope".utf8), now: now) == .missing)
    }
}

@Suite struct CredentialRecordingTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func tempStore() -> StateStore {
        StateStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("usage-store-\(UUID().uuidString)/usage.json"))
    }

    @Test func exporterRecordsWhichLoginToUse() throws {
        let store = tempStore()
        let r = ["five_hour": RateLimitReading(usedPercentage: 1, resetsAt: now.addingTimeInterval(60))]
        #expect(try store.update(with: r, credentialService: "Claude Code-credentials-1e91dd84", now: now))
        #expect(store.load()?.credentialService == "Claude Code-credentials-1e91dd84")
        // Same readings, same service: nothing to rewrite.
        #expect(try store.update(with: r, credentialService: "Claude Code-credentials-1e91dd84", now: now) == false)
    }

    @Test func invalidServiceNamesAreNeverStored() throws {
        let store = tempStore()
        let r = ["five_hour": RateLimitReading(usedPercentage: 1, resetsAt: now.addingTimeInterval(60))]
        _ = try store.update(with: r, credentialService: "login.keychain", now: now)
        #expect(store.load()?.credentialService == nil)
    }

    @Test func olderStateFilesWithoutTheFieldStillLoad() throws {
        let store = tempStore()
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"updated_at":1800000000,"windows":{}}"#.utf8).write(to: store.url)
        #expect(store.load()?.credentialService == nil)
        #expect(store.load()?.updatedAt == now)
    }
}
