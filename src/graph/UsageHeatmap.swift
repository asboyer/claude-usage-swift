import Foundation

func generateHeatmapHTML() -> String {
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
        .legend-text { fill: #8b949e; }
      }
      @media (prefers-color-scheme: light) {
        body { background: #fff; color: #333; }
        .level-0 { fill: #ebedf0; }
        .level-1 { fill: #9be9a8; }
        .level-2 { fill: #40c463; }
        .level-3 { fill: #30a14e; }
        .level-4 { fill: #216e39; }
        .legend-text { fill: #656d76; }
      }
      body {
        font-family: -apple-system, BlinkMacSystemFont, sans-serif;
        display: flex; flex-direction: column; align-items: center;
        justify-content: center; height: 100vh; margin: 0; padding: 16px;
        box-sizing: border-box;
      }
      h3 { font-size: 13px; font-weight: 600; margin: 0 0 12px 0; }
      .month-label { font-size: 10px; fill: currentColor; }
      .day-label { font-size: 10px; fill: currentColor; }
      .legend { display: flex; align-items: center; gap: 4px; margin-top: 10px; font-size: 11px; }
      .legend svg rect { rx: 2; ry: 2; }
    </style>
    </head>
    <body>
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
    </body>
    </html>
    """
}
