import Foundation

// MARK: - Model

/// One rate-limit window as Claude Code reported it in a single status line update.
public struct RateLimitReading: Equatable, Sendable {
    public var usedPercentage: Double
    public var resetsAt: Date

    public init(usedPercentage: Double, resetsAt: Date) {
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
    }
}

/// A window as stored in the state file.
public struct UsageWindow: Codable, Equatable, Sendable {
    public var usedPercentage: Double
    public var resetsAt: Date
    /// When a status line update last reported (or confirmed) this value.
    public var observedAt: Date

    public init(usedPercentage: Double, resetsAt: Date, observedAt: Date) {
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
        self.observedAt = observedAt
    }

    public func hasReset(at now: Date) -> Bool { resetsAt <= now }

    /// After the window resets, usage starts again from zero.
    public func effectivePercentage(at now: Date) -> Double { hasReset(at: now) ? 0 : usedPercentage }

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
        case observedAt = "observed_at"
    }
}

/// Contents of the state file shared by the exporter (writer) and the menu bar app (reader).
public struct UsageState: Codable, Equatable, Sendable {
    public var updatedAt: Date
    /// Keyed by Claude Code's window name: "five_hour", "seven_day", ...
    public var windows: [String: UsageWindow]

    public init(updatedAt: Date, windows: [String: UsageWindow]) {
        self.updatedAt = updatedAt
        self.windows = windows
    }

    enum CodingKeys: String, CodingKey {
        case updatedAt = "updated_at"
        case windows
    }
}

// MARK: - Parsing Claude Code's status line input

/// Extracts `rate_limits` windows from the JSON Claude Code passes to a status line command.
/// Returns an empty dictionary when there are none (API-key billing, or before the first response).
public func parseRateLimits(_ data: Data) -> [String: RateLimitReading] {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let limits = root["rate_limits"] as? [String: Any] else { return [:] }

    var readings: [String: RateLimitReading] = [:]
    for (name, value) in limits {
        guard let window = value as? [String: Any],
              let used = window["used_percentage"] as? NSNumber, !(used is Bool),
              let resets = window["resets_at"] as? NSNumber else { continue }
        readings[name] = RateLimitReading(
            usedPercentage: used.doubleValue,
            resetsAt: Date(timeIntervalSince1970: resets.doubleValue)
        )
    }
    return readings
}

// MARK: - Merging

/// Two readings whose reset times are this close belong to the same window. Consecutive
/// windows are at least five hours apart, so an hour leaves room for jitter without ambiguity.
let sameWindowTolerance: TimeInterval = 3600

/// Folds new readings into the stored state so that stale reports from idle sessions never win:
/// - a reading that has already reset is ignored;
/// - within the same window, usage only goes up, so the higher percentage is kept;
/// - a later window replaces an earlier one, and a reading from an earlier window is ignored;
/// - windows missing from this update are kept as they were.
/// Returns `state` unchanged when nothing new was learned.
public func merge(_ state: UsageState?, readings: [String: RateLimitReading], now: Date) -> UsageState? {
    var windows = state?.windows ?? [:]
    var changed = false

    for (name, reading) in readings {
        guard reading.resetsAt > now else { continue }
        let incoming = UsageWindow(usedPercentage: reading.usedPercentage, resetsAt: reading.resetsAt, observedAt: now)

        guard let stored = windows[name], !stored.hasReset(at: now) else {
            windows[name] = incoming
            changed = true
            continue
        }

        let sameWindow = abs(reading.resetsAt.timeIntervalSince(stored.resetsAt)) < sameWindowTolerance
        if sameWindow ? reading.usedPercentage >= stored.usedPercentage : reading.resetsAt > stored.resetsAt {
            windows[name] = incoming
            changed = true
        }
    }

    guard changed else { return state }
    return UsageState(updatedAt: now, windows: windows)
}

// MARK: - Formatting

public func formatPercent(_ value: Double) -> String {
    let clamped = min(max(value, 0), 100)
    return "\(Int(clamped.rounded()))%"
}

