// Menu bar app. Reads the state file written by claude-usage-export and shows it.
// No network access, no Keychain access, no edits to any other app's configuration.
import AppKit
import ServiceManagement
import UsageCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = StateStore()
    private var statusItem: NSStatusItem!
    private var state: UsageState?
    private var lastModified: Date?
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            let icon = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent", accessibilityDescription: "Claude usage")
            icon?.isTemplate = true
            button.image = icon
            button.imagePosition = .imageLeading
        }

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu

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
            state = store.load()
        }
        let title = " " + menuBarTitle(state, now: Date())
        if statusItem.button?.title != title {
            statusItem.button?.title = title
        }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        refresh(forceReload: true)
        menu.removeAllItems()
        let now = Date()

        for window in displayedWindows {
            if let w = state?.windows[window.key] {
                menu.addItem(info("\(window.long): \(formatPercent(w.effectivePercentage(at: now))) used", bold: true))
                if w.hasReset(at: now) {
                    menu.addItem(info("Reset at \(clockTime(w.resetsAt, now: now)) · waiting for new data"))
                } else {
                    menu.addItem(info("Resets in \(formatCountdown(from: now, to: w.resetsAt)) · \(clockTime(w.resetsAt, now: now))"))
                }
            } else {
                menu.addItem(info("\(window.long): no data", bold: true))
            }
        }

        menu.addItem(.separator())
        if let updated = state?.updatedAt {
            let relative = RelativeDateTimeFormatter()
            relative.unitsStyle = .full
            menu.addItem(info("Updated \(relative.localizedString(for: updated, relativeTo: now))"))
        } else {
            menu.addItem(info("No data yet. Send a message in Claude Code."))
        }

        menu.addItem(.separator())
        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleOpenAtLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func info(_ text: String, bold: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        if bold {
            item.attributedTitle = NSAttributedString(string: text, attributes: [.font: NSFont.menuFont(ofSize: 0).bold()])
        }
        return item
    }

    private func clockTime(_ date: Date, now: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate(Calendar.current.isDate(date, inSameDayAs: now) ? "jmm" : "EEE jmm")
        return f.string(from: date)
    }

    @objc private func toggleOpenAtLogin(_ sender: NSMenuItem) {
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
    }
}

private extension NSFont {
    func bold() -> NSFont {
        NSFontManager.shared.convert(self, toHaveTrait: .boldFontMask)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
