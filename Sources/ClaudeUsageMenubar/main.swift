// Menu bar app. Reads the state file written by claude-usage-export and shows it.
// The only network and Keychain access is the optional Refresh button (see Refresh.swift).
// Never edits any other app's configuration.
import AppKit
import ServiceManagement
import SwiftUI
import UsageCore

// MARK: - Model

final class UsageModel: ObservableObject {
    @Published var state: UsageState?
    @Published var now = Date()
    @Published var openAtLogin = SMAppService.mainApp.status == .enabled
    @Published var refreshing = false
    /// Result of the last Refresh, shown under the title. Nil when there's nothing to say.
    @Published var refreshError: String?
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
    private var panel: UsagePanel!
    private lazy var fetcher = UsageFetcher(store: store)
    private var lastModified: Date?
    private var timer: Timer?
    /// False once macOS has no room for "icon + %"; the app then shows the coloured icon alone.
    private var percentFits = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePanel(_:))
        }

        panel = UsagePanel(content: UsageCard(
            model: model,
            toggleOpenAtLogin: { [weak self] in self?.toggleOpenAtLogin() },
            refresh: { [weak self] in self?.refreshFromAnthropic() },
            quit: { NSApp.terminate(nil) }
        ))
        panel.onClose = { [weak self] in self?.statusItem.button?.highlight(false) }

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

    /// macOS first parks a new or resized item above the screen, then places it about a second
    /// later. Only drop the percentage if the item is still off-screen after it has settled.
    private func checkPlacement() {
        guard isParkedOffScreen else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.isParkedOffScreen else { return }
            self.percentFits = false
            self.updateStatusItem()
        }
    }

    private var isParkedOffScreen: Bool {
        guard let button = statusItem.button, let window = button.window else { return false }
        return !button.attributedTitle.string.isEmpty && window.frame.minY < 0
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

    // MARK: Panel

    @objc private func togglePanel(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if panel.isVisible {
            panel.dismiss()
        } else if panel.dismissedJustNow {
            // This click on the menu bar item already closed the panel: macOS draws the item in
            // another process, so the "click outside" monitor sees the click before this action.
            return
        } else {
            refresh(forceReload: true)
            model.openAtLogin = SMAppService.mainApp.status == .enabled
            button.highlight(true)
            panel.show(below: button)
        }
    }

    private func refreshFromAnthropic() {
        guard !model.refreshing else { return }
        model.refreshing = true
        model.refreshError = nil
        fetcher.refresh { [weak self] result in
            guard let self else { return }
            self.model.refreshing = false
            if case .failure(let error) = result {
                self.model.refreshError = error.localizedDescription
            }
            self.refresh(forceReload: true)
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

// MARK: - Panel

/// Borderless floating panel with a frosted background, dropped down below the menu bar item.
/// (A plain NSPopover renders as a solid sheet with an arrow.)
final class UsagePanel: NSPanel {
    private let hosting: NSView
    private var eventMonitors: [Any] = []
    private var resignObserver: NSObjectProtocol?
    private var dismissedAt = Date.distantPast
    var onClose: (() -> Void)?

    /// True right after the panel closed, so the same click doesn't immediately reopen it.
    var dismissedJustNow: Bool { Date().timeIntervalSince(dismissedAt) < 0.35 }

    init<Content: View>(content: Content) {
        hosting = NSHostingView(rootView: content)
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isReleasedWhenClosed = false

        // A solid background drawn by the app, so the panel looks the same whether or not
        // Reduce Transparency is on (system glass changes with that setting). Everything is
        // clipped to the rounded shape so no rectangular edge or shadow shows past the corners.
        let background = PanelBackground()
        background.wantsLayer = true
        background.layer?.cornerRadius = Self.radius
        background.layer?.cornerCurve = .continuous
        background.layer?.masksToBounds = true
        hosting.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: background.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        contentView = background
    }

    static let radius: CGFloat = 16

    // Borderless panels can't take key status by default; the checkbox and Esc need it.
    override var canBecomeKey: Bool { true }

    func show(below button: NSStatusBarButton) {
        guard let anchor = button.window?.frame, let screen = button.window?.screen ?? NSScreen.main else { return }
        let size = hosting.fittingSize
        let visible = screen.visibleFrame
        var x = anchor.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        let y = anchor.minY - size.height - 6
        setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        // Recompute the shadow from the rounded, clipped content rather than the old frame.
        invalidateShadow()

        NSApp.activate()
        makeKeyAndOrderFront(nil)

        // Close on a click anywhere else, on Esc, or when another app becomes active.
        let click = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
        let escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.dismiss(); return nil }
            return event
        }
        eventMonitors = [click, escape].compactMap { $0 }
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            self?.dismiss()
        }
    }

    func dismiss() {
        guard isVisible else { return }
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors.removeAll()
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        orderOut(nil)
        dismissedAt = Date()
        onClose?()
    }
}

/// Solid panel fill with a faint rim, following light/dark appearance.
final class PanelBackground: NSView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = (dark ? NSColor(white: 0.133, alpha: 1) : NSColor(white: 0.95, alpha: 1)).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = (dark ? NSColor(white: 1, alpha: 0.12) : NSColor(white: 0, alpha: 0.1)).cgColor
    }
}

// MARK: - Card

struct UsageCard: View {
    @ObservedObject var model: UsageModel
    let toggleOpenAtLogin: () -> Void
    let refresh: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Claude Usage")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    if model.refreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(action: refresh) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .buttonStyle(.borderless)
                        .help("Fetch current usage from Anthropic, including claude.ai and the Claude apps. Uses Claude Code's login.")
                    }
                }
                if let error = model.refreshError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

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
