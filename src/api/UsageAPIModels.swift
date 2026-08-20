import Foundation

struct UsageResponse: Codable {
    let five_hour: UsageLimit?
    let seven_day: UsageLimit?
    let seven_day_opus: UsageLimit?
    let seven_day_sonnet: UsageLimit?
    let seven_day_oauth_apps: UsageLimit?
    let seven_day_cowork: UsageLimit?
    let extra_usage: ExtraUsage?
    let limits: [LimitEntry]?
}

struct LimitEntry: Codable {
    let kind: String?
    let percent: Double?
    let resets_at: String?
    let scope: Scope?

    struct Scope: Codable {
        let model: Model?

        struct Model: Codable {
            let display_name: String?
        }
    }
}

/// The weekly per-model limit (Fable, Opus, ...) arrives in `limits`, not in a `seven_day_<model>` field.
func scopedWeeklyLimit(_ usage: UsageResponse) -> (label: String?, limit: UsageLimit)? {
    guard
        let entry = usage.limits?.first(where: { $0.kind == "weekly_scoped" }),
        let percent = entry.percent
    else {
        return nil
    }
    return (entry.scope?.model?.display_name, UsageLimit(utilization: percent, resets_at: entry.resets_at))
}

func detectModel(_ usage: UsageResponse) -> String {
    return UsageModelDetector.detectPreferredModel(
        opusUtilization: usage.seven_day_opus?.utilization,
        sonnetUtilization: usage.seven_day_sonnet?.utilization
    )
}

struct UsageLimit: Codable {
    let utilization: Double
    let resets_at: String?
}

struct ExtraUsage: Codable {
    let is_enabled: Bool
    let monthly_limit: Double?
    let used_credits: Double?
    let utilization: Double?
    let decimal_places: Int?
}

struct APIErrorResponse: Codable {
    let error: APIError?

    struct APIError: Codable {
        let message: String?
        let type: String?
    }
}
