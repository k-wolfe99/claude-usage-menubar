// Menu bar app. Reads the state file written by claude-usage-export and shows it.
// No network access, no Keychain access, no edits to any other app's configuration.
import AppKit
import ServiceManagement
import SwiftUI
import UsageCore

// MARK: - Model

final class UsageModel: ObservableObject {
    @Published var state: UsageState?
    @Published var now = Date()
    @Published var openAtLogin = SMAppService.mainApp.status == .enabled
}

extension UsageLevel {
    var nsColor: NSColor {
        switch self {
        case .low: return .systemGreen
        case .moderate: return .systemYellow
        case .high: return .systemOrange
        case .critical: return .systemRed
        }
    }
    var color: Color { Color(nsColor: nsColor) }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = StateStore()
    private let model = UsageModel()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var lastModified: Date?
    private var timer: Timer?
    /// False once macOS has no room for "icon + %"; the app then shows the coloured icon alone.
    private var percentFits = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: UsageCard(
            model: model,
            toggleOpenAtLogin: { [weak self] in self?.toggleOpenAtLogin() },
            quit: { NSApp.terminate(nil) }
        ))

        // When the item is hidden for lack of room, macOS parks its window above the screen.
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                               object: statusItem.button?.window, queue: .main) { [weak self] _ in
            self?.checkPlacement()
        }
        // The menu bar may have room again after a display change or wake: try the full form again.
        for (center, name) in [(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification),
                               (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification)] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.percentFits = true
                self?.updateStatusItem()
            }
        }

        refresh(forceReload: true)
        // Cheap poll: one stat() call every few seconds. Also keeps countdowns and resets current.
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh(forceReload: false)
        }
        timer?.tolerance = 2
    }

    private func refresh(forceReload: Bool) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: store.url.path)
        let modified = attributes?[.modificationDate] as? Date
        if forceReload || modified != lastModified {
            lastModified = modified
            model.state = store.load()
        }
        model.now = Date()
        updateStatusItem()
    }

    // MARK: Status item

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let percent = headlinePercent(model.state, now: model.now)
        button.image = gaugeImage(percent)
        button.toolTip = "Claude usage: " + menuBarTitle(model.state, now: model.now)

        let title: NSAttributedString
        if let percent, percentFits {
            title = NSAttributedString(string: " " + formatPercent(percent), attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
                .foregroundColor: usageLevel(percent).nsColor,
            ])
        } else {
            title = NSAttributedString(string: "")
        }
        if button.attributedTitle != title {
            button.attributedTitle = title
            // A wider title may no longer fit; check once macOS has placed it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.checkPlacement() }
        }
    }

    private func checkPlacement() {
        guard let button = statusItem.button, let window = button.window,
              !button.attributedTitle.string.isEmpty, window.frame.minY < 0 else { return }
        percentFits = false
        updateStatusItem()
    }

    /// Gauge whose needle and colour follow usage. Plain template gauge before any data arrives.
    private func gaugeImage(_ percent: Double?) -> NSImage? {
        guard let percent else {
            let image = NSImage(systemSymbolName: "gauge.with.dots.needle.0percent", accessibilityDescription: "Claude usage")
            image?.isTemplate = true
            return image
        }
        let needle: String
        switch percent {
        case ..<17: needle = "0"
        case ..<42: needle = "33"
        case ..<58: needle = "50"
        case ..<83: needle = "67"
        default: needle = "100"
        }
        let config = NSImage.SymbolConfiguration(pointSize: NSFont.systemFontSize, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [usageLevel(percent).nsColor]))
        let image = NSImage(systemSymbolName: "gauge.with.dots.needle.\(needle)percent", accessibilityDescription: "Claude usage")?
            .withSymbolConfiguration(config)
        image?.isTemplate = false
        return image
    }

    // MARK: Popover

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            refresh(forceReload: true)
            model.openAtLogin = SMAppService.mainApp.status == .enabled
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func toggleOpenAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Open at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        model.openAtLogin = service.status == .enabled
    }
}

// MARK: - Card

struct UsageCard: View {
    @ObservedObject var model: UsageModel
    let toggleOpenAtLogin: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Claude Usage")
                .font(.system(size: 15, weight: .semibold))

            ForEach(usageRows(model.state, now: model.now), id: \.key) { row in
                UsageRowView(row: row, now: model.now)
            }

            Divider()

            Text(lastUpdated)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            HStack {
                Toggle("Open at Login", isOn: Binding(get: { model.openAtLogin }, set: { _ in toggleOpenAtLogin() }))
                    .toggleStyle(.checkbox)
                Spacer()
                Button("Quit", action: quit)
                    .buttonStyle(.borderless)
            }
            .font(.callout)
        }
        .padding(18)
        .frame(width: 320)
    }

    private var lastUpdated: String {
        guard let updated = model.state?.updatedAt else {
            return "No data yet. Send a message in Claude Code."
        }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .full
        return "Last updated " + relative.localizedString(for: updated, relativeTo: model.now)
    }
}

struct UsageRowView: View {
    let row: UsageRow
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.title)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                if let resetsAt = row.resetsAt {
                    Text(resetLabel(resetsAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            UsageBar(fraction: (row.percent ?? 0) / 100, color: row.level.color)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var detail: String {
        guard let percent = row.percent, let resetsAt = row.resetsAt else { return "No data yet" }
        if row.hasReset { return "0% used · reset, waiting for new data" }
        return "\(formatPercent(percent)) used · resets in \(formatCountdown(from: now, to: resetsAt))"
    }

    private func resetLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        if calendar.isDate(date, inSameDayAs: now) {
            formatter.setLocalizedDateFormatFromTemplate("jmm")
            return (row.hasReset ? "Reset at " : "Resets at ") + formatter.string(from: date)
        }
        let withinWeek = date.timeIntervalSince(now) < 6 * 86_400
        formatter.setLocalizedDateFormatFromTemplate(withinWeek ? "EEE jmm" : "d MMM")
        return (row.hasReset ? "Reset " : "Resets ") + formatter.string(from: date)
    }
}

struct UsageBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                if fraction > 0 {
                    Capsule().fill(color)
                        .frame(width: max(geo.size.width * min(fraction, 1), 6))
                }
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.3), value: fraction)
    }
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
