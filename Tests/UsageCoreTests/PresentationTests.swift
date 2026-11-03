import Foundation
import Testing
@testable import UsageCore

@Suite struct PresentationTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func window(_ pct: Double, resetsIn: TimeInterval = 3600) -> UsageWindow {
        UsageWindow(usedPercentage: pct, resetsAt: now.addingTimeInterval(resetsIn), observedAt: now)
    }

    @Test(arguments: [
        (0.0, UsageLevel.low), (49.9, .low), (50.0, .moderate), (74.9, .moderate),
        (75.0, .high), (89.9, .high), (90.0, .critical), (100.0, .critical),
    ])
    func levelThresholds(percent: Double, expected: UsageLevel) {
        #expect(usageLevel(percent) == expected)
    }

    @Test func headlineIsTheHighestCurrentWindow() {
        let state = UsageState(updatedAt: now, windows: ["five_hour": window(12), "seven_day": window(81)])
        #expect(headlinePercent(state, now: now) == 81)
    }

    @Test func headlineTreatsResetWindowsAsZero() {
        let state = UsageState(updatedAt: now, windows: ["five_hour": window(95, resetsIn: -60), "seven_day": window(20)])
        #expect(headlinePercent(state, now: now) == 20)
    }

    @Test func headlineIsNilWithoutData() {
        #expect(headlinePercent(nil, now: now) == nil)
        #expect(headlinePercent(UsageState(updatedAt: now, windows: [:]), now: now) == nil)
    }

    @Test func rowsListKnownWindowsFirstThenOthers() {
        let state = UsageState(updatedAt: now, windows: [
            "seven_day_opus": window(5), "seven_day": window(16), "five_hour": window(2),
        ])
        let rows = usageRows(state, now: now)
        #expect(rows.map(\.key) == ["five_hour", "seven_day", "seven_day_opus"])
        #expect(rows.map(\.title) == ["Session (5-hour)", "Weekly (7-day)", "Seven day opus"])
    }

    @Test func knownWindowsAlwaysAppearEvenWithoutData() {
        let rows = usageRows(nil, now: now)
        #expect(rows.map(\.key) == ["five_hour", "seven_day"])
        #expect(rows.allSatisfy { $0.percent == nil && $0.resetsAt == nil })
    }

    @Test func rowCarriesEffectivePercentAndResetFlag() {
        let state = UsageState(updatedAt: now, windows: ["five_hour": window(64, resetsIn: -1)])
        let row = usageRows(state, now: now).first { $0.key == "five_hour" }
        #expect(row?.percent == 0)
        #expect(row?.hasReset == true)
        #expect(row?.level == .low)
    }
}
