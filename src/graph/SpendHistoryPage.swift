import Foundation

private func money(_ amount: Double) -> String {
    return CodexOverageCore.formatDollars(amount)
}

/// Whole dollars on the chart axis; cents would crowd it without telling the reader more.
private func axisMoney(_ amount: Double) -> String {
    return String(format: "$%.0f", amount)
}

private let pageDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US")
    return formatter
}()

private func format(_ date: Date, _ pattern: String) -> String {
    pageDateFormatter.dateFormat = pattern
    return pageDateFormatter.string(from: date)
}

private func periodTitle(_ period: SpendPeriod, granularity: SpendGranularity) -> String {
    switch granularity {
    case .week:
        let last = period.end.addingTimeInterval(-1)
        return format(period.start, "MMM d") + " – " + format(last, "MMM d, yyyy")
    case .month:
        return format(period.start, "MMMM yyyy")
    }
}

private func shortTitle(_ period: SpendPeriod, granularity: SpendGranularity) -> String {
    return format(period.start, granularity == .week ? "MMM d" : "MMM")
}

/// An ⓘ whose sentence shows on hover.
private func info(_ text: String) -> String {
    return "<span class=\"info\" data-tip=\"\(text.htmlEscaped)\">i</span>"
}

/// "↓ 24% vs last week · avg $412.10 a week", leaving out whatever there is nothing to compare with.
private func context(_ periods: [SpendPeriod], index: Int, granularity: SpendGranularity) -> String {
    var parts: [String] = []
    let period = periods[index]
    if index > 0, periods[index - 1].dollars > 0 {
        let previous = periods[index - 1].dollars
        let change = (period.dollars - previous) / previous
        parts.append(
            "\(change >= 0 ? "↑" : "↓") \(Int((abs(change) * 100).rounded()))% vs last \(granularity.rawValue)")
    }
    let earlier = periods[..<index].filter { $0.dollars > 0 }
    if earlier.count >= 2 {
        let average = earlier.reduce(0) { $0 + $1.dollars } / Double(earlier.count)
        parts.append("avg \(money(average)) a \(granularity.rawValue)")
    }
    return parts.joined(separator: " · ")
}

private func modelLines(_ total: SpendProviderTotal) -> String {
    return total.models.map { model in
        let name =
            model.model == SpendLedgerBuilder.beforeTracking
            ? "\(model.model) \(info("Claude Extra billed this month before the app started recording it, so it cannot be split by model."))"
            : model.model.htmlEscaped
        let share = model.tokenShare > 0 ? CodexOverageCore.formatShare(model.tokenShare) + " of tokens" : ""
        return """
            <div class="model"><span class="model-name">\(name)</span>\
            <span class="model-share">\(share)</span><span class="model-cost">\(money(model.dollars))</span></div>
            """
    }.joined()
}

private func periodPanel(
    _ periods: [SpendPeriod], index: Int, granularity: SpendGranularity, filter: String
) -> String {
    let period = periods[index]
    var providers = ""
    for provider in SpendProvider.allCases {
        guard let total = period.provider(provider) else { continue }
        let share = period.dollars > 0 ? total.dollars / period.dollars * 100 : 0
        providers += """
            <div class="provider">
              <div class="provider-row"><span class="dot \(provider.rawValue)"></span>\
            <span class="provider-name">\(provider.displayName)</span>\
            <span class="provider-cost">\(money(total.dollars))</span></div>
              <div class="track"><span class="fill \(provider.rawValue)" style="width:\(String(format: "%.1f", share))%"></span></div>
              <div class="models">\(modelLines(total))</div>
            </div>
            """
    }
    let empty = "No extra billed this \(granularity.rawValue)."
    // Each period carries its own copy of the Models switch; the script keeps the copies in step.
    let content =
        providers.isEmpty
        ? "<p class=\"empty\">\(empty)</p>"
        : """
        <div class="section-head"><span>By provider</span>\
        <label class="switch"><input type="checkbox" data-switch="models"><span class="knob"></span>Models</label></div>
        <div class="providers">\(providers)</div>
        """
    return """
        <article class="period" data-p="\(filter)" data-g="\(granularity.rawValue)" data-i="\(index)" \
        data-title="\(periodTitle(period, granularity: granularity))" hidden>
          <p class="amount">\(money(period.dollars))</p>
          <p class="context">\(context(periods, index: index, granularity: granularity))&nbsp;</p>
          \(content)
        </article>
        """
}

