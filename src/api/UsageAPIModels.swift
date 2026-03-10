import Foundation

struct UsageResponse: Codable {
    let five_hour: UsageLimit?
    let seven_day: UsageLimit?
    let seven_day_opus: UsageLimit?
    let seven_day_sonnet: UsageLimit?
    let seven_day_oauth_apps: UsageLimit?
    let seven_day_cowork: UsageLimit?
    let extra_usage: ExtraUsage?
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
}

struct APIErrorResponse: Codable {
    let error: APIError?

    struct APIError: Codable {
        let message: String?
        let type: String?
    }
}
