import Foundation
import Testing

@testable import ClaudeUsageCore

struct SpendHistoryCoreTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private func date(_ day: String, hour: Int = 12) -> Date {
        let parts = day.split(separator: "-").map { Int($0)! }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: hour))!
    }

    private func claude(_ day: String, hour: Int, model: String = "claude-opus-5", input: Int = 1_000_000)
        -> TranscriptRequest
    {
        return TranscriptRequest(
            sessionID: "s", timestamp: date(day, hour: hour), model: model, inputTokens: input,
            cacheWrite5mTokens: 0, cacheWrite1hTokens: 0, cacheReadTokens: 0, outputTokens: 0,
            isSubagent: false, agent: nil, skill: nil
        )
    }

    private func codex(_ id: String, _ day: String, model: String? = "gpt-6-astra") -> CodexModelRequest {
        return CodexModelRequest(
            responseID: id, timestamp: date(day), model: model,
            inputTokens: 1_000_000, cachedInputTokens: 0, outputTokens: 0
        )
    }

    // MARK: - Claude Extra

    @Test func claudeReadingsBecomeIncreasesBetweenReadings() {
        var ledger = SpendLedger()
        ledger.recordClaudeExtra(dollars: 10, at: date("2026-10-05", hour: 9))
        ledger.recordClaudeExtra(dollars: 10, at: date("2026-10-05", hour: 10))
        ledger.recordClaudeExtra(dollars: 25, at: date("2026-10-05", hour: 11))
        #expect(
            ledger.pendingClaudeExtra == [
                // Spend billed before the first reading has no known window.
                ClaudeExtraIncrease(start: nil, end: date("2026-10-05", hour: 9), dollars: 10),
                ClaudeExtraIncrease(
                    start: date("2026-10-05", hour: 10), end: date("2026-10-05", hour: 11), dollars: 15),
            ])
        #expect(ledger.claudeTrackedSince == date("2026-10-05", hour: 9))
    }

    @Test func claudeResetAtUtcMidnightBeforeLocalMidnightIsCountedOnce() {
        // New York: the API resets at 20:00 on the 30th (UTC midnight), four hours before the local month.
        var ledger = SpendLedger()
        ledger.recordClaudeExtra(dollars: 300, at: date("2026-09-30", hour: 19))
        // Within the reset's first hour the drop waits for the next reading.
        ledger.recordClaudeExtra(dollars: 2, at: date("2026-09-30", hour: 20))
        ledger.recordClaudeExtra(dollars: 4, at: date("2026-09-30", hour: 23))
        ledger.recordClaudeExtra(dollars: 5, at: date("2026-10-01", hour: 1))
        #expect(
            ledger.pendingClaudeExtra.dropFirst()
                == [
                    ClaudeExtraIncrease(
                        start: date("2026-09-30", hour: 20), end: date("2026-09-30", hour: 23), dollars: 4),
                    ClaudeExtraIncrease(
                        start: date("2026-09-30", hour: 23), end: date("2026-10-01", hour: 1), dollars: 1),
                ])
    }

    @Test func claudeStaleTotalJustAfterTheResetIsNotCountedAgain() {
        var ledger = SpendLedger()
        ledger.recordClaudeExtra(dollars: 300, at: date("2026-09-30", hour: 19))
        ledger.recordClaudeExtra(dollars: 300, at: date("2026-09-30", hour: 20))
        #expect(ledger.pendingClaudeExtra.count == 1)
    }

    @Test func claudeGapAfterAResetBeforeTheLocalMonthCountsOnlyTheRise() {
        // The reading at 22:00 New York is already in the UTC month, so its total is this month's.
        var ledger = SpendLedger()
        ledger.recordClaudeExtra(dollars: 2, at: date("2026-09-30", hour: 22))
        ledger.recordClaudeExtra(dollars: 50, at: date("2026-10-03"))
        #expect(
            ledger.pendingClaudeExtra.last
                == ClaudeExtraIncrease(start: date("2026-09-30", hour: 22), end: date("2026-10-03"), dollars: 48))
    }

    @Test func claudeTotalCarriedPastLocalMidnightIsNotCountedAgain() {
        // East of UTC, or on a billing-date reset, the old total is still reported in the new local month.
        var ledger = SpendLedger()
        ledger.recordClaudeExtra(dollars: 300, at: date("2026-09-30", hour: 23))
        ledger.recordClaudeExtra(dollars: 302, at: date("2026-10-01", hour: 1))
        #expect(ledger.pendingClaudeExtra.dropFirst().map(\.dollars) == [2])
    }

    @Test func claudeSingleLowReadingIsIgnored() {
        var ledger = SpendLedger()
        ledger.recordClaudeExtra(dollars: 300, at: date("2026-10-15", hour: 9))
        ledger.recordClaudeExtra(dollars: 0, at: date("2026-10-15", hour: 10))
        ledger.recordClaudeExtra(dollars: 303, at: date("2026-10-15", hour: 11))
        #expect(
            ledger.pendingClaudeExtra.dropFirst()
                == [
                    ClaudeExtraIncrease(
                        start: date("2026-10-15", hour: 9), end: date("2026-10-15", hour: 11), dollars: 3)
                ])
    }

    @Test func claudeDropConfirmedByTheNextReadingCountsFromZero() {
        var ledger = SpendLedger()
        ledger.recordClaudeExtra(dollars: 300, at: date("2026-10-15", hour: 9))
        ledger.recordClaudeExtra(dollars: 4, at: date("2026-10-15", hour: 10))
        #expect(ledger.pendingClaudeExtra.count == 1)
        ledger.recordClaudeExtra(dollars: 6, at: date("2026-10-15", hour: 11))
        #expect(
            ledger.pendingClaudeExtra.dropFirst()
                == [
                    ClaudeExtraIncrease(
                        start: date("2026-10-15", hour: 9), end: date("2026-10-15", hour: 10), dollars: 4),
                    ClaudeExtraIncrease(
                        start: date("2026-10-15", hour: 10), end: date("2026-10-15", hour: 11), dollars: 2),
                ])
    }

    @Test func claudeLongGapAcrossTheResetCountsTheNewTotalFromTheReset() {
        var ledger = SpendLedger()
        ledger.recordClaudeExtra(dollars: 300, at: date("2026-09-28"))
        ledger.recordClaudeExtra(dollars: 350, at: date("2026-10-03"))
        #expect(
            ledger.pendingClaudeExtra.last
                == ClaudeExtraIncrease(start: date("2026-09-30", hour: 20), end: date("2026-10-03"), dollars: 350))
    }

    @Test func claudeIncreaseSplitsAcrossModelsByApiCost() {
        let increase = ClaudeExtraIncrease(
            start: date("2026-10-05", hour: 10), end: date("2026-10-05", hour: 11), dollars: 30)
        let requests = [
            claude("2026-10-05", hour: 9),  // before the window
            claude("2026-10-05", hour: 11, model: "claude-opus-5"),  // $5 at API rates
            claude("2026-10-05", hour: 11, model: "claude-fable-5-1"),  // $10 at API rates
        ]
        let days = SpendLedgerBuilder.claudeDays(increases: [increase], requests: requests, calendar: calendar)
        let models = days["2026-10-05"]?["claude"]
        #expect(models?["claude-opus-5"] == SpendEntry(tokens: 333_333, dollars: 10))
        #expect(models?["claude-fable-5-1"] == SpendEntry(tokens: 666_667, dollars: 20))
    }

    @Test func claudeIncreaseWithoutWindowIsBeforeTracking() {
        let increase = ClaudeExtraIncrease(start: nil, end: date("2026-10-05", hour: 9), dollars: 12)
        let days = SpendLedgerBuilder.claudeDays(
            increases: [increase], requests: [claude("2026-10-05", hour: 8)], calendar: calendar)
        #expect(days["2026-10-05"]?["claude"] == [SpendLedgerBuilder.beforeTracking: SpendEntry(dollars: 12)])
    }

    @Test func claudeIncreaseWithNoLocalRequestsIsUnmatched() {
        let increase = ClaudeExtraIncrease(
            start: date("2026-10-05", hour: 10), end: date("2026-10-05", hour: 11), dollars: 3)
        let days = SpendLedgerBuilder.claudeDays(
            increases: [increase], requests: [claude("2026-10-05", hour: 9)], calendar: calendar)
        #expect(days["2026-10-05"]?["claude"] == [SpendLedgerBuilder.unmatched: SpendEntry(dollars: 3)])
    }

    // MARK: - Codex Overage

    @Test func codexDaysCountOnlyRequestsSentAtTheLimit() {
        let exhausted = CodexLimitReading(
            timestamp: date("2026-10-05", hour: 11),
            windows: [CodexLimitWindow(usedPercent: 100, resetsAt: date("2026-10-06"))]
        )
        let days = SpendLedgerBuilder.codexDays(
            requests: [codex("r1", "2026-10-05"), codex("r1", "2026-10-05"), codex("r2", "2026-10-07")],
            readings: [exhausted], calendar: calendar)
        #expect(days["2026-10-05"]?["codex"] == ["gpt-6-astra": SpendEntry(tokens: 1_000_000, credits: 250)])
        #expect(days["2026-10-07"] == nil)
    }

    @Test func codexMergeKeepsHistoryOnceSessionsAreDeleted() {
        var ledger = SpendLedger()
        ledger.merge(.codex, days: ["2026-09-01": ["codex": ["gpt-6-astra": SpendEntry(tokens: 100, credits: 5)]]])
        ledger.merge(.codex, days: ["2026-09-01": ["codex": ["gpt-6-astra": SpendEntry(tokens: 40, credits: 2)]]])
        #expect(ledger.days["2026-09-01"]?["codex"]?["gpt-6-astra"]?.credits == 5)
    }

    @Test func codexRescanJudgesANewSessionByTheLastScansReading() {
        // The weekly limit hit 100% in a session the incremental rescans no longer read.
        let exhausted = CodexLimitReading(
            timestamp: date("2026-10-01"),
            windows: [CodexLimitWindow(usedPercent: 100, resetsAt: date("2026-10-08"))]
        )
        let laterReading = CodexLimitReading(
            timestamp: date("2026-10-05", hour: 13),
            windows: [CodexLimitWindow(usedPercent: 100, resetsAt: date("2026-10-08"))]
        )
        let r1 = codex("r1", "2026-10-05")
        var ledger = SpendLedger()
        ledger.timeZone = "America/New_York"
        ledger.mergeCodexScan(requests: [], readings: [exhausted], nextCutoff: date("2026-10-04", hour: 0))
        ledger.mergeCodexScan(requests: [r1], readings: [laterReading], nextCutoff: date("2026-10-04", hour: 0))
        // A later rescan reads the same session again, with a newer request after its reading.
        let r2 = CodexModelRequest(
            responseID: "r2", timestamp: date("2026-10-05", hour: 14), model: "gpt-6-astra",
            inputTokens: 2_000_000, cachedInputTokens: 0, outputTokens: 0)
        ledger.mergeCodexScan(requests: [r1, r2], readings: [laterReading], nextCutoff: date("2026-10-04", hour: 0))
        #expect(ledger.days["2026-10-05"]?["codex"] == ["gpt-6-astra": SpendEntry(tokens: 3_000_000, credits: 750)])
        #expect(ledger.lastCodexReading == exhausted)
    }

    @Test func ledgerKeysDaysInItsOwnTimeZone() {
        var ledger = SpendLedger()
        ledger.timeZone = "America/New_York"
        // 02:00 UTC on the 2nd is still the 1st in New York, wherever the Mac is now.
        let request = OpencodeRequestCost(
            timestamp: ISO8601DateFormatter().date(from: "2026-10-02T02:00:00Z")!, model: "m", tokens: 1, costUSD: 5)
        let days = SpendLedgerBuilder.opencodeDays(requests: [request], calendar: ledger.calendar)
        #expect(days.keys.sorted() == ["2026-10-01"])
    }

    @Test func ledgerFromAnOlderVersionDecodesWithDefaults() throws {
        let json = #"{"days":{"2026-10-01":{"codex":{"m":{"tokens":5}}}},"pendingClaudeExtra":[]}"#
        let ledger = try JSONDecoder().decode(SpendLedger.self, from: Data(json.utf8))
        #expect(ledger.days["2026-10-01"]?["codex"]?["m"] == SpendEntry(tokens: 5))
        #expect(ledger.timeZone == nil && ledger.lastCodexReading == nil)
    }

    @Test func displayModelDropsContextAndDateSuffixes() {
        #expect(SpendLedgerBuilder.displayModel("claude-opus-5[1m]") == "claude-opus-5")
        #expect(SpendLedgerBuilder.displayModel("claude-haiku-4-5-20251001") == "claude-haiku-4-5")
        #expect(SpendLedgerBuilder.displayModel(nil) == "unknown")
    }

    // MARK: - Periods

    @Test func periodsRollExtraSpendIntoWeeksWithTokenShares() {
        var ledger = SpendLedger()
        ledger.merge(.codex, days: [
            "2026-10-05": [
                "codex": [
                    "gpt-6-astra": SpendEntry(tokens: 300, credits: 2_500),
                    "gpt-6.1-sol": SpendEntry(tokens: 700, credits: 400),
                ]
            ]
        ])
        ledger.add(days: [
            "2026-10-06": ["claude": ["claude-opus-5": SpendEntry(tokens: 50, dollars: 7)]],
            "2026-09-29": ["claude": ["claude-opus-5": SpendEntry(tokens: 10, dollars: 3)]],
        ])
        let periods = SpendHistoryCore.periods(
            from: ledger, granularity: .week, count: 3, pricePerCredit: 0.04,
            now: date("2026-10-07"), calendar: calendar
        )
        #expect(periods.count == 3)
        #expect(periods[0].providers.isEmpty)
        #expect(periods[1].dollars == 3)

        let thisWeek = periods[2]
        #expect(thisWeek.start == calendar.startOfDay(for: date("2026-10-05")))
        let codex = thisWeek.provider(.codex)
        #expect(codex?.dollars == 116)
        #expect(codex?.models.map(\.model) == ["gpt-6-astra", "gpt-6.1-sol"])
        #expect(codex?.models.map(\.tokenShare) == [0.3, 0.7])
        #expect(thisWeek.dollars == 123)
    }

    @Test func periodsLeaveOutProvidersWithNoExtraSpend() {
        var ledger = SpendLedger()
        ledger.add(days: ["2026-10-06": ["claude": ["claude-opus-5": SpendEntry(tokens: 50, dollars: 7)]]])
        let periods = SpendHistoryCore.periods(
            from: ledger, granularity: .month, count: 1, pricePerCredit: 0.04,
            now: date("2026-10-07"), calendar: calendar
        )
        #expect(periods[0].providers.map(\.provider) == [.claude])
    }

    @Test func periodsKeepOnlyTheChosenProviders() {
        var ledger = SpendLedger()
        ledger.add(days: ["2026-10-06": ["claude": ["claude-opus-5": SpendEntry(tokens: 50, dollars: 7)]]])
        ledger.merge(.codex, days: ["2026-10-06": ["codex": ["gpt-6-astra": SpendEntry(tokens: 10, credits: 100)]]])
        let codexOnly = SpendHistoryCore.periods(
            from: ledger, providers: [.codex], granularity: .week, count: 1, pricePerCredit: 0.04,
            now: date("2026-10-07"), calendar: calendar)[0]
        #expect(codexOnly.providers.map(\.provider) == [.codex])
        #expect(codexOnly.dollars == 4)
    }

    // MARK: - Opencode

    @Test func opencodeSpendCountsPaidTurnsOnly() {
        let days = SpendLedgerBuilder.opencodeDays(
            requests: [
                OpencodeRequestCost(timestamp: date("2026-10-05", hour: 9), model: "kimi-k3", tokens: 100, costUSD: 2),
                OpencodeRequestCost(timestamp: date("2026-10-05", hour: 10), model: "kimi-k3", tokens: 50, costUSD: 1),
                OpencodeRequestCost(timestamp: date("2026-10-05", hour: 11), model: "free", tokens: 900, costUSD: 0),
            ], calendar: calendar)
        #expect(days["2026-10-05"]?["opencode"] == ["kimi-k3": SpendEntry(tokens: 150, dollars: 3)])

        var ledger = SpendLedger()
        ledger.merge(.opencode, days: days)
        let period = SpendHistoryCore.periods(
            from: ledger, granularity: .week, count: 1, pricePerCredit: 0.04,
            now: date("2026-10-07"), calendar: calendar)[0]
        #expect(period.provider(.opencode)?.dollars == 3)
    }

    // MARK: - Rescan cutoff

    @Test func codexRescanStartsTheDayBeforeTheLastScan() {
        let cutoff = SpendLedgerBuilder.codexRescanCutoff(lastScan: date("2026-10-06", hour: 15), calendar: calendar)
        #expect(cutoff == calendar.startOfDay(for: date("2026-10-05")))
    }
}
