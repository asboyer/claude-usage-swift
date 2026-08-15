import Foundation

let appVersion = "2.1.34"
let appAuthor = "asboyer"

// Claude usage categories.
let claudeCategoryKeys: [String] = [
    "five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet",
    "seven_day_oauth_apps", "seven_day_cowork", "extra_usage",
]

// Codex usage categories. Codex only exposes a weekly limit window.
let codexCategoryKeys: [String] = ["codex_weekly"]

// All trackable usage categories.
let allCategoryKeys: [String] = claudeCategoryKeys + codexCategoryKeys

let categoryLabels: [String: String] = [
    "five_hour": "5-hour",
    "seven_day": "Weekly",
    "seven_day_opus": "Opus",
    "seven_day_sonnet": "Sonnet",
    "seven_day_oauth_apps": "OAuth Apps",
    "seven_day_cowork": "Cowork",
    "extra_usage": "Extra",
    "codex_weekly": "Weekly",
]

let providerSectionTitles: [UsageProvider: String] = [
    .claude: "Claude",
    .codex: "Codex",
]

let defaultPinnedKeys: Set<String> = [
    "five_hour", "seven_day", "seven_day_sonnet", "extra_usage", "codex_weekly",
]
