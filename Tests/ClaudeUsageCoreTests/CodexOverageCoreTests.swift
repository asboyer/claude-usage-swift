import Foundation
import Testing

@testable import ClaudeUsageCore

struct CodexOverageCoreTests {
    private let start = Date(timeIntervalSince1970: 1_791_000_000)

    private func request(
        _ responseID: String? = nil,
        model: String? = "gpt-6-astra",
        input: Int = 1_000_000,
        cached: Int = 0,
        output: Int = 0,
        offset: TimeInterval = 60
    ) -> CodexModelRequest {
        return CodexModelRequest(
            responseID: responseID,
            timestamp: start.addingTimeInterval(offset),
            model: model,
            inputTokens: input,
            cachedInputTokens: cached,
            outputTokens: output
        )
    }

    private func reading(offset: TimeInterval, usedPercent: Double, resetsIn: TimeInterval = 3600) -> CodexLimitReading {
        let timestamp = start.addingTimeInterval(offset)
        return CodexLimitReading(
            timestamp: timestamp,
            windows: [
                CodexLimitWindow(usedPercent: usedPercent, resetsAt: timestamp.addingTimeInterval(resetsIn)),
                CodexLimitWindow(usedPercent: 47, resetsAt: timestamp.addingTimeInterval(86400)),
            ]
        )
    }

    // MARK: - Rate Card

    @Test func ratesMatchExactModel() {
        #expect(CodexCreditRateCard.rates(for: "gpt-6.1-sol") == CodexCreditRates(input: 50, cachedInput: 2.5, output: 250))
    }

    @Test func ratesMatchDatedSnapshotToItsBaseModel() {
        #expect(CodexCreditRateCard.rates(for: "gpt-6-astra-2026-09-01") == CodexCreditRateCard.table["gpt-6-astra"])
    }

    @Test func ratesDoNotConfuseSimilarModelNames() {
        // "gpt-6.1-sol" must not fall through to "gpt-6-sol", which caches at a different rate.
        #expect(CodexCreditRateCard.rates(for: "gpt-6.1-sol")?.cachedInput == 2.5)
        #expect(CodexCreditRateCard.rates(for: "gpt-6-solar") == nil)
    }

    @Test func ratesAreNilForUnknownOrMissingModel() {
        #expect(CodexCreditRateCard.rates(for: "codex-auto-review") == nil)
        #expect(CodexCreditRateCard.rates(for: nil) == nil)
        #expect(CodexCreditRateCard.rates(for: "") == nil)
    }

    // MARK: - Request Credits

    @Test func creditsPriceUncachedCachedAndOutputSeparately() {
        // 200k uncached x 250 + 800k cached x 25 + 100k output x 1,250, per million.
        let credits = request(input: 1_000_000, cached: 800_000, output: 100_000).credits
        #expect(credits == 195)
    }

    @Test func creditsAreNilForUnpricedModel() {
        #expect(request(model: "codex-auto-review").credits == nil)
    }

    // MARK: - Limit Readings

    @Test func readingIsExhaustedWhileAWindowAtTheLimitHasNotReset() {
        let exhausted = reading(offset: 0, usedPercent: 100, resetsIn: 3600)
        #expect(exhausted.isExhausted(at: start.addingTimeInterval(1800)))
        #expect(!exhausted.isExhausted(at: start.addingTimeInterval(3600)))
    }

    @Test func readingIsNotExhaustedBelowOneHundredPercent() {
        #expect(!reading(offset: 0, usedPercent: 99).isExhausted(at: start))
    }

    // MARK: - Session Parsing

    private func usageRecordLine(
        _ timestamp: String, responseID: String, turnID: String, input: Int, cached: Int, output: Int
    ) -> String {
        return """
            {"timestamp":"\(timestamp)","type":"token_usage_record","payload":{"turn_id":"\(turnID)",\
            "response_id":"\(responseID)","usage":{"input_tokens":\(input),"cached_input_tokens":\(cached),\
            "output_tokens":\(output)}}}
            """
    }

