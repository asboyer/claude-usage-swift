import Foundation
import SQLite3

// MARK: - Opencode usage (opencode's local session database)

/// Where opencode keeps the session database it writes every turn to.
private let opencodeDatabasePath = NSString(string: "~/.local/share/opencode/opencode.db")
    .expandingTildeInPath

func fetchOpencodeUsage(completion: @escaping (OpencodeUsage?) -> Void) {
    guard FileManager.default.fileExists(atPath: opencodeDatabasePath) else {
        completion(nil)
        return
    }
    let monthStart = OpencodeUsageCore.monthStart(containing: Date())
    guard let costsByModel = queryOpencodeCosts(since: monthStart) else {
        completion(nil)
        return
    }
    completion(OpencodeUsage(models: OpencodeUsageCore.rank(costsByModel), monthStart: monthStart))
}

/// Nil when opencode isn't installed or its database can't be read.
func fetchOpencodeRequestCosts(since cutoff: Date) -> [OpencodeRequestCost]? {
    guard FileManager.default.fileExists(atPath: opencodeDatabasePath) else { return nil }
    return queryOpencode(\.requestQuery, since: cutoff) { statement in
        guard let modelID = sqlite3_column_text(statement, 1) else { return nil }
        return OpencodeRequestCost(
            timestamp: Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 0)) / 1000),
            model: OpencodeModelSpend(modelID: String(cString: modelID), costUSD: 0).displayName,
            tokens: Int(sqlite3_column_int64(statement, 2)),
            costUSD: sqlite3_column_double(statement, 3))
    }
}

private func queryOpencodeCosts(since monthStart: Date) -> [String: Double]? {
    let rows = queryOpencode(\.costQuery, since: monthStart) { statement -> (String, Double)? in
        guard let modelID = sqlite3_column_text(statement, 0) else { return nil }
        return (String(cString: modelID), sqlite3_column_double(statement, 1))
    }
    return rows.map { Dictionary($0, uniquingKeysWith: +) }
}

/// Opens the database read-only so a running opencode is never blocked or modified, picks the
/// query for whichever message table this opencode version writes, and binds `since` as the
/// query's one millisecond-timestamp parameter.
private func queryOpencode<Row>(
    _ query: (OpencodeMessageTable) -> String, since: Date, row: (OpaquePointer?) -> Row?
) -> [Row]? {
    let escapedPath =
        opencodeDatabasePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        ?? opencodeDatabasePath

    var database: OpaquePointer?
    guard
        sqlite3_open_v2(
            "file://\(escapedPath)?mode=ro", &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil
        ) == SQLITE_OK
    else {
        sqlite3_close(database)
        return nil
    }
    defer { sqlite3_close(database) }

    guard let table = opencodeMessageTable(in: database) else { return nil }

    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, query(table), -1, &statement, nil) == SQLITE_OK else {
        sqlite3_finalize(statement)
        return nil
    }
    defer { sqlite3_finalize(statement) }

    sqlite3_bind_int64(statement, 1, Int64(since.timeIntervalSince1970 * 1000))

    var rows: [Row] = []
    while sqlite3_step(statement) == SQLITE_ROW {
        if let value = row(statement) { rows.append(value) }
    }
    return rows
}

private func opencodeMessageTable(in database: OpaquePointer?) -> OpencodeMessageTable? {
    var statement: OpaquePointer?
    guard
        sqlite3_prepare_v2(
            database, "SELECT name FROM sqlite_master WHERE type = 'table'", -1, &statement, nil)
            == SQLITE_OK
    else {
        sqlite3_finalize(statement)
        return nil
    }
    defer { sqlite3_finalize(statement) }

    var tableNames: Set<String> = []
    while sqlite3_step(statement) == SQLITE_ROW {
        if let name = sqlite3_column_text(statement, 0) { tableNames.insert(String(cString: name)) }
    }
    return OpencodeMessageTable.preferred(among: tableNames)
}
