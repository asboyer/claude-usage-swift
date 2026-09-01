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
