import Foundation
import SQLite3

// MARK: - Opencode usage (opencode's local session database)

/// Where opencode keeps the session database it writes every turn to.
private let opencodeDatabasePath = NSString(string: "~/.local/share/opencode/opencode.db")
    .expandingTildeInPath

/// Month-to-date cost per model, summed over completed assistant turns.
///
/// opencode inserts the assistant row when a turn starts and fills in `cost` when it
/// finishes, so an in-flight turn contributes nothing until the next refresh picks it up.
private let opencodeCostQuery = """
    SELECT json_extract(data, '$.modelID'), SUM(json_extract(data, '$.cost'))
    FROM message
    WHERE time_created >= ?
      AND json_extract(data, '$.role') = 'assistant'
      AND json_extract(data, '$.cost') > 0
    GROUP BY 1
    """

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

/// Opens the database read-only so a running opencode is never blocked or modified.
private func queryOpencodeCosts(since monthStart: Date) -> [String: Double]? {
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

    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, opencodeCostQuery, -1, &statement, nil) == SQLITE_OK else {
        sqlite3_finalize(statement)
        return nil
    }
    defer { sqlite3_finalize(statement) }

    sqlite3_bind_int64(statement, 1, Int64(monthStart.timeIntervalSince1970 * 1000))

    var costsByModel: [String: Double] = [:]
    while sqlite3_step(statement) == SQLITE_ROW {
        guard let modelID = sqlite3_column_text(statement, 0) else { continue }
        costsByModel[String(cString: modelID)] = sqlite3_column_double(statement, 1)
    }
    return costsByModel
}