/// Rounds up to 1, 2, 2.5 or 5 times a power of ten, so gridlines land on readable values.
private func niceCeiling(_ value: Double) -> Double {
    guard value > 0 else { return 1 }
    let magnitude = pow(10, floor(log10(value)))
    for step in [1.0, 2.0, 2.5, 5.0, 10.0] where step * magnitude >= value {
        return step * magnitude
    }
    return 10 * magnitude
}

/// A bar segment with rounded top corners and a square base.
private func roundedTopPath(x: Double, y: Double, width: Double, height: Double) -> String {
    let radius = min(3, height, width / 2)
    return String(
        format: "M%.1f,%.1f L%.1f,%.1f Q%.1f,%.1f %.1f,%.1f L%.1f,%.1f Q%.1f,%.1f %.1f,%.1f L%.1f,%.1f Z",
        x, y + height, x, y + radius, x, y, x + radius, y, x + width - radius, y, x + width, y,
        x + width, y + radius, x + width, y + height)
}

/// Every period at once, Claude and Codex stacked, for spotting patterns across weeks or months.
private func chart(
    _ periods: [SpendPeriod], granularity: SpendGranularity, filter: String
) -> String {
    let width = 440.0
    let height = 150.0
    let left = 40.0
    let top = 6.0
    let bottom = 20.0
    let plot = height - top - bottom
    let maximum = niceCeiling(periods.map(\.dollars).max() ?? 0)
    let slot = (width - left) / Double(max(periods.count, 1))
    let barWidth = min(18, slot * 0.6)

    var svg = ""
    for tick in 0...2 {
        let y = top + plot - plot * Double(tick) / 2
        svg += """
            <line x1="\(left)" x2="\(width)" y1="\(y)" y2="\(y)" class="grid"/>\
            <text x="\(left - 6)" y="\(y + 3.5)" class="axis" text-anchor="end">\(axisMoney(maximum * Double(tick) / 2))</text>
            """
    }
    for (index, period) in periods.enumerated() {
        let x = left + slot * Double(index) + (slot - barWidth) / 2
        var base = top + plot
        var segments = ""
        let drawn = SpendProvider.allCases.compactMap { provider in
            period.provider(provider).map { (provider, plot * $0.dollars / maximum) }
        }.filter { $0.1 > 0 }
        for (position, (provider, segmentHeight)) in drawn.enumerated() {
            let isTop = position == drawn.count - 1
            // A 2px surface gap separates stacked segments.
            let visible = max(segmentHeight - (position > 0 ? 2 : 0), 1)
            let y = base - segmentHeight
            segments +=
                isTop
                ? "<path d=\"\(roundedTopPath(x: x, y: y, width: barWidth, height: visible))\" class=\"\(provider.rawValue)\"/>"
                : "<rect x=\"\(x)\" y=\"\(y)\" width=\"\(barWidth)\" height=\"\(visible)\" class=\"\(provider.rawValue)\"/>"
            base = y
        }
        let lines =
            ["\(periodTitle(period, granularity: granularity)): \(money(period.dollars))"]
            + SpendProvider.allCases.compactMap { provider in
                period.provider(provider).map { "\(provider.displayName) \(money($0.dollars))" }
            }
        svg += """
            <g class="column" data-i="\(index)" data-tip="\(lines.joined(separator: "\n").htmlEscaped)">\
            <rect x="\(left + slot * Double(index))" y="\(top)" width="\(slot)" height="\(plot)" class="hit"/>\(segments)\
            <text x="\(x + barWidth / 2)" y="\(height - 5)" class="axis" text-anchor="middle">\
            \(shortTitle(period, granularity: granularity))</text></g>
            """
    }
    return """
        <svg class="chart" data-p="\(filter)" data-g="\(granularity.rawValue)" viewBox="0 0 \(width) \(height)" hidden>\
        \(svg)</svg>
        """
}

