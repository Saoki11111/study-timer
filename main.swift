// StudyTimer - simple menu bar stopwatch for studying, with a break timer
// Left click: start study / switch to break / switch back to study
// Right click: menu (Study & Break totals, Reset, Stop, Quit)
// No window, no Dock icon, no double-click reset.
import Cocoa

struct Persisted: Codable {
    var elapsed: Int = 0                 // study stopwatch (seconds)
    var dailyTotals: [String: Int] = [:] // "yyyy-MM-dd" -> study seconds
    var breakElapsed: Int = 0            // current break (seconds)
    var dailyBreakTotals: [String: Int] = [:] // "yyyy-MM-dd" -> break seconds

    init() {}
    init(elapsed: Int, dailyTotals: [String: Int], breakElapsed: Int, dailyBreakTotals: [String: Int]) {
        self.elapsed = elapsed
        self.dailyTotals = dailyTotals
        self.breakElapsed = breakElapsed
        self.dailyBreakTotals = dailyBreakTotals
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        elapsed = try c.decodeIfPresent(Int.self, forKey: .elapsed) ?? 0
        dailyTotals = try c.decodeIfPresent([String: Int].self, forKey: .dailyTotals) ?? [:]
        breakElapsed = try c.decodeIfPresent(Int.self, forKey: .breakElapsed) ?? 0
        dailyBreakTotals = try c.decodeIfPresent([String: Int].self, forKey: .dailyBreakTotals) ?? [:]
    }
}

enum Mode { case stopped, studying, breaking }

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var mode: Mode = .stopped
    private var elapsed = 0
    private var dailyTotals: [String: Int] = [:]
    private var breakElapsed = 0
    private var dailyBreakTotals: [String: Int] = [:]
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
        breakElapsed = saved.breakElapsed
        dailyBreakTotals = saved.dailyBreakTotals
    }

    private func save() {
        let data = Persisted(elapsed: elapsed, dailyTotals: dailyTotals, breakElapsed: breakElapsed, dailyBreakTotals: dailyBreakTotals)
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
            advanceMode()
        }
    }

    /// Left click cycles: stopped -> studying -> breaking -> studying -> ...
    private func advanceMode() {
        switch mode {
        case .stopped:
            mode = .studying
        case .studying:
            mode = .breaking
            breakElapsed = 0 // each break is measured from 0
        case .breaking:
            mode = .studying
        }
        syncTimer()
        save()
        updateTitle()
    }

    private func stopBoth() {
        mode = .stopped
        syncTimer()
        save()
        updateTitle()
    }

    private func syncTimer() {
        if mode == .stopped {
            timer?.invalidate()
            timer = nil
        } else if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self else { return }
                let key = self.dateFormatter.string(from: Date())
                if self.mode == .studying {
                    self.elapsed += 1
                    self.dailyTotals[key, default: 0] += 1
                } else if self.mode == .breaking {
                    self.breakElapsed += 1
                    self.dailyBreakTotals[key, default: 0] += 1
                }
                self.tickCount += 1
                if self.tickCount % 5 == 0 { self.save() }
                self.updateTitle()
            }
        }
    }

    private func updateTitle() {
        switch mode {
        case .studying:
            statusItem?.button?.title = "▶ " + formatClock(elapsed)
        case .breaking:
            statusItem?.button?.title = "☕ " + formatClock(breakElapsed)
        case .stopped:
            statusItem?.button?.title = "❚❚ " + formatClock(elapsed)
        }
    }

    // MARK: - Menu (right click)
    private func showMenu() {
        let menu = NSMenu()

        func infoItem(_ title: String) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            return item
        }
        menu.addItem(infoItem("Study Today: \(formatTotal(totalForToday()))"))
        menu.addItem(infoItem("Break Today: \(formatTotal(breakTotalForToday()))"))
        menu.addItem(infoItem("Study This Week: \(formatTotal(totalForThisWeek()))"))
        menu.addItem(infoItem("Study This Month: \(formatTotal(totalForThisMonth()))"))

        menu.addItem(.separator())

        let switchTitle: String
        switch mode {
        case .stopped: switchTitle = "Start Study"
        case .studying: switchTitle = "Take a Break"
        case .breaking: switchTitle = "Back to Study"
        }
        let switchItem = NSMenuItem(title: switchTitle, action: #selector(menuAdvance), keyEquivalent: "")
        switchItem.target = self
        menu.addItem(switchItem)

        let stopItem = NSMenuItem(title: "Stop Both Timers", action: #selector(menuStop), keyEquivalent: "")
        stopItem.target = self
        stopItem.isEnabled = (mode != .stopped)
        menu.addItem(stopItem)

        let resetItem = NSMenuItem(title: "Reset Timer", action: #selector(menuReset), keyEquivalent: "")
        resetItem.target = self
        menu.addItem(resetItem)

        menu.addItem(.separator())

        let clearItem = NSMenuItem(title: "Clear History (Study/Break totals)…", action: #selector(menuClearHistory), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)

        let quitItem = NSMenuItem(title: "Quit StudyTimer", action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuAdvance() { advanceMode() }
    @objc private func menuStop() { stopBoth() }

    @objc private func menuReset() {
        // Reset the stopwatches only. Daily totals are NOT erased.
        mode = .stopped
        syncTimer()
        elapsed = 0
        breakElapsed = 0
        save()
        updateTitle()
    }

    @objc private func menuClearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear all history?"
        alert.informativeText = "Study and break totals (Today / Week / Month) will be set to 0."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            dailyTotals = [:]
            dailyBreakTotals = [:]
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

    private func breakTotalForToday() -> Int {
        dailyBreakTotals[dateFormatter.string(from: Date()), default: 0]
    }

    private func totalForThisWeek() -> Int {
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
