// StudyTimer - simple menu bar stopwatch for studying, with a break timer
// Left click: start study / switch to break / switch back to study
// Right click: menu (Study & Break totals, Open Report, Stop, Start at Login, Quit)
// No window (menu bar + Dock icon for easy relaunch), no double-click reset.
import Cocoa
import ServiceManagement

struct Persisted: Codable {
    var elapsed: Int = 0                 // legacy field (unused; kept so old data files still load)
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
        dailyTotals = saved.dailyTotals
        breakElapsed = saved.breakElapsed
        dailyBreakTotals = saved.dailyBreakTotals
    }

    private func save() {
        let data = Persisted(elapsed: 0, dailyTotals: dailyTotals, breakElapsed: breakElapsed, dailyBreakTotals: dailyBreakTotals)
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
            statusItem?.button?.title = "▶ " + formatClock(totalForToday())
        case .breaking:
            statusItem?.button?.title = "☕ " + formatClock(breakElapsed)
        case .stopped:
            statusItem?.button?.title = "❚❚ " + formatClock(totalForToday())
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

        menu.addItem(.separator())

        let loginItem = NSMenuItem(title: "Start at Login", action: #selector(menuToggleLogin), keyEquivalent: "")
        loginItem.target = self
        if #available(macOS 13.0, *) {
            loginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        }
        menu.addItem(loginItem)

        menu.addItem(.separator())

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

        func levelClass(_ secs: Int) -> String {
            switch secs {
            case 0: return "l0"
            case ..<1800: return "l1"
            case ..<3600: return "l2"
            case ..<7200: return "l3"
            default: return "l4"
            }
        }

        let dayLabel: DateFormatter = {
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .gregorian)
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "M/d"
            return f
        }()
        let todayStart = cal.startOfDay(for: now)
        let thisWeekStart = cal.dateInterval(of: .weekOfYear, for: now)!.start

        // Donut: today's study vs break
        let donutHTML: String = {
            let s = totalForToday()
            let b = breakTotalForToday()
            let total = s + b
            let circ = 339.292 // 2 * pi * 54
            if total == 0 {
                return """
                <div class="donut-wrap"><svg width="180" height="180" viewBox="0 0 180 180"><circle cx="90" cy="90" r="54" fill="none" stroke="#e9e9ee" stroke-width="22"/></svg><div class="donut-legend"><div>今日はまだ記録がありません</div></div></div>
                """
            }
            let frac = Double(s) / Double(total)
            let studyLen = frac * circ
            let studyPct = Int((frac * 100).rounded())
            return """
            <div class="donut-wrap"><svg width="180" height="180" viewBox="0 0 180 180"><circle cx="90" cy="90" r="54" fill="none" stroke="#f2a541" stroke-width="22"/><circle cx="90" cy="90" r="54" fill="none" stroke="#3a7bd5" stroke-width="22" stroke-dasharray="\(studyLen) \(circ)" transform="rotate(-90 90 90)"/><text x="90" y="86" text-anchor="middle" font-size="20" font-weight="700" fill="currentColor">\(formatTotal(total))</text><text x="90" y="108" text-anchor="middle" font-size="11" fill="#888">今日の合計</text></svg><div class="donut-legend"><div><span class="dot study"></span>勉強 \(formatTotal(s))（\(studyPct)%）</div><div><span class="dot brk"></span>休憩 \(formatTotal(b))（\(100 - studyPct)%）</div></div></div>
            """
        }()

        // Heatmap: last 15 weeks (columns = weeks, rows = Mon..Sun)
        let heatHTML: String = {
            let startMonday = cal.date(byAdding: .day, value: -14 * 7, to: thisWeekStart)!
            var cells = ""
            for col in 0...14 {
                for row in 0..<7 {
                    let day = cal.date(byAdding: .day, value: col * 7 + row, to: startMonday)!
                    if day > todayStart {
                        cells += "<div class=\"cell empty\"></div>"
                    } else {
                        let secs = dailyTotals[dateFormatter.string(from: day), default: 0]
                        cells += "<div class=\"cell \(levelClass(secs))\" title=\"\(dayLabel.string(from: day)): \(formatTotal(secs))\"></div>"
                    }
                }
            }
            return "<div class=\"heat\">\(cells)</div><div class=\"heat-note\">少ない □ → ■ 多い（1マス＝1日）</div>"
        }()

        // This month calendar (Mon-start); each cell shows that day's study total
        let monthCalHTML: String = {
            let interval = cal.dateInterval(of: .month, for: now)!
            let first = interval.start
            let dayCount = cal.range(of: .day, in: .month, for: now)!.count
            let firstOffset = (cal.component(.weekday, from: first) + 5) % 7 // Mon=0
            var cells = ""
            for name in ["月", "火", "水", "木", "金", "土", "日"] {
                cells += "<div class=\"mcal-head\">\(name)</div>"
            }
            for _ in 0..<firstOffset { cells += "<div class=\"mcal-cell blank\"></div>" }
            for d in 1...dayCount {
                let day = cal.date(byAdding: .day, value: d - 1, to: first)!
                let secs = dailyTotals[dateFormatter.string(from: day), default: 0]
                let brk = dailyBreakTotals[dateFormatter.string(from: day), default: 0]
                let isToday = cal.isDateInToday(day)
                let cls = "mcal-cell \(levelClass(secs))\(isToday ? " today" : "")"
                var label = ""
                if secs > 0 { label += "<div class=\"mcal-min\">勉強 \(formatTotal(secs))</div>" }
                if brk > 0 { label += "<div class=\"mcal-min brk\">休憩 \(formatTotal(brk))</div>" }
                cells += "<div class=\"\(cls)\"><div class=\"mcal-day\">\(d)</div>\(label)</div>"
            }
            return "<div class=\"mcal\">\(cells)</div>"
        }()

        // Monthly totals, newest first (up to 6 months that have any study)
        let monthsHTML: String = {
            var byMonth: [String: Int] = [:]
            for (k, v) in dailyTotals { byMonth[String(k.prefix(7)), default: 0] += v }
            let keys = byMonth.keys.sorted(by: >).prefix(6)
            if keys.isEmpty { return "<div class=\"month-row\">まだ記録がありません</div>" }
            var rows = ""
            for k in keys {
                let parts = k.split(separator: "-")
                let label = "\(parts[0])年\(Int(parts[1])!)月"
                rows += "<div class=\"month-row\"><span>\(label)</span><strong>\(formatTotal(byMonth[k]!))</strong></div>"
            }
            return rows
        }()

        let allTime = dailyTotals.values.reduce(0, +)
        let nowLabel: String = {
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .gregorian)
            f.locale = Locale(identifier: "ja_JP")
            f.dateFormat = "yyyy年M月d日 HH:mm"
            return f.string(from: now)
        }()
        let monthTitle: String = {
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .gregorian)
            f.locale = Locale(identifier: "ja_JP")
            f.dateFormat = "yyyy年M月"
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
          .cards { display: flex; flex-wrap: wrap; gap: 12px; margin-bottom: 8px; }
          .card { background: #fff; border-radius: 12px; padding: 16px 20px; min-width: 140px; box-shadow: 0 1px 3px rgba(0,0,0,.08); }
          .card .k { font-size: 12px; color: #6e6e73; }
          .card .v { font-size: 28px; font-weight: 700; margin-top: 4px; }
          h2 { font-size: 16px; margin: 24px 0 10px; }
          .panel { background: #fff; border-radius: 12px; padding: 16px 20px; box-shadow: 0 1px 3px rgba(0,0,0,.08); }
          .mcal { display: grid; grid-template-columns: repeat(7, 1fr); gap: 4px; }
          .mcal-head { font-size: 11px; color: #6e6e73; text-align: center; padding: 2px 0; }
          .mcal-cell { border-radius: 8px; min-height: 52px; padding: 5px 7px; }
          .mcal-cell.blank { background: transparent; }
          .mcal-cell.l0 { background: #ebedf0; }
          .mcal-cell.l1 { background: #d5f0ea; }
          .mcal-cell.l2 { background: #9fd8cf; }
          .mcal-cell.l3 { background: #4fb3a5; color: #fff; }
          .mcal-cell.l4 { background: #14665a; color: #fff; }
          .mcal-cell.today { outline: 2px solid #3a7bd5; }
          .mcal-day { font-size: 12px; font-weight: 600; }
          .mcal-min { font-size: 11px; margin-top: 2px; }
          .mcal-min.brk { opacity: .75; }
          .donut-wrap { display: flex; align-items: center; gap: 24px; flex-wrap: wrap; }
          .donut-legend { font-size: 14px; line-height: 2; }
          .dot { display: inline-block; width: 12px; height: 12px; border-radius: 3px; margin-right: 8px; }
          .dot.study { background: #3a7bd5; }
          .dot.brk { background: #f2a541; }
          .heat { display: grid; grid-template-rows: repeat(7, 12px); grid-auto-flow: column; grid-auto-columns: 12px; gap: 3px; }
          .cell { width: 12px; height: 12px; border-radius: 3px; }
          .cell.empty { background: transparent; }
          .cell.l0 { background: #ebedf0; }
          .cell.l1 { background: #9fd8cf; }
          .cell.l2 { background: #4fb3a5; }
          .cell.l3 { background: #2b8a7e; }
          .cell.l4 { background: #14665a; }
          .heat-note { font-size: 11px; color: #6e6e73; margin-top: 8px; }
          .month-row { display: flex; justify-content: space-between; padding: 8px 2px; border-bottom: 1px solid #eee; font-size: 14px; }
          .month-row:last-child { border-bottom: none; }
          @media (prefers-color-scheme: dark) {
            body { background: #1c1c1e; color: #f5f5f7; }
            .card, .panel { background: #2c2c2e; }
            .mcal-cell.l0 { background: #3a3a3c; }
            .cell.l0 { background: #3a3a3c; }
            .mcal-cell.l1 { background: #1f4d45; }
            .mcal-cell.l2 { background: #2b8a7e; }
            .month-row { border-bottom-color: #3a3a3c; }
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
        <h2>今日の内訳（勉強 vs 休憩）</h2>
        <div class="panel">\(donutHTML)</div>
        <h2>直近15週のヒートマップ</h2>
        <div class="panel">\(heatHTML)</div>
        <h2>\(monthTitle) のカレンダー</h2>
        <div class="panel">\(monthCalHTML)</div>
        <h2>月ごとの勉強合計</h2>
        <div class="panel">\(monthsHTML)</div>
        </body>
        </html>
        """
    }

    @objc private func menuAdvance() { advanceMode() }
    @objc private func menuStop() { stopBoth() }

    @objc private func menuQuit() {
        save()
        NSApp.terminate(nil)
    }

    @objc private func menuToggleLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change the login setting."
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
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
NSApplication.shared.setActivationPolicy(.regular)
NSApplication.shared.run()