    private func tokenCountLine(_ timestamp: String, usedPercent: Double) -> String {
        return """
            {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","info":null,\
            "rate_limits":{"primary":{"used_percent":\(usedPercent),"window_minutes":300,"resets_at":1891313309},\
            "secondary":{"used_percent":47.0,"window_minutes":10080,"resets_at":1891313309}}}}
            """
    }

    private func turnContextLine(_ timestamp: String, turnID: String, model: String) -> String {
        return #"{"timestamp":"\#(timestamp)","type":"turn_context","payload":{"turn_id":"\#(turnID)","model":"\#(model)"}}"#
    }

    @Test func parserReadsRequestsWithTheirTurnsModel() {
        var parser = CodexSessionParser()
        parser.consume(line: turnContextLine("2026-10-06T16:00:00Z", turnID: "t1", model: "gpt-6-astra"))
        parser.consume(line: turnContextLine("2026-10-06T16:00:30Z", turnID: "t2", model: "gpt-6.1-sol"))
        // A request from the first turn that lands after the second turn opened keeps its own model.
        parser.consume(
            line: usageRecordLine(
                "2026-10-06T16:01:00.500Z", responseID: "r1", turnID: "t1", input: 90, cached: 80, output: 10))
        parser.consume(
            line: usageRecordLine("2026-10-06T16:02:00Z", responseID: "r2", turnID: "t2", input: 95, cached: 0, output: 5))

        #expect(parser.requests.map(\.model) == ["gpt-6-astra", "gpt-6.1-sol"])
        #expect(parser.requests.map(\.responseID) == ["r1", "r2"])
        #expect(parser.requests.first?.inputTokens == 90)
        #expect(parser.requests.first?.cachedInputTokens == 80)
        #expect(parser.requests.first?.outputTokens == 10)
    }

    @Test func parserFallsBackToTheLatestModelForAnUnknownTurn() {
        var parser = CodexSessionParser()
        parser.consume(line: turnContextLine("2026-10-06T16:00:00Z", turnID: "t1", model: "gpt-5.6-sol"))
        parser.consume(
            line: usageRecordLine("2026-10-06T16:01:00Z", responseID: "r1", turnID: "other", input: 1, cached: 0, output: 1))
        #expect(parser.requests.first?.model == "gpt-5.6-sol")
    }

    @Test func parserReadsLimitReadingsEvenWithoutTokenInfo() {
        var parser = CodexSessionParser()
        parser.consume(line: tokenCountLine("2026-10-06T16:01:00Z", usedPercent: 100))
        #expect(parser.readings.count == 1)
        #expect(parser.readings.first?.windows.map(\.usedPercent) == [100, 47])
    }

