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

        let reportItem = NSMenuItem(title: "Open Report…", action: #selector(menuOpenReport), keyEquivalent: "")
        reportItem.target = self
        menu.addItem(reportItem)

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

    // MARK: - Report (local HTML, never uploaded anywhere)
    @objc private func menuOpenReport() {
        save()
        let html = generateReportHTML()
        let url = storageURL.deletingLastPathComponent().appendingPathComponent("report.html")
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not create the report."
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func generateReportHTML() -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday
        let now = Date()
        let todayStart = cal.startOfDay(for: now)

        let dayLabel: DateFormatter = {
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .gregorian)
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "M/d"
            return f
        }()
        let weekdayNames = ["日", "月", "火", "水", "木", "金", "土"] // index: weekday-1 (1=Sun)

        // Last 14 days, oldest first
        var days: [(label: String, study: Int, brk: Int)] = []
        for i in stride(from: 13, through: 0, by: -1) {
            let day = cal.date(byAdding: .day, value: -i, to: todayStart)!
            let key = dateFormatter.string(from: day)
            let wd = cal.component(.weekday, from: day)
            days.append((label: "\(dayLabel.string(from: day)) (\(weekdayNames[wd - 1]))",
                         study: dailyTotals[key, default: 0],
                         brk: dailyBreakTotals[key, default: 0]))
        }
        let maxStudy = max(days.map { $0.study }.max() ?? 0, 1)

        var barsHTML = ""
        for d in days {
            let pct = Int((Double(d.study) / Double(maxStudy) * 100).rounded())
            barsHTML += """
            <div class="bar-row"><span class="bar-label">\(d.label)</span><div class="bar-track"><div class="bar-fill" style="width:\(pct)%"></div></div><span class="bar-value">\(formatTotal(d.study))</span></div>
            """
        }

        var rowsHTML = ""
        for d in days.reversed() {
            rowsHTML += "<tr><td>\(d.label)</td><td>\(formatTotal(d.study))</td><td>\(formatTotal(d.brk))</td></tr>\n"
        }

        // Last 8 weeks (Monday start), oldest first
        let thisWeekStart = cal.dateInterval(of: .weekOfYear, for: now)!.start
        var weeks: [(label: String, study: Int)] = []
        for w in stride(from: 7, through: 0, by: -1) {
            let start = cal.date(byAdding: .day, value: -7 * w, to: thisWeekStart)!
            var sum = 0
            for d in 0..<7 {
                let day = cal.date(byAdding: .day, value: d, to: start)!
                sum += dailyTotals[dateFormatter.string(from: day), default: 0]
            }
            weeks.append((label: "\(dayLabel.string(from: start))〜", study: sum))
        }
        let maxWeek = max(weeks.map { $0.study }.max() ?? 0, 1)
        var weeksHTML = ""
        for wk in weeks {
            let pct = Int((Double(wk.study) / Double(maxWeek) * 100).rounded())
            weeksHTML += """
            <div class="bar-row"><span class="bar-label">\(wk.label)</span><div class="bar-track"><div class="bar-fill week" style="width:\(pct)%"></div></div><span class="bar-value">\(formatTotal(wk.study))</span></div>
            """
        }

        let allTime = dailyTotals.values.reduce(0, +)
        let nowLabel: String = {
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .gregorian)
            f.locale = Locale(identifier: "ja_JP")
            f.dateFormat = "yyyy年M月d日 HH:mm"
            return f.string(from: now)
        }()

        return """
        <!DOCTYPE html>
        <html lang="ja">
        <head>
        <meta charset="utf-8">
        <title>StudyTimer レポート</title>
        <style>
          body { font-family: -apple-system, "Hiragino Sans", sans-serif; margin: 24px; color: #1c1c1e; background: #f5f5f7; }
          h1 { font-size: 22px; margin: 0 0 4px; }
          .sub { color: #6e6e73; font-size: 13px; margin-bottom: 20px; }
          .cards { display: flex; flex-wrap: wrap; gap: 12px; margin-bottom: 24px; }
          .card { background: #fff; border-radius: 12px; padding: 16px 20px; min-width: 140px; box-shadow: 0 1px 3px rgba(0,0,0,.08); }
          .card .k { font-size: 12px; color: #6e6e73; }
          .card .v { font-size: 28px; font-weight: 700; margin-top: 4px; }
          h2 { font-size: 16px; margin: 24px 0 10px; }
          .panel { background: #fff; border-radius: 12px; padding: 16px 20px; box-shadow: 0 1px 3px rgba(0,0,0,.08); }
          .bar-row { display: flex; align-items: center; gap: 10px; margin: 6px 0; }
          .bar-label { width: 86px; font-size: 12px; color: #3a3a3c; text-align: right; }
          .bar-track { flex: 1; background: #e9e9ee; border-radius: 6px; height: 18px; overflow: hidden; }
          .bar-fill { background: linear-gradient(90deg, #2bb3a3, #3a7bd5); height: 100%; border-radius: 6px; min-width: 2px; }
          .bar-fill.week { background: linear-gradient(90deg, #f2a541, #e2603f); }
          .bar-value { width: 64px; font-size: 12px; font-weight: 600; }
          table { border-collapse: collapse; width: 100%; font-size: 13px; }
          th, td { padding: 6px 8px; border-bottom: 1px solid #eee; text-align: left; }
          th { color: #6e6e73; font-weight: 600; }
          @media (prefers-color-scheme: dark) {
            body { background: #1c1c1e; color: #f5f5f7; }
            .card, .panel { background: #2c2c2e; }
            .bar-track { background: #3a3a3c; }
            .bar-label { color: #d1d1d6; }
            th, td { border-bottom-color: #3a3a3c; }
          }
        </style>
        </head>
        <body>
        <h1>📚 StudyTimer レポート</h1>
        <div class="sub">\(nowLabel) 時点 ・ このファイルはあなたの Mac の中だけで作られています</div>
        <div class="cards">
          <div class="card"><div class="k">今日の勉強</div><div class="v">\(formatTotal(totalForToday()))</div></div>
          <div class="card"><div class="k">今日の休憩</div><div class="v">\(formatTotal(breakTotalForToday()))</div></div>
          <div class="card"><div class="k">今週の勉強</div><div class="v">\(formatTotal(totalForThisWeek()))</div></div>
          <div class="card"><div class="k">今月の勉強</div><div class="v">\(formatTotal(totalForThisMonth()))</div></div>
          <div class="card"><div class="k">累計の勉強</div><div class="v">\(formatTotal(allTime))</div></div>
        </div>
        <h2>直近14日間の勉強</h2>
        <div class="panel">\(barsHTML)</div>
        <h2>週ごと（直近8週）</h2>
        <div class="panel">\(weeksHTML)</div>
        <h2>日ごとの内訳（新しい順）</h2>
        <div class="panel"><table><tr><th>日付</th><th>勉強</th><th>休憩</th></tr>
        \(rowsHTML)</table></div>
        </body>
        </html>
        """
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
