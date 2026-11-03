import Foundation
import Testing
@testable import UsageCore

@Suite struct ParseTests {
    @Test func readsBothWindowsFromRealSample() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/statusline-input.sample.json")
        let readings = parseRateLimits(try Data(contentsOf: fixture))

        #expect(readings["five_hour"] == RateLimitReading(usedPercentage: 2, resetsAt: Date(timeIntervalSince1970: 1793706000)))
        #expect(readings["seven_day"] == RateLimitReading(usedPercentage: 16, resetsAt: Date(timeIntervalSince1970: 1793854800)))
    }

    @Test func noRateLimitsMeansNoReadings() {
        // API-key billed configurations never receive rate_limits.
        let json = #"{"model":{"id":"x"},"cost":{"total_cost_usd":1}}"#
        #expect(parseRateLimits(Data(json.utf8)).isEmpty)
    }

    @Test func fractionalPercentagesAreKept() {
        let json = #"{"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1738425600}}}"#
        #expect(parseRateLimits(Data(json.utf8))["five_hour"]?.usedPercentage == 23.5)
    }

    @Test func malformedWindowsAreSkipped() {
        let json = #"{"rate_limits":{"five_hour":{"used_percentage":"lots"},"seven_day":{"used_percentage":5,"resets_at":1738425600}}}"#
        let readings = parseRateLimits(Data(json.utf8))
        #expect(readings["five_hour"] == nil)
        #expect(readings["seven_day"]?.usedPercentage == 5)
    }

    @Test func invalidJSONYieldsNothing() {
        #expect(parseRateLimits(Data("not json".utf8)).isEmpty)
    }
}
