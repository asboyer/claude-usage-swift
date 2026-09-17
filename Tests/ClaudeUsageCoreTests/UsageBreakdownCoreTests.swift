import Foundation
import Testing
@testable import ClaudeUsageCore

struct UsageBreakdownCoreTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func request(
        session: String = "s1",
        minutesFromBase: Double = 0,
        model: String = "claude-sonnet-5",
        input: Int = 0,
        cacheWrite5m: Int = 0,
        cacheWrite1h: Int = 0,
        cacheRead: Int = 0,
        output: Int = 0,
        isSubagent: Bool = false,
        agent: String? = nil,
        skill: String? = nil
    ) -> TranscriptRequest {
        return TranscriptRequest(
            sessionID: session,
            timestamp: base.addingTimeInterval(minutesFromBase * 60),
            model: model,
            inputTokens: input,
            cacheWrite5mTokens: cacheWrite5m,
            cacheWrite1hTokens: cacheWrite1h,
            cacheReadTokens: cacheRead,
            outputTokens: output,
            isSubagent: isSubagent,
            agent: agent,
            skill: skill
        )
    }

    // MARK: - Model Rates

    @Test func ratesMatchTheModelExactly() {
        #expect(ClaudeModelRates.rates(for: "claude-haiku-4-5").input == 1)
        #expect(ClaudeModelRates.rates(for: "claude-fable-5-1").output == 50)
    }

    @Test func ratesIgnoreAContextWindowSuffix() {
        #expect(ClaudeModelRates.rates(for: "claude-opus-5[1m]") == ClaudeModelRates.rates(for: "claude-opus-5"))
    }

    @Test func ratesFallBackToTheModelFamily() {
        #expect(ClaudeModelRates.rates(for: "claude-sonnet-9-9") == ClaudeModelRates.rates(for: "claude-sonnet-5"))
    }

    @Test func ratesFallBackToOpusTierWhenTheModelIsUnknown() {
        #expect(ClaudeModelRates.rates(for: "some-other-model") == ClaudeModelRates.fallback)
        #expect(ClaudeModelRates.rates(for: nil) == ClaudeModelRates.fallback)
    }

    // MARK: - Request Cost

    @Test func weightedCostAppliesPerTokenTypeRates() {
        let sample = request(model: "claude-sonnet-5", input: 1_000_000, output: 1_000_000)
        // Sonnet 5 bills $2 per million input and $10 per million output.
        #expect(abs(sample.weightedCost - 12) < 0.0001)
    }

    @Test func contextCountsEveryPromptToken() {
        let sample = request(input: 10, cacheWrite5m: 20, cacheWrite1h: 30, cacheRead: 40, output: 1000)
        #expect(sample.contextTokens == 100)
    }

    @Test func subagentGroupPrefersTheSkillOverTheAgentType() {
        #expect(request(agent: "general-purpose", skill: "code-review").subagentGroup == "code-review")
        #expect(request(agent: "Explore").subagentGroup == "Explore")
        #expect(request().subagentGroup == "unattributed")
    }

    // MARK: - Breakdown

    @Test func emptyInputProducesAnEmptyBreakdown() {
        let breakdown = UsageBreakdownBuilder.build(from: [], windowHours: 24)
        #expect(breakdown.isEmpty)
        #expect(breakdown.signals.isEmpty)
    }

    @Test func sessionCountsEveryDistinctSession() {
        let breakdown = UsageBreakdownBuilder.build(
            from: [request(session: "a", output: 100), request(session: "b", output: 100)],
            windowHours: 24
        )
        #expect(breakdown.sessionCount == 2)
        #expect(breakdown.requestCount == 2)
    }

    @Test func aSessionIsSubagentHeavyOnlyWhenSubagentsRunHalfOfIt() {
        let heavy = UsageBreakdownBuilder.build(
            from: [
                request(session: "heavy", output: 300, isSubagent: true, agent: "Explore"),
                request(session: "heavy", output: 100),
            ],
            windowHours: 24
        )
        let signal = heavy.signals.first { $0.headline.contains("subagent-heavy") }
        #expect(signal?.share == 1.0)

        let light = UsageBreakdownBuilder.build(
            from: [
                request(session: "light", output: 100, isSubagent: true, agent: "Explore"),
                request(session: "light", output: 900),
            ],
            windowHours: 24
        )
        #expect(!light.signals.contains { $0.headline.contains("subagent-heavy") })
    }

    @Test func longContextSignalCountsOnlyRequestsOverTheThreshold() {
        let breakdown = UsageBreakdownBuilder.build(
            from: [
                request(session: "a", cacheRead: 200_000, output: 1000),
                request(session: "b", cacheRead: 1000, output: 1000),
            ],
            windowHours: 24
        )
        let signal = breakdown.signals.first { $0.headline.contains(">150k context") }
        // The long-context request reads far more cache, so it dominates the weighted total.
        #expect(signal != nil)
        #expect((signal?.share ?? 0) > 0.7)
    }

    @Test func longSessionSignalUsesTheSpanBetweenFirstAndLastRequest() {
        let breakdown = UsageBreakdownBuilder.build(
            from: [
                request(session: "long", minutesFromBase: 0, output: 500),
                request(session: "long", minutesFromBase: 9 * 60, output: 500),
            ],
            windowHours: 24
        )
        #expect(breakdown.signals.contains { $0.headline.contains("8+ hours") })

        let short = UsageBreakdownBuilder.build(
            from: [
                request(session: "short", minutesFromBase: 0, output: 500),
                request(session: "short", minutesFromBase: 60, output: 500),
            ],
            windowHours: 24
        )
        #expect(!short.signals.contains { $0.headline.contains("8+ hours") })
    }

    @Test func signalsAreSortedByShareAndDropWeakOnes() {
        let breakdown = UsageBreakdownBuilder.build(
            from: [
                request(
                    session: "a", minutesFromBase: 0, cacheRead: 400_000, output: 4000,
                    isSubagent: true, skill: "code-review"
                ),
                request(session: "a", minutesFromBase: 9 * 60, output: 10),
            ],
            windowHours: 24
        )
        #expect(breakdown.signals == breakdown.signals.sorted { $0.share > $1.share })
        #expect(breakdown.signals.allSatisfy { $0.share >= UsageBreakdownBuilder.minimumSignalShare })
    }

    @Test func skillsTableCoversMainThreadWorkAndSubagentsTableCoversSidechains() {
        let breakdown = UsageBreakdownBuilder.build(
            from: [
                request(session: "a", output: 100, skill: "artifact-design"),
                request(session: "a", output: 300, isSubagent: true, agent: "general-purpose", skill: "code-review"),
                request(session: "a", output: 100, isSubagent: true, agent: "Explore"),
                request(session: "a", output: 500),
            ],
            windowHours: 24
        )
        #expect(breakdown.skills.map { $0.label } == ["artifact-design"])
        #expect(breakdown.subagents.map { $0.label } == ["code-review", "Explore"])
        #expect(abs((breakdown.subagents.first?.share ?? 0) - 0.3) < 0.0001)
    }

    @Test func topSubagentGroupBecomesASignal() {
        let breakdown = UsageBreakdownBuilder.build(
            from: [
                request(session: "a", output: 700, isSubagent: true, agent: "general-purpose", skill: "code-review"),
                request(session: "a", output: 300),
            ],
            windowHours: 24
        )
        #expect(breakdown.signals.contains { $0.headline.contains("subagents under \"code-review\"") })
    }

    // MARK: - Transcript Timestamps

    @Test func transcriptTimestampsParseWithAndWithoutFractionalSeconds() {
        #expect(ClaudeCodeTranscripts.parseTimestamp("2026-08-31T19:52:31.043Z") != nil)
        #expect(ClaudeCodeTranscripts.parseTimestamp("2026-08-31T19:52:31Z") != nil)
        #expect(ClaudeCodeTranscripts.parseTimestamp("not a date") == nil)
    }
}