    @Test func parserIgnoresUnrelatedLines() {
        var parser = CodexSessionParser()
        parser.consume(line: #"{"type":"response_item","payload":{"text":"what does token_usage_record mean?"}}"#)
        parser.consume(line: "not json")
        #expect(parser.requests.isEmpty)
        #expect(parser.readings.isEmpty)
    }

    // MARK: - Estimate

    @Test func estimateCountsRequestsSentAfterTheLimitWasReached() {
        let readings = [reading(offset: 0, usedPercent: 100)]
        let requests = [
            request("r1", input: 1_000_000, offset: 60),  // 250 credits
            request("r2", input: 1_000_000, offset: -60),  // before the window opened
        ]
        let estimate = CodexOverageCore.estimate(requests: requests, readings: readings, since: start)
        #expect(estimate.credits == 250)
        #expect(estimate.overageRequests == 1)
        #expect(estimate.dollars(pricePerCredit: 0.04) == 10)
    }

    @Test func estimateLeavesOutTheRequestThatReachesTheLimit() {
        // Codex logs each reading just after its response: r1 pushed the window to 100%,
        // so it was sent under the limit and only r2 is overage.
        let readings = [
            reading(offset: 0, usedPercent: 98),
            reading(offset: 61, usedPercent: 100),
        ]
        let requests = [request("r1", offset: 60), request("r2", offset: 120)]
        let estimate = CodexOverageCore.estimate(requests: requests, readings: readings, since: start)
        #expect(estimate.overageRequests == 1)
    }

    @Test func estimateUsesReadingsFromOtherSessions() {
        // Limits are account-wide, so a reading logged by any session decides the request.
        let readings = [reading(offset: 30, usedPercent: 100)]
        let estimate = CodexOverageCore.estimate(
            requests: [request("other-session", offset: 60)], readings: readings, since: start)
        #expect(estimate.overageRequests == 1)
    }

    @Test func estimateStopsCountingOnceTheExhaustedWindowResets() {
        let readings = [reading(offset: 0, usedPercent: 100, resetsIn: 100)]
        let estimate = CodexOverageCore.estimate(
            requests: [request("r1", offset: 50), request("r2", offset: 200)], readings: readings, since: start)
        #expect(estimate.overageRequests == 1)
    }

    @Test func estimateSkipsRequestsWithNoEarlierReading() {
        let readings = [reading(offset: 120, usedPercent: 100)]
        let estimate = CodexOverageCore.estimate(requests: [request("r1", offset: 60)], readings: readings, since: start)
        #expect(estimate.overageRequests == 0)
    }

    @Test func estimateReportsUnpricedRequestsInsteadOfGuessing() {
        let readings = [reading(offset: 0, usedPercent: 100)]
        let requests = [request("r1", model: "codex-auto-review"), request("r2")]
        let estimate = CodexOverageCore.estimate(requests: requests, readings: readings, since: start)
        #expect(estimate.credits == 250)
        #expect(estimate.unpricedRequests == 1)
    }

    @Test func estimateCountsAResponseReplayedIntoAnotherFileOnce() {
        let readings = [reading(offset: 0, usedPercent: 100)]
        let requests = [request("same"), request("same")]
        let estimate = CodexOverageCore.estimate(requests: requests, readings: readings, since: start)
        #expect(estimate.overageRequests == 1)
    }

    @Test func estimateBreaksCreditsDownByModelMostExpensiveFirst() {
        let readings = [reading(offset: 0, usedPercent: 100)]
        let requests = [
            request("r1", model: "gpt-6.1-sol", input: 1_000_000),  // 50 credits
            request("r2", model: "gpt-6-astra", input: 1_000_000),  // 250 credits
            request("r3", model: "gpt-6.1-sol", input: 1_000_000),  // 50 credits
            request("r4", model: "codex-auto-review"),
        ]
        let estimate = CodexOverageCore.estimate(requests: requests, readings: readings, since: start)
        #expect(
            estimate.models == [
                CodexModelOverage(model: "gpt-6-astra", credits: 250, requests: 1),
                CodexModelOverage(model: "gpt-6.1-sol", credits: 100, requests: 2),
            ])
        #expect(estimate.models.map(\.credits).reduce(0, +) == estimate.credits)
        #expect(estimate.unpricedRequests == 1)
    }

    @Test func formatPeriodSpansTheWeeklyWindowInLocalTime() {
        let newYork = TimeZone(identifier: "America/New_York")!
        let windowStart = Date(timeIntervalSince1970: 1_791_225_720)  // 2026-10-05 18:42 UTC
        let bounded = CodexOverageEstimate(
            periodStart: windowStart, periodEnd: windowStart.addingTimeInterval(604_800), period: .week)
        #expect(CodexOverageCore.formatPeriod(bounded, timeZone: newYork) == "Mon Oct 5, 2:42 PM – Mon Oct 12, 2:42 PM")
        let open = CodexOverageEstimate(periodStart: windowStart, periodEnd: nil, period: .week)
        #expect(CodexOverageCore.formatPeriod(open, timeZone: newYork) == "Since Mon Oct 5, 2:42 PM")
    }

    @Test func formatPeriodShowsAMonthByItsFirstAndLastDay() {
        let range = CodexOveragePeriod.month.range(now: octoberSixth, weeklyWindow: nil, calendar: newYorkCalendar)
        let estimate = CodexOverageEstimate(periodStart: range.start, periodEnd: range.end, period: .month)
        #expect(CodexOverageCore.formatPeriod(estimate, timeZone: newYorkCalendar.timeZone) == "Oct 1 – Oct 31, 2026")
    }