/// Renders the Spend panel, or a placeholder while `ledger` is still being scanned.
func generateSpendHistoryHTML(ledger: SpendLedger?, pricePerCredit: Double) -> String {
    var panels = ""
    var charts = ""
    var counts: [String: Int] = [:]
    // Only providers with something recorded get a filter button, and "All" only when there are two.
    let present = SpendProvider.allCases.filter { provider in
        ledger?.days.values.contains { $0[provider.rawValue]?.isEmpty == false } ?? false
    }
    let filters: [(key: String, providers: Set<SpendProvider>)] =
        [("all", Set(SpendProvider.allCases))] + (present.count > 1 ? present.map { ($0.rawValue, [$0]) } : [])
    if let ledger {
        for granularity in SpendGranularity.allCases {
            func periods(_ providers: Set<SpendProvider>) -> [SpendPeriod] {
                return SpendHistoryCore.periods(
                    from: ledger, providers: providers, granularity: granularity, count: 12,
                    pricePerCredit: pricePerCredit)
            }
            // Every filter shares one period list, starting at the first period with any spend, so
            // switching filters keeps the selected period.
            let first = periods(Set(SpendProvider.allCases)).firstIndex { $0.dollars > 0 } ?? 11
            counts[granularity.rawValue] = 12 - first
            for filter in filters {
                let shown = Array(periods(filter.providers)[first...])
                charts += chart(shown, granularity: granularity, filter: filter.key)
                for index in shown.indices {
                    panels += periodPanel(shown, index: index, granularity: granularity, filter: filter.key)
                }
            }
        }
    } else {
        panels = "<p class=\"empty\">Reading local sessions…</p>"
    }

    var sources =
        "Spend billed past your plans. Codex overage is estimated from sessions on this Mac at "
        + "\(CodexOverageCore.formatPrice(pricePerCredit)) per credit (Settings › Codex Credit Price); "
        + "Claude Extra comes from the usage the Claude API reports"
    if let since = ledger?.claudeTrackedSince {
        sources += ", recorded since \(format(since, "MMM d, yyyy"))"
    }
    sources +=
        ". Opencode spend is the cost opencode records for each pay-per-token request; "
        + "subscription-billed turns cost nothing there and are left out."
    let providerButtons = filters.map { filter in
        "<button data-v=\"\(filter.key)\">\(filter.key == "all" ? "All" : SpendProvider(rawValue: filter.key)?.displayName ?? filter.key)</button>"
    }.joined()
    let legend = present.map { provider in
        "<span data-p=\"\(provider.rawValue)\"><span class=\"dot \(provider.rawValue)\"></span>\(provider.displayName)</span>"
    }.joined()
    let countsJSON = "{\"week\":\(counts["week"] ?? 0),\"month\":\(counts["month"] ?? 0)}"
    let controls = ledger == nil ? " hidden" : ""

    return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
          :root {
            --surface: #fcfcfb; --text: #0b0b0b; --text-2: #6b6a66; --rule: #ebeae6; --soft: #f3f2ef;
            --claude: #eb6834; --codex: #2a78d6; --opencode: #1baf7a;
          }
          @media (prefers-color-scheme: dark) {
            :root {
              --surface: #1a1a19; --text: #f5f5f3; --text-2: #a3a29a; --rule: #2e2e2c; --soft: #262624;
              --claude: #d95926; --codex: #3987e5; --opencode: #199e70;
            }
          }
          * { box-sizing: border-box; }
          body {
            background: var(--surface); color: var(--text); margin: 0; padding: 20px 24px 18px;
            font: 13px -apple-system, BlinkMacSystemFont, sans-serif;
          }
          .page { max-width: 460px; margin: 0 auto; }
          [hidden] { display: none !important; }
          header { display: flex; align-items: center; gap: 8px; margin-bottom: 16px; }
          h1 { font-size: 13px; font-weight: 600; margin: 0; }
          .spacer { flex: 1; }
          .info {
            display: inline-flex; align-items: center; justify-content: center; width: 14px; height: 14px;
            border-radius: 50%; border: 1px solid var(--text-2); color: var(--text-2); font: italic 600 9px Georgia, serif;
            cursor: help; vertical-align: 1px; margin-left: 4px;
          }
          .segmented { display: inline-flex; background: var(--soft); border-radius: 7px; padding: 2px; }
          .segmented button {
            border: 0; background: none; color: var(--text-2); font: inherit; font-size: 12px; white-space: nowrap;
            padding: 3px 9px; border-radius: 5px; cursor: pointer;
          }
          .segmented button.on { background: var(--surface); color: var(--text); box-shadow: 0 1px 2px rgba(0,0,0,0.12); }
          nav { display: flex; align-items: center; gap: 8px; }
          .arrow {
            border: 0; background: none; color: var(--text-2); font-size: 18px; line-height: 1;
            width: 26px; height: 26px; border-radius: 6px; cursor: pointer;
          }
          .arrow:hover:not(:disabled) { background: var(--soft); color: var(--text); }
          .arrow:disabled { opacity: 0.25; cursor: default; }
          .period { margin-top: 2px; }
          .legend-row { display: flex; align-items: center; justify-content: space-between; margin-bottom: 4px; }
          .period-title { flex: 1; color: var(--text-2); font-size: 12px; }
          .amount { margin: 2px 0 0; font-size: 32px; font-weight: 600; letter-spacing: -0.5px; font-variant-numeric: tabular-nums; }
          .context { margin: 2px 0 0; color: var(--text-2); font-size: 12px; }
          .providers { border-top: 1px solid var(--rule); }
          .provider { padding: 12px 0; border-bottom: 1px solid var(--rule); }
          .provider-row { display: flex; align-items: center; gap: 8px; }
          .dot { width: 8px; height: 8px; border-radius: 50%; }
          .provider-name { flex: 1; font-weight: 500; }
          .provider-cost { width: 80px; text-align: right; font-weight: 600; font-variant-numeric: tabular-nums; }
          .track { height: 4px; margin-top: 8px; background: var(--soft); border-radius: 2px; overflow: hidden; }
          .fill { display: block; height: 100%; border-radius: 2px; }
          .claude { background: var(--claude); fill: var(--claude); }
          .codex { background: var(--codex); fill: var(--codex); }
          .opencode { background: var(--opencode); fill: var(--opencode); }
          .models { display: none; margin-top: 8px; }
          body.show-models .models { display: block; }
          .model { display: flex; align-items: baseline; gap: 8px; padding: 3px 0 3px 16px; font-size: 12px; }
          .model-name { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
          .model-share { color: var(--text-2); font-size: 11px; font-variant-numeric: tabular-nums; }
          .model-cost { width: 80px; text-align: right; font-variant-numeric: tabular-nums; }
          .section-head {
            display: flex; align-items: center; justify-content: space-between; margin-top: 18px; padding-bottom: 6px;
            color: var(--text-2); font-size: 11px; text-transform: uppercase; letter-spacing: 0.4px;
          }
          .section-head .switch { text-transform: none; letter-spacing: 0; }
          .switch { display: flex; align-items: center; gap: 8px; color: var(--text-2); font-size: 12px; cursor: pointer; user-select: none; }
          .switch input { display: none; }
          .knob { width: 26px; height: 16px; border-radius: 8px; background: var(--rule); position: relative; transition: background .15s; }
          .knob::after {
            content: ""; position: absolute; top: 2px; left: 2px; width: 12px; height: 12px; border-radius: 50%;
            background: #fff; box-shadow: 0 1px 2px rgba(0,0,0,0.25); transition: transform .15s;
          }
          .switch input:checked + .knob { background: var(--text-2); }
          .switch input:checked + .knob::after { transform: translateX(10px); }
          .charts { margin-top: 22px; }
          .chart { width: 100%; height: auto; display: block; }
          .legend { display: flex; gap: 14px; text-transform: none; letter-spacing: 0; }
          .legend .dot { display: inline-block; margin-right: 5px; }
          .grid { stroke: var(--rule); stroke-width: 1; }
          .axis { fill: var(--text-2); font-size: 9px; font-variant-numeric: tabular-nums; }
          .hit { fill: transparent; }
          .column { cursor: pointer; }
          .column:hover .hit { fill: var(--text); fill-opacity: 0.05; }
          .column.off path, .column.off rect:not(.hit) { opacity: 0.45; }
          .empty { color: var(--text-2); margin: 16px 0 0; }
          #tip {
            position: fixed; pointer-events: none; display: none; max-width: 260px; white-space: pre-line;
            background: var(--surface); color: var(--text); border: 1px solid var(--rule); border-radius: 6px;
            padding: 6px 9px; font-size: 11px; line-height: 1.45; box-shadow: 0 2px 8px rgba(0,0,0,0.15); z-index: 10;
          }
        </style>
        </head>
        <body>
          <div class="page">
            <header>
              <h1>Spend\(info(sources))</h1><span class="spacer"></span>
              <div class="segmented"\(filters.count > 1 ? controls : " hidden") data-control="p">\(providerButtons)</div>
              <div class="segmented"\(controls) data-control="g"><button data-v="week">Week</button><button data-v="month">Month</button></div>
            </header>
            <nav\(controls)>
              <span class="period-title" id="title"></span>
              <button class="arrow" id="prev" aria-label="Previous">‹</button>
              <button class="arrow" id="next" aria-label="Next">›</button>
            </nav>
            \(panels)
            <div class="charts"\(controls)>
              <div class="section-head legend-row"><span id="chart-title"></span>\
            <span class="legend">\(legend)</span></div>
              \(charts)
            </div>
          </div>
          <div id="tip"></div>
          <script>
            const counts = \(countsJSON);
            const store = {
              get(key, fallback) { try { return localStorage.getItem('spend-' + key) ?? fallback; } catch (e) { return fallback; } },
              set(key, value) { try { localStorage.setItem('spend-' + key, value); } catch (e) {} },
            };
            const filters = [...document.querySelectorAll('[data-control="p"] button')].map(b => b.dataset.v);
            const state = { p: store.get('p', 'all'), g: store.get('g', 'week') };
            // A provider remembered from before may have no data now.
            if (!filters.includes(state.p)) state.p = 'all';
            const index = { week: counts.week - 1, month: counts.month - 1 };
            const matches = el => el.dataset.p === state.p && el.dataset.g === state.g;
            function render() {
              document.querySelectorAll('.segmented').forEach(c => c.querySelectorAll('button').forEach(
                b => b.classList.toggle('on', b.dataset.v === state[c.dataset.control])));
              const i = index[state.g];
              // toggleAttribute rather than .hidden, which SVG elements do not implement.
              document.querySelectorAll('.chart').forEach(el => el.toggleAttribute('hidden', !matches(el)));
              document.querySelectorAll('.period').forEach(p => {
                p.hidden = !matches(p) || +p.dataset.i !== i;
                if (!p.hidden) document.getElementById('title').textContent = p.dataset.title;
              });
              const n = counts[state.g];
              document.getElementById('chart-title').textContent = `Last ${n} ${state.g}${n === 1 ? '' : 's'}`;
              document.querySelectorAll('.legend [data-p]').forEach(
                el => el.hidden = state.p !== 'all' && el.dataset.p !== state.p);
              document.querySelectorAll('.column').forEach(c => c.classList.toggle('off', +c.dataset.i !== i));
              document.getElementById('prev').disabled = i <= 0;
              document.getElementById('next').disabled = i >= counts[state.g] - 1;
            }
            const select = i => { index[state.g] = Math.max(0, Math.min(counts[state.g] - 1, i)); render(); };
            document.querySelectorAll('.segmented').forEach(c => c.querySelectorAll('button').forEach(b => b.onclick = () => {
              state[c.dataset.control] = b.dataset.v; store.set(c.dataset.control, b.dataset.v); render();
            }));
            document.querySelectorAll('.column').forEach(el => el.addEventListener('click', () => select(+el.dataset.i)));
            document.getElementById('prev').onclick = () => select(index[state.g] - 1);
            document.getElementById('next').onclick = () => select(index[state.g] + 1);
            document.addEventListener('keydown', e => {
              if (e.key === 'ArrowLeft') select(index[state.g] - 1);
              if (e.key === 'ArrowRight') select(index[state.g] + 1);
            });
            function setSwitch(name, on) {
              document.querySelectorAll(`[data-switch="${name}"]`).forEach(input => input.checked = on);
              document.body.classList.toggle('show-' + name, on);
              store.set(name, on ? '1' : '0');
            }
            document.querySelectorAll('[data-switch]').forEach(input =>
              input.onchange = () => setSwitch(input.dataset.switch, input.checked));
            setSwitch('models', store.get('models', '0') === '1');
            const tip = document.getElementById('tip');
            document.querySelectorAll('[data-tip]').forEach(el => {
              el.addEventListener('mousemove', e => {
                tip.textContent = el.dataset.tip;
                tip.style.display = 'block';
                const x = Math.max(8, Math.min(e.clientX + 12, window.innerWidth - tip.offsetWidth - 8));
                const y = e.clientY + 16 + tip.offsetHeight > window.innerHeight ? e.clientY - tip.offsetHeight - 10 : e.clientY + 16;
                tip.style.left = x + 'px';
                tip.style.top = y + 'px';
              });
              el.addEventListener('mouseleave', () => tip.style.display = 'none');
            });
            render();
          </script>
        </body>
        </html>
        """
}
