import Foundation

let appVersion = "2.2.0"
let appAuthor = "asboyer"

let scopedWeeklyKey = "weekly_scoped"

// Claude usage categories.
// `extra_usage` sits right after the scoped weekly row because that limit is what
// starts billing it.
let claudeCategoryKeys: [String] = [
    "five_hour", "seven_day", scopedWeeklyKey, "extra_usage", "seven_day_opus",
    "seven_day_sonnet", "seven_day_oauth_apps", "seven_day_cowork",
]

// Codex usage categories. Codex only exposes a weekly limit window.
let codexCategoryKeys: [String] = ["codex_weekly"]

// All trackable usage categories.
let allCategoryKeys: [String] = claudeCategoryKeys + codexCategoryKeys

let categoryLabels: [String: String] = [
    "five_hour": "5-hour",
    "seven_day": "Weekly",
    scopedWeeklyKey: "Model",
    "seven_day_opus": "Opus",
    "seven_day_sonnet": "Sonnet",
    "seven_day_oauth_apps": "OAuth Apps",
    "seven_day_cowork": "Cowork",
    "extra_usage": "Extra",
    "codex_weekly": "Weekly",
]

/// Labels the API supplies at runtime, overriding `categoryLabels`.
var dynamicCategoryLabels: [String: String] = [:]

func categoryLabel(for key: String) -> String {
    return dynamicCategoryLabels[key] ?? categoryLabels[key] ?? key
}

let providerSectionTitles: [UsageProvider: String] = [
    .claude: "Claude",
    .codex: "Codex",
]

let defaultPinnedKeys: Set<String> = [
    "five_hour", "seven_day", scopedWeeklyKey, "extra_usage", "codex_weekly",
]
