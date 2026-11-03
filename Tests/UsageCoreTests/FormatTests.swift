import Foundation
import Testing
@testable import UsageCore

@Suite struct FormatTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test(arguments: [(2.0, "2%"), (23.5, "24%"), (0.4, "0%"), (100.0, "100%"), (130.0, "100%"), (-3.0, "0%")])
    func percent(value: Double, expected: String) {
        #expect(formatPercent(value) == expected)
    }

    static let countdowns: [(Double, String)] = [
        (30, "<1m"), (2_700, "45m"), (11_520, "3h 12m"),   // 45m, 3h12m
        (7_200, "2h 0m"), (163_800, "1d 21h"), (-5, "now"), // 2h, 45h30m
    ]

    @Test(arguments: countdowns)
    func countdown(seconds: Double, expected: String) {
        #expect(formatCountdown(from: now, to: now.addingTimeInterval(seconds)) == expected)
    }

    @Test func expiredWindowCountsAsZero() {
        let w = UsageWindow(usedPercentage: 80, resetsAt: now.addingTimeInterval(-1), observedAt: now.addingTimeInterval(-3600))
        #expect(w.effectivePercentage(at: now) == 0)
        #expect(w.hasReset(at: now))
    }

    @Test func titleShowsBothWindows() {
        let state = UsageState(updatedAt: now, windows: [
            "five_hour": UsageWindow(usedPercentage: 2, resetsAt: now.addingTimeInterval(3600), observedAt: now),
            "seven_day": UsageWindow(usedPercentage: 16.4, resetsAt: now.addingTimeInterval(86400), observedAt: now),
        ])
        #expect(menuBarTitle(state, now: now) == "5h 2% · 7d 16%")
    }

    @Test func titleWithoutDataUsesDashes() {
        #expect(menuBarTitle(nil, now: now) == "5h – · 7d –")
        let partial = UsageState(updatedAt: now, windows: [
            "seven_day": UsageWindow(usedPercentage: 16, resetsAt: now.addingTimeInterval(86400), observedAt: now),
        ])
        #expect(menuBarTitle(partial, now: now) == "5h – · 7d 16%")
    }
}
