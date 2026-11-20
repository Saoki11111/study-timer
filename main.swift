// StudyTimer - simple menu bar stopwatch for studying
// Left click: start / pause
// Right click: menu (Today / This Week / This Month, Reset, Quit)
// No window, no Dock icon, no double-click reset.
import Cocoa

struct Persisted: Codable {
    var elapsed: Int = 0
    var dailyTotals: [String: Int] = [:] // "yyyy-MM-dd" -> seconds
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var isRunning = false
    private var elapsed = 0
    private var dailyTotals: [String: Int] = [:]
    private var tickCount = 0

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Storage
    private var storageURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("StudyTimer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("data.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let saved = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        elapsed = saved.elapsed
        dailyTotals = saved.dailyTotals
    }

    private func save() {
        let data = Persisted(elapsed: elapsed, dailyTotals: dailyTotals)
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: storageURL, options: [.atomic])
        }
    }

    // MARK: - Lifecycle
    func applicationDidFinishLaunching(_ notification: Notification) {
        load()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        }
        updateTitle()
    }

    func applicationWillTerminate(_ notification: Notification) {
        save()
    }

    // MARK: - Click handling
    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showMenu()
        } else {
            toggle()
        }
    }

    private func toggle() {
        isRunning.toggle()
        if isRunning {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.elapsed += 1
                let key = self.dateFormatter.string(from: Date())
                self.dailyTotals[key, default: 0] += 1
                self.tickCount += 1
                if self.tickCount % 5 == 0 { self.save() }
                self.updateTitle()
            }
        } else {
            timer?.invalidate()
            timer = nil
            save()
        }
        updateTitle()
    }

    private func updateTitle() {
        let prefix = isRunning ? "▶ " : "❚❚ "
        statusItem?.button?.title = prefix + formatClock(elapsed)
    }

    // MARK: - Menu (right click)
    private func showMenu() {
        let menu = NSMenu()

        let todayItem = NSMenuItem(title: "Today: \(formatTotal(totalForToday()))", action: nil, keyEquivalent: "")
        todayItem.isEnabled = false
        menu.addItem(todayItem)

        let weekItem = NSMenuItem(title: "This Week: \(formatTotal(totalForThisWeek()))", action: nil, keyEquivalent: "")
        weekItem.isEnabled = false
        menu.addItem(weekItem)

        let monthItem = NSMenuItem(title: "This Month: \(formatTotal(totalForThisMonth()))", action: nil, keyEquivalent: "")
        monthItem.isEnabled = false
        menu.addItem(monthItem)

        menu.addItem(.separator())

        let toggleItem = NSMenuItem(title: isRunning ? "Pause" : "Start", action: #selector(menuToggle), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        let resetItem = NSMenuItem(title: "Reset Timer", action: #selector(menuReset), keyEquivalent: "")
        resetItem.target = self
        menu.addItem(resetItem)

        menu.addItem(.separator())

        let clearItem = NSMenuItem(title: "Clear History (Today/Week/Month)…", action: #selector(menuClearHistory), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)

        let quitItem = NSMenuItem(title: "Quit StudyTimer", action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuToggle() { toggle() }

    @objc private func menuReset() {
        // Reset only the current stopwatch. Daily/weekly/monthly totals are NOT erased.
        timer?.invalidate()
        timer = nil
        isRunning = false
        elapsed = 0
        save()
        updateTitle()
    }

    @objc private func menuClearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear all history?"
        alert.informativeText = "Today / This Week / This Month totals will be set to 0. The current timer is not changed."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            dailyTotals = [:]
            save()
        }
    }

    @objc private func menuQuit() {
        save()
        NSApp.terminate(nil)
    }

    // MARK: - Totals
    private func totalForToday() -> Int {
        dailyTotals[dateFormatter.string(from: Date()), default: 0]
    }

    private func totalForThisWeek() -> Int {
        // Week starting Monday
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday
        let now = Date()
        guard let interval = cal.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        var sum = 0
        var day = interval.start
        while day < interval.end {
            sum += dailyTotals[dateFormatter.string(from: day), default: 0]
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
        return sum
    }

    private func totalForThisMonth() -> Int {
        let keyPrefix = String(dateFormatter.string(from: Date()).prefix(7)) // yyyy-MM
        return dailyTotals.filter { $0.key.hasPrefix(keyPrefix) }.values.reduce(0, +)
    }

    // MARK: - Formatting
    private func formatClock(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
    }

    private func formatTotal(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return seconds > 0 ? "\(seconds)s" : "0m"
    }
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
