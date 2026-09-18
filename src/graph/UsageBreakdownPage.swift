import Foundation

extension String {
    /// Skill and agent names come off disk, so they are escaped before reaching the web view.
    var htmlEscaped: String {
        return
            replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

private func percentText(_ share: Double) -> String {
    return "\(Int((share * 100).rounded()))%"
}

private func summarySection(_ breakdown: UsageBreakdown?) -> String {
    let title = "<h2>What's contributing to your limits usage?</h2>"
    guard let breakdown else {
        return "\(title)\n<p class=\"meta\">Reading local sessions…</p>"
    }
    guard !breakdown.isEmpty else {
        return "\(title)\n<p class=\"meta\">No local sessions in the last \(breakdown.windowHours)h.</p>"
    }

    var signalsHTML = ""
    for signal in breakdown.signals {
        signalsHTML += """
            <li>
              <p class="signal"><span class="pct">\(percentText(signal.share))</span> \(signal.headline.htmlEscaped)</p>
              <p class="advice">\(signal.advice.htmlEscaped)</p>
            </li>\n
            """
    }
    if signalsHTML.isEmpty {
        signalsHTML = """
            <li><p class="advice">No single characteristic stands out across the last \(breakdown.windowHours)h.</p></li>
            """
    }

    let skillsTable = shareTable(title: "Skills", rows: breakdown.skills, prefix: "/")
    let subagentsTable = shareTable(title: "Subagents", rows: breakdown.subagents, prefix: "")
    let tablesHTML =
        skillsTable.isEmpty && subagentsTable.isEmpty
        ? "" : "<div class=\"tables\">\(skillsTable)\(subagentsTable)</div>"

    return """
        \(title)
        <p class="meta">Last \(breakdown.windowHours)h</p>
        <ul class="signals">\(signalsHTML)</ul>
        \(tablesHTML)
        """
}

private func shareTable(title: String, rows: [UsageShare], prefix: String) -> String {
    guard !rows.isEmpty else { return "" }
    var body = ""
    for row in rows {
        body += """
            <tr><td>\(prefix)\(row.label.htmlEscaped)</td><td class="pct-cell">\(percentText(row.share))</td></tr>\n
            """
    }
    return """
        <table>
          <thead><tr><th>\(title.htmlEscaped)</th><th class="pct-cell">% of usage</th></tr></thead>
          <tbody>\(body)</tbody>
        </table>
        """
}

/// Renders the page shown by the Usage Breakdown panel: the recent-usage summary above the
/// 90-day heatmap. `breakdown` is nil while the transcript scan is still running.
func generateUsageBreakdownHTML(breakdown: UsageBreakdown?) -> String {
    let file = loadHistoryFile()
    let summaries = file.dailySummaries["five_hour"] ?? []

    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())

    // Build lookup from date string -> peak utilization.
    var lookup: [String: Double] = [:]
    for summary in summaries {
        lookup[summary.date] = summary.peakUtilization
    }

    // Generate 90 days of data ending today.
    var days: [(dateStr: String, weekday: Int, weekIndex: Int, level: Int)] = []
    guard let startDate = calendar.date(byAdding: .day, value: -89, to: today) else {
        return ""
    }

    // Align start to Sunday so columns are full weeks.
    let startWeekday = calendar.component(.weekday, from: startDate)
    guard let alignedStart = calendar.date(byAdding: .day, value: -(startWeekday - 1), to: startDate) else {
        return ""
    }
    let totalDays = (calendar.dateComponents([.day], from: alignedStart, to: today).day ?? 0) + 1
    let numberOfWeeks = (totalDays + 6) / 7

    for i in 0..<(numberOfWeeks * 7) {
        guard let date = calendar.date(byAdding: .day, value: i, to: alignedStart) else {
            continue
        }
        let dateString = dailyDateFormatter.string(from: date)
        let weekday = calendar.component(.weekday, from: date) - 1
        let weekIndex = i / 7
        let peak = lookup[dateString]

        let level: Int
        if date > today {
            level = -1
        } else if let peak {
            if peak >= 90 { level = 4 }
            else if peak >= 61 { level = 3 }
            else if peak >= 31 { level = 2 }
            else if peak >= 1 { level = 1 }
            else { level = 0 }
        } else {
            level = 0
        }

        days.append((dateString, weekday, weekIndex, level))
    }

    var monthLabels: [(weekIndex: Int, label: String)] = []
    let monthFormatter = DateFormatter()
    monthFormatter.dateFormat = "MMM"
    var lastMonth = -1
    for i in 0..<(numberOfWeeks * 7) {
        guard let date = calendar.date(byAdding: .day, value: i, to: alignedStart) else {
            continue
        }
        let month = calendar.component(.month, from: date)
        if month != lastMonth && calendar.component(.weekday, from: date) == 1 {
            lastMonth = month
            monthLabels.append((i / 7, monthFormatter.string(from: date)))
        }
    }

    var cellsHTML = ""
    for day in days where day.level != -1 {
        let tooltip = day.level > 0
            ? "\(day.dateStr): \(Int(lookup[day.dateStr] ?? 0))% peak"
            : "\(day.dateStr): no usage"
        cellsHTML += """
        <rect width="11" height="11" x="\(day.weekIndex * 14)" y="\(day.weekday * 14)" \
        rx="2" ry="2" class="level-\(day.level)"><title>\(tooltip)</title></rect>\n
        """
    }

    var monthLabelsHTML = ""
    for monthLabel in monthLabels {
        monthLabelsHTML += """
        <text x="\(monthLabel.weekIndex * 14 + 2)" y="-4" class="month-label">\(monthLabel.label)</text>\n
        """
    }

    let dayLabelsHTML = """
    <text x="-28" y="23" class="day-label">Mon</text>
    <text x="-28" y="51" class="day-label">Wed</text>
    <text x="-28" y="79" class="day-label">Fri</text>
    """

    let svgWidth = numberOfWeeks * 14 + 2
    let svgHeight = 7 * 14 + 2

    return """
    <!DOCTYPE html>
    <html>
    <head>
    <meta charset="utf-8">
    <style>
      @media (prefers-color-scheme: dark) {
        body { background: #1e1e1e; color: #ccc; }
        .level-0 { fill: #2d2d2d; }
        .level-1 { fill: #0e4429; }
        .level-2 { fill: #006d32; }
        .level-3 { fill: #26a641; }
        .level-4 { fill: #39d353; }
        .legend-text, .meta, .advice { color: #8b949e; fill: #8b949e; }
        th { color: #8b949e; }
        hr { border-color: #2d2d2d; }
        table { border-color: #2d2d2d; }
      }
      @media (prefers-color-scheme: light) {
        body { background: #fff; color: #333; }
        .level-0 { fill: #ebedf0; }
        .level-1 { fill: #9be9a8; }
        .level-2 { fill: #40c463; }
        .level-3 { fill: #30a14e; }
        .level-4 { fill: #216e39; }
        .legend-text, .meta, .advice { color: #656d76; fill: #656d76; }
        th { color: #656d76; }
        hr { border-color: #e1e4e8; }
        table { border-color: #e1e4e8; }
      }
      body {
        font-family: -apple-system, BlinkMacSystemFont, sans-serif;
        margin: 0; padding: 18px 20px; box-sizing: border-box; font-size: 12px;
      }
      /* One centred column so the summary and the heatmap share an axis at any panel width. */
      .page { max-width: 620px; margin: 0 auto; }
      h2 { font-size: 14px; font-weight: 600; margin: 0 0 6px 0; }
      h3 { font-size: 13px; font-weight: 600; margin: 0 0 12px 0; }
      .meta { font-size: 11px; margin: 0 0 14px 0; }
      ul.signals { list-style: none; margin: 0 0 16px 0; padding: 0; }
      ul.signals li { margin-bottom: 12px; }
      .signal { margin: 0 0 2px 0; font-size: 12px; }
      .pct { font-weight: 600; font-variant-numeric: tabular-nums; }
      .advice { margin: 0; font-size: 11px; line-height: 1.45; }
      .tables { display: flex; flex-wrap: wrap; align-items: flex-start; gap: 28px; margin-bottom: 4px; }
      table { border-collapse: collapse; min-width: 200px; }
      th, td { text-align: left; padding: 3px 0; font-weight: normal; }
      th { font-size: 11px; border-bottom: 1px solid; border-color: inherit; }
      .pct-cell { text-align: right; font-variant-numeric: tabular-nums; padding-left: 24px; }
      hr { border: 0; border-top: 1px solid; margin: 18px 0; }
      .heatmap { display: flex; flex-direction: column; align-items: center; }
      .month-label { font-size: 10px; fill: currentColor; }
      .day-label { font-size: 10px; fill: currentColor; }
      .legend { display: flex; align-items: center; gap: 4px; margin-top: 10px; font-size: 11px; }
      .legend svg rect { rx: 2; ry: 2; }
    </style>
    </head>
    <body>
      <div class="page">
      \(summarySection(breakdown))
      <hr>
      <div class="heatmap">
        <h3>Claude Usage — Last 90 Days</h3>
        <svg width="\(svgWidth + 36)" height="\(svgHeight + 20)">
          <g transform="translate(34, 16)">
            \(monthLabelsHTML)
            \(dayLabelsHTML)
            \(cellsHTML)
          </g>
        </svg>
        <div class="legend">
          <span class="legend-text">Less</span>
          <svg width="11" height="11"><rect width="11" height="11" class="level-0"/></svg>
          <svg width="11" height="11"><rect width="11" height="11" class="level-1"/></svg>
          <svg width="11" height="11"><rect width="11" height="11" class="level-2"/></svg>
          <svg width="11" height="11"><rect width="11" height="11" class="level-3"/></svg>
          <svg width="11" height="11"><rect width="11" height="11" class="level-4"/></svg>
          <span class="legend-text">More</span>
        </div>
      </div>
      </div>
    </body>
    </html>
    """
}
