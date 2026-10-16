import Foundation

// MARK: - Opencode usage

/// One model's month-to-date spend in opencode.
struct OpencodeModelSpend: Equatable {
    let modelID: String
    let costUSD: Double

    /// Provider-routed models arrive as paths (`accounts/fireworks/models/kimi-k3`);
    /// only the trailing segment is short enough for a menu row.
    var displayName: String {
        return modelID.split(separator: "/").last.map(String.init) ?? modelID
    }
}

/// Month-to-date opencode spend, most expensive model first.
struct OpencodeUsage: Equatable {
    let models: [OpencodeModelSpend]
    let monthStart: Date

    var totalUSD: Double {
        return models.reduce(0) { $0 + $1.costUSD }
    }
}

/// One completed opencode turn, as the spend history records it.
struct OpencodeRequestCost: Equatable {
    let timestamp: Date
    /// Display name, the model path's trailing segment.
    let model: String
    let tokens: Int
    let costUSD: Double
}

/// The table opencode records turns in. opencode 2 moved turns from `message` to
/// `session_message` and copied every earlier turn across, so whenever the newer table exists
/// it is the complete one; `message` is only read for databases from before opencode 2.
enum OpencodeMessageTable: String {
    case sessionMessage = "session_message"
    case message

    /// Nil when the database has neither table, so isn't one opencode wrote.
    static func preferred(among tableNames: Set<String>) -> OpencodeMessageTable? {
        return [.sessionMessage, .message].first { tableNames.contains($0.rawValue) }
    }

    /// Month-to-date cost per model, summed over completed assistant turns. Binds one
    /// millisecond-timestamp parameter, the start of the month.
    ///
    /// opencode inserts the assistant row when a turn starts and fills in `cost` when it
    /// finishes, so an in-flight turn contributes nothing until the next refresh picks it up.
    var costQuery: String {
        return """
            SELECT \(modelID), SUM(json_extract(data, '$.cost'))
            FROM \(rawValue)
            WHERE time_created >= ?
              AND \(isAssistant)
              AND json_extract(data, '$.cost') > 0
            GROUP BY 1
            """
    }

    /// Every completed, paid assistant turn since one bound millisecond timestamp, as
    /// (time created, model ID, tokens, cost) rows for the spend history.
    var requestQuery: String {
        return """
            SELECT time_created, \(modelID), \(tokens), json_extract(data, '$.cost')
            FROM \(rawValue)
            WHERE time_created >= ?
              AND \(isAssistant)
              AND json_extract(data, '$.cost') > 0
            """
    }

    private var modelID: String {
        switch self {
        case .sessionMessage: return "json_extract(data, '$.model.id')"
        case .message: return "json_extract(data, '$.modelID')"
        }
    }

    private var isAssistant: String {
        switch self {
        case .sessionMessage: return "type = 'assistant'"
        case .message: return "json_extract(data, '$.role') = 'assistant'"
        }
    }

    /// opencode 2 and older opencode 1 versions record no token total, so it is summed from
    /// the parts.
    private var tokens: String {
        let parts = """
            COALESCE(json_extract(data, '$.tokens.input'), 0)
                + COALESCE(json_extract(data, '$.tokens.output'), 0)
                + COALESCE(json_extract(data, '$.tokens.reasoning'), 0)
                + COALESCE(json_extract(data, '$.tokens.cache.read'), 0)
                + COALESCE(json_extract(data, '$.tokens.cache.write'), 0)
            """
        switch self {
        case .sessionMessage: return parts
        case .message: return "COALESCE(json_extract(data, '$.tokens.total'), \(parts))"
        }
    }
}

enum OpencodeUsageCore {
    /// How many models the section lists before hiding the rest behind "More".
    static let collapsedModelCount = 3

    /// The period the menu reports on: midnight on the 1st of `date`'s month, local time.
    static func monthStart(containing date: Date, calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    /// Collapses per-model costs into ranked spend, dropping models that cost nothing.
    /// Subscription-billed providers report zero cost per turn, and thousands of free
    /// turns would otherwise crowd out the models actually being paid for.
    static func rank(_ costsByModel: [String: Double]) -> [OpencodeModelSpend] {
        return
            costsByModel
            .filter { $0.value > 0 }
            .map { OpencodeModelSpend(modelID: $0.key, costUSD: $0.value) }
            .sorted { first, second in
                if first.costUSD != second.costUSD { return first.costUSD > second.costUSD }
                return first.modelID < second.modelID
            }
    }

    static func formatCost(_ usd: Double) -> String {
        return String(format: "$%.2f", usd)
    }
}