    @Test func formatPeriodShowsADayByItsDate() {
        let range = CodexOveragePeriod.day.range(now: octoberSixth, weeklyWindow: nil, calendar: newYorkCalendar)
        let estimate = CodexOverageEstimate(periodStart: range.start, periodEnd: range.end, period: .day)
        #expect(CodexOverageCore.formatPeriod(estimate, timeZone: newYorkCalendar.timeZone) == "Tue Oct 6")
    }

    // MARK: - Periods

    private var newYorkCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    /// 2026-10-06 17:00 UTC, which is 1:00 PM in New York.
    private let octoberSixth = Date(timeIntervalSince1970: 1_791_306_000)

    @Test func monthPeriodCoversTheLocalCalendarMonth() {
        let range = CodexOveragePeriod.month.range(now: octoberSixth, weeklyWindow: nil, calendar: newYorkCalendar)
        #expect(range.start == Date(timeIntervalSince1970: 1_790_827_200))  // Oct 1 00:00 EDT
        #expect(range.end == Date(timeIntervalSince1970: 1_793_505_600))  // Nov 1 00:00 EDT
    }

    @Test func dayPeriodStartsAtLocalMidnight() {
        let range = CodexOveragePeriod.day.range(now: octoberSixth, weeklyWindow: nil, calendar: newYorkCalendar)
        #expect(range.start == Date(timeIntervalSince1970: 1_791_259_200))  // Oct 6 00:00 EDT
        #expect(range.end == Date(timeIntervalSince1970: 1_791_345_600))  // Oct 7 00:00 EDT
    }

    @Test func weekPeriodFollowsCodexsWeeklyWindowNotTheCalendar() {
        let resetsAt = Date(timeIntervalSince1970: 1_791_830_520)  // Mon Oct 12 18:42 UTC
        let weekly = CodexRateWindow(usedPercent: 47, windowSeconds: 604_800, resetsAt: resetsAt)
        let range = CodexOveragePeriod.week.range(now: octoberSixth, weeklyWindow: weekly, calendar: newYorkCalendar)
        #expect(range.start == resetsAt.addingTimeInterval(-604_800))
        #expect(range.end == resetsAt)
    }

    @Test func weekPeriodFallsBackToTheLastSevenDaysWithoutAWeeklyWindow() {
        let range = CodexOveragePeriod.week.range(now: octoberSixth, weeklyWindow: nil, calendar: newYorkCalendar)
        #expect(range.start == octoberSixth.addingTimeInterval(-604_800))
        #expect(range.end == nil)
    }

    @Test func monthIsTheDefaultPeriod() {
        #expect(CodexOveragePeriod.defaultPeriod == .month)
        #expect(CodexOverageCore.estimate(requests: [], readings: [], since: start).period == .month)
    }

    // MARK: - Price Setting

    @Test func parsePriceAcceptsCommonSpellings() {
        #expect(CodexOverageCore.parsePricePerCredit("0.03") == 0.03)
        #expect(CodexOverageCore.parsePricePerCredit(" $0.035 ") == 0.035)
        #expect(CodexOverageCore.parsePricePerCredit("0,04") == 0.04)
    }

    @Test func parsePriceRejectsNonPositiveOrNonNumericInput() {
        #expect(CodexOverageCore.parsePricePerCredit("abc") == nil)
        #expect(CodexOverageCore.parsePricePerCredit("0") == nil)
        #expect(CodexOverageCore.parsePricePerCredit("-0.04") == nil)
        #expect(CodexOverageCore.parsePricePerCredit("") == nil)
        #expect(CodexOverageCore.parsePricePerCredit("50") == nil)
    }

    @Test func formatPriceKeepsCentsAndCustomPrecision() {
        #expect(CodexOverageCore.formatPrice(0.04) == "$0.04")
        #expect(CodexOverageCore.formatPrice(0.035) == "$0.035")
        #expect(CodexOverageCore.formatPrice(0.1) == "$0.10")
    }

    @Test func formatDollarsAndCreditsGroupThousands() {
        #expect(CodexOverageCore.formatDollars(1605.7) == "$1,605.70")
        #expect(CodexOverageCore.formatCredits(15_142.4) == "15,142 credits")
        #expect(CodexOverageCore.formatCredits(3.24) == "3.2 credits")
    }
}
