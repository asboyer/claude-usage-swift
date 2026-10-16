import Foundation
import SQLite3
import Testing

@testable import ClaudeUsageCore

struct OpencodeUsageCoreTests {
    private var utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: iso)!
    }

    // MARK: - monthStart

    @Test func monthStartSnapsToTheFirstAtMidnight() {
        let start = OpencodeUsageCore.monthStart(
            containing: date("2026-09-17T13:45:09Z"), calendar: utcCalendar)
        #expect(start == date("2026-09-01T00:00:00Z"))
    }

    @Test func monthStartOnTheFirstReturnsThatSameDay() {
        let start = OpencodeUsageCore.monthStart(
            containing: date("2026-09-01T00:00:01Z"), calendar: utcCalendar)
        #expect(start == date("2026-09-01T00:00:00Z"))
    }

    @Test func monthStartCrossesAYearBoundary() {
        let start = OpencodeUsageCore.monthStart(
            containing: date("2026-01-09T08:00:00Z"), calendar: utcCalendar)
        #expect(start == date("2026-01-01T00:00:00Z"))
    }

    // MARK: - rank

    @Test func rankOrdersByCostDescending() {
        let ranked = OpencodeUsageCore.rank([
            "claude-opus-4-8": 15.74,
            "kimi-k3": 62.70,
            "glm-5p2": 0.01,
        ])
        #expect(ranked.map { $0.modelID } == ["kimi-k3", "claude-opus-4-8", "glm-5p2"])
    }

    @Test func rankDropsModelsThatCostNothing() {
        let ranked = OpencodeUsageCore.rank([
            "gpt-5.6-sol": 0,
            "kimi-k3": 62.70,
        ])
        #expect(ranked.map { $0.modelID } == ["kimi-k3"])
    }

    @Test func rankBreaksTiesByModelIDSoOrderIsStable() {
        let ranked = OpencodeUsageCore.rank(["zeta": 1.0, "alpha": 1.0])
        #expect(ranked.map { $0.modelID } == ["alpha", "zeta"])
    }

    @Test func rankOfNoPaidModelsIsEmpty() {
        #expect(OpencodeUsageCore.rank(["gpt-5.6-sol": 0]).isEmpty)
    }

    // MARK: - displayName

    @Test func displayNameKeepsOnlyTheTrailingSegmentOfARoutedModel() {
        let spend = OpencodeModelSpend(
            modelID: "accounts/fireworks/models/kimi-k3", costUSD: 62.70)
        #expect(spend.displayName == "kimi-k3")
    }

    @Test func displayNameLeavesAPlainModelIDAlone() {
        let spend = OpencodeModelSpend(modelID: "claude-opus-4-8", costUSD: 15.74)
        #expect(spend.displayName == "claude-opus-4-8")
    }

    // MARK: - totalUSD

    @Test func totalSumsEveryModelNotJustTheCollapsedOnes() {
        let usage = OpencodeUsage(
            models: OpencodeUsageCore.rank([
                "kimi-k3": 62.70,
                "kimi-k3-fast": 30.03,
                "claude-opus-4-8": 15.74,
                "fable-5": 0.02,
            ]),
            monthStart: date("2026-09-01T00:00:00Z")
        )
        #expect(usage.models.count == 4)
        #expect(abs(usage.totalUSD - 108.49) <= 0.001)
    }

    // MARK: - formatCost

    @Test func formatCostAlwaysShowsTwoDecimals() {
        #expect(OpencodeUsageCore.formatCost(108.4) == "$108.40")
        #expect(OpencodeUsageCore.formatCost(0) == "$0.00")
        #expect(OpencodeUsageCore.formatCost(62.699) == "$62.70")
    }

    // MARK: - OpencodeMessageTable.preferred

    @Test func preferredPicksSessionMessageWhenBothTablesExist() {
        let table = OpencodeMessageTable.preferred(among: ["message", "session_message", "part"])
        #expect(table == .sessionMessage)
    }

    @Test func preferredFallsBackToMessageBeforeOpencode2() {
        #expect(OpencodeMessageTable.preferred(among: ["message", "part"]) == .message)
    }

    @Test func preferredIsNilForADatabaseOpencodeDidNotWrite() {
        #expect(OpencodeMessageTable.preferred(among: ["kv"]) == nil)
    }

    // MARK: - Queries, run against fixture databases

    /// Turn cost cutoff for the query tests: 2026-10-01T00:00:00Z in milliseconds.
    private let cutoffMs: Int64 = 1_790_812_800_000

    /// An in-memory database holding opencode 2's `session_message` table.
    private func sessionMessageDatabase() -> OpaquePointer? {
        return database(
            schema: """
                CREATE TABLE session_message (
                  id text PRIMARY KEY, session_id text NOT NULL, type text NOT NULL,
                  seq integer NOT NULL, time_created integer NOT NULL,
                  time_updated integer NOT NULL, data text NOT NULL)
                """,
            rows: [
                // Paid turns this month, one per model.
                """
                ('a', 's', 'assistant', 1, \(cutoffMs + 1000), 0, '{"model":{"id":"accounts/fireworks/models/kimi-k3","providerID":"fireworks-ai"},"cost":0.05,"tokens":{"input":100,"output":20,"reasoning":5,"cache":{"read":1000,"write":10}}}')
                """,
                """
                ('b', 's', 'assistant', 2, \(cutoffMs + 2000), 0, '{"model":{"id":"accounts/fireworks/models/kimi-k3"},"cost":0.01,"tokens":{"input":1,"output":1,"reasoning":0,"cache":{"read":0,"write":0}}}')
                """,
                """
                ('c', 's', 'assistant', 3, \(cutoffMs + 3000), 0, '{"model":{"id":"claude-opus-4-8"},"cost":0.5,"tokens":{"input":1,"output":1,"reasoning":0,"cache":{"read":0,"write":0}}}')
                """,
                // Ignored: before the cutoff, unpaid, not a turn.
                """
                ('d', 's', 'assistant', 4, \(cutoffMs - 1000), 0, '{"model":{"id":"kimi-k3"},"cost":9.0}')
                """,
                """
                ('e', 's', 'assistant', 5, \(cutoffMs + 4000), 0, '{"model":{"id":"gpt-5.6-sol"},"cost":0}')
                """,
                """
                ('f', 's', 'user', 6, \(cutoffMs + 5000), 0, '{"cost":3.0}')
                """,
            ])
    }

    /// An in-memory database holding opencode 1's `message` table.
    private func messageDatabase() -> OpaquePointer? {
        return database(
            schema: """
                CREATE TABLE message (
                  id text PRIMARY KEY, session_id text NOT NULL,
                  time_created integer NOT NULL, time_updated integer NOT NULL, data text NOT NULL)
                """,
            rows: [
                """
                ('a', 's', \(cutoffMs + 1000), 0, '{"role":"assistant","modelID":"kimi-k3","cost":0.25,"tokens":{"total":500,"input":1}}')
                """,
                """
                ('b', 's', \(cutoffMs + 2000), 0, '{"role":"assistant","modelID":"kimi-k3","cost":0.5,"tokens":{"input":10,"output":2}}')
                """,
                """
                ('c', 's', \(cutoffMs + 3000), 0, '{"role":"user","modelID":"kimi-k3","cost":3.0}')
                """,
            ])
    }

    private func database(schema: String, rows: [String]) -> OpaquePointer? {
        var database: OpaquePointer?
        guard sqlite3_open(":memory:", &database) == SQLITE_OK else { return nil }
        let table = schema.split(separator: " ")[2]
        let inserts = rows.map { "INSERT INTO \(table) VALUES \($0);" }.joined(separator: "\n")
        guard sqlite3_exec(database, schema + ";\n" + inserts, nil, nil, nil) == SQLITE_OK else {
            sqlite3_close(database)
            return nil
        }
        return database
    }

    /// Runs `query` with the cutoff bound, returning each row's columns as text.
    private func run(_ query: String, in database: OpaquePointer?) -> [[String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, cutoffMs)
        var rows: [[String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(
                (0..<sqlite3_column_count(statement)).map {
                    sqlite3_column_text(statement, $0).map { String(cString: $0) } ?? ""
                })
        }
        return rows
    }

    @Test func sessionMessageCostQuerySumsPaidAssistantTurnsPerModel() throws {
        let database = try #require(sessionMessageDatabase())
        defer { sqlite3_close(database) }
        let costs = Dictionary(
            uniqueKeysWithValues: run(OpencodeMessageTable.sessionMessage.costQuery, in: database)
                .map { ($0[0], Double($0[1])!) })
        #expect(costs.keys.sorted() == ["accounts/fireworks/models/kimi-k3", "claude-opus-4-8"])
        #expect(abs(costs["accounts/fireworks/models/kimi-k3"]! - 0.06) <= 0.0001)
        #expect(abs(costs["claude-opus-4-8"]! - 0.5) <= 0.0001)
    }

    @Test func sessionMessageRequestQuerySumsTokenParts() throws {
        let database = try #require(sessionMessageDatabase())
        defer { sqlite3_close(database) }
        let rows = run(OpencodeMessageTable.sessionMessage.requestQuery, in: database)
        #expect(rows.map { $0[0] } == ["\(cutoffMs + 1000)", "\(cutoffMs + 2000)", "\(cutoffMs + 3000)"])
        #expect(rows[0][1] == "accounts/fireworks/models/kimi-k3")
        #expect(rows[0][2] == "1135")
        #expect(rows[0][3] == "0.05")
    }

    @Test func messageCostQueryStillReadsOpencode1Databases() throws {
        let database = try #require(messageDatabase())
        defer { sqlite3_close(database) }
        let rows = run(OpencodeMessageTable.message.costQuery, in: database)
        #expect(rows.count == 1)
        #expect(rows.first?[0] == "kimi-k3")
        #expect(rows.first.map { abs(Double($0[1])! - 0.75) <= 0.0001 } == true)
    }

    @Test func messageRequestQueryPrefersRecordedTokenTotal() throws {
        let database = try #require(messageDatabase())
        defer { sqlite3_close(database) }
        let rows = run(OpencodeMessageTable.message.requestQuery, in: database)
        #expect(rows.map { $0[2] } == ["500", "12"])
    }
}