/// Compact time remaining: "<1m", "45m", "3h 12m", "1d 21h", or "now" once passed.
public func formatCountdown(from now: Date, to target: Date) -> String {
    let seconds = target.timeIntervalSince(now)
    if seconds <= 0 { return "now" }
    if seconds < 60 { return "<1m" }
    let minutes = Int(seconds / 60)
    if minutes < 60 { return "\(minutes)m" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h \(minutes % 60)m" }
    return "\(hours / 24)d \(hours % 24)h"
}

/// The two windows the menu bar shows, in order, with their short labels.
public let displayedWindows: [(key: String, short: String, long: String)] = [
    ("five_hour", "5h", "Session (5-hour)"),
    ("seven_day", "7d", "Weekly (7-day)"),
]

public func menuBarTitle(_ state: UsageState?, now: Date) -> String {
    displayedWindows.map { w in
        let value = state?.windows[w.key].map { formatPercent($0.effectivePercentage(at: now)) } ?? "–"
        return "\(w.short) \(value)"
    }.joined(separator: " · ")
}

// MARK: - Presentation

/// Colour band for a usage percentage: green, yellow, orange, red.
public enum UsageLevel: Int, Sendable, Comparable {
    case low, moderate, high, critical

    public static func < (a: UsageLevel, b: UsageLevel) -> Bool { a.rawValue < b.rawValue }
}

public func usageLevel(_ percent: Double) -> UsageLevel {
    switch percent {
    case ..<50: return .low
    case ..<75: return .moderate
    case ..<90: return .high
    default: return .critical
    }
}

/// The percentage the menu bar shows: the highest current window, i.e. the limit you'll hit first.
public func headlinePercent(_ state: UsageState?, now: Date) -> Double? {
    state?.windows.values.map { $0.effectivePercentage(at: now) }.max()
}

/// One row of the usage card.
public struct UsageRow: Equatable, Sendable {
    public let key: String
    public let title: String
    /// Nil when Claude Code hasn't reported this window yet.
    public let percent: Double?
    public let resetsAt: Date?
    public let hasReset: Bool

    public var level: UsageLevel { usageLevel(percent ?? 0) }
}

/// Rows for the card: the two standard windows always (so the layout is stable before any data
/// arrives), then any other window Claude Code reports, with a readable name.
public func usageRows(_ state: UsageState?, now: Date) -> [UsageRow] {
    let known = displayedWindows.map(\.key)
    let extra = (state?.windows.keys.filter { !known.contains($0) } ?? []).sorted()

    return (known + extra).map { key in
        let title = displayedWindows.first { $0.key == key }?.long ?? humanize(key)
        guard let w = state?.windows[key] else {
            return UsageRow(key: key, title: title, percent: nil, resetsAt: nil, hasReset: false)
        }
        return UsageRow(key: key, title: title, percent: w.effectivePercentage(at: now),
                        resetsAt: w.resetsAt, hasReset: w.hasReset(at: now))
    }
}

func humanize(_ key: String) -> String {
    let words = key.split(separator: "_").joined(separator: " ")
    return words.prefix(1).uppercased() + words.dropFirst()
}

// MARK: - State file

public struct StateStore {
    public let url: URL

    public init(url: URL = StateStore.defaultURL) {
        self.url = url
    }

    /// `~/Library/Application Support/claude-usage-menubar/usage.json`, or `$CLAUDE_USAGE_MENUBAR_STATE`.
    public static var defaultURL: URL {
        if let override = ProcessInfo.processInfo.environment["CLAUDE_USAGE_MENUBAR_STATE"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("claude-usage-menubar/usage.json")
    }

    /// The current state, or nil if the file is missing or unreadable.
    public func load() -> UsageState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(UsageState.self, from: data)
    }

    /// Merges readings into the file under an exclusive lock, so concurrent Claude Code sessions
    /// can't lose each other's updates. Returns true if the file was rewritten.
    @discardableResult
    public func update(with readings: [String: RateLimitReading], now: Date = Date()) throws -> Bool {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let lockPath = url.path + ".lock"
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { close(fd) }
        flock(fd, LOCK_EX)
        defer { flock(fd, LOCK_UN) }

        let current = load()
        guard let next = merge(current, readings: readings, now: now), next != current else { return false }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // .atomic writes a temporary file and renames it, so readers never see a partial file.
        try encoder.encode(next).write(to: url, options: .atomic)
        return true
    }
}
