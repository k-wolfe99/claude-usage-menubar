import Foundation
import Testing
@testable import UsageCore

/// Several Claude Code sessions write the same state file, and an idle session can re-run
/// its status line with numbers from hours ago. These rules keep stale data from winning.
@Suite struct MergeTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func t(_ offset: TimeInterval) -> Date { now.addingTimeInterval(offset) }
    func reading(_ pct: Double, resetsIn: TimeInterval) -> RateLimitReading {
        RateLimitReading(usedPercentage: pct, resetsAt: t(resetsIn))
    }

    @Test func firstReadingCreatesState() {
        let state = merge(nil, readings: ["five_hour": reading(10, resetsIn: 3600)], now: now)
        #expect(state?.windows["five_hour"] == UsageWindow(usedPercentage: 10, resetsAt: t(3600), observedAt: now))
        #expect(state?.updatedAt == now)
    }

    @Test func noReadingsLeavesStateUntouched() {
        let existing = merge(nil, readings: ["five_hour": reading(10, resetsIn: 3600)], now: t(-60))
        #expect(merge(existing, readings: [:], now: now) == existing)
        #expect(merge(nil, readings: [:], now: now) == nil)
    }

    @Test func sameWindowTakesTheHigherPercentage() {
        let s1 = merge(nil, readings: ["five_hour": reading(30, resetsIn: 3600)], now: t(-60))
        // A stale session reports 12% for the same window: ignored.
        let s2 = merge(s1, readings: ["five_hour": reading(12, resetsIn: 3600)], now: now)
        #expect(s2?.windows["five_hour"]?.usedPercentage == 30)
        // A fresh session reports 41%: taken.
        let s3 = merge(s2, readings: ["five_hour": reading(41, resetsIn: 3600)], now: now)
        #expect(s3?.windows["five_hour"]?.usedPercentage == 41)
        #expect(s3?.windows["five_hour"]?.observedAt == now)
    }

    @Test func smallResetTimeJitterCountsAsTheSameWindow() {
        let s1 = merge(nil, readings: ["five_hour": reading(30, resetsIn: 3600)], now: t(-60))
        let s2 = merge(s1, readings: ["five_hour": reading(20, resetsIn: 3600 - 120)], now: now)
        #expect(s2?.windows["five_hour"]?.usedPercentage == 30)
    }

    @Test func laterWindowReplacesEvenWithLowerPercentage() {
        // Old window was at 90%, a new 5-hour window started and is at 3%.
        let s1 = merge(nil, readings: ["five_hour": reading(90, resetsIn: 600)], now: t(-60))
        let s2 = merge(s1, readings: ["five_hour": reading(3, resetsIn: 600 + 5 * 3600)], now: now)
        #expect(s2?.windows["five_hour"]?.usedPercentage == 3)
        #expect(s2?.windows["five_hour"]?.resetsAt == t(600 + 5 * 3600))
    }

    @Test func readingFromAnOlderWindowIsIgnored() {
        let s1 = merge(nil, readings: ["five_hour": reading(3, resetsIn: 5 * 3600)], now: t(-60))
        let s2 = merge(s1, readings: ["five_hour": reading(90, resetsIn: 600)], now: now)
        #expect(s2 == s1)
    }

    @Test func alreadyExpiredReadingIsIgnored() {
        let s1 = merge(nil, readings: ["seven_day": reading(16, resetsIn: 86400)], now: t(-60))
        let s2 = merge(s1, readings: ["five_hour": reading(50, resetsIn: -10)], now: now)
        #expect(s2 == s1)
    }

    @Test func expiredStoredWindowIsReplacedByAnyCurrentReading() {
        let s1 = merge(nil, readings: ["five_hour": reading(80, resetsIn: 60)], now: now)
        let later = t(3600)
        let s2 = merge(s1, readings: ["five_hour": RateLimitReading(usedPercentage: 1, resetsAt: later.addingTimeInterval(1800))], now: later)
        #expect(s2?.windows["five_hour"]?.usedPercentage == 1)
    }

    @Test func absentWindowsAreKept() {
        let s1 = merge(nil, readings: ["five_hour": reading(10, resetsIn: 3600), "seven_day": reading(16, resetsIn: 86400)], now: t(-60))
        let s2 = merge(s1, readings: ["five_hour": reading(12, resetsIn: 3600)], now: now)
        #expect(s2?.windows["seven_day"]?.usedPercentage == 16)
        #expect(s2?.windows["five_hour"]?.usedPercentage == 12)
    }
}
