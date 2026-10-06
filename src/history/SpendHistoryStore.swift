import Foundation

private let spendLedgerURL: URL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/ClaudeUsage/extra_spend.json")
/// Guards the ledger file, which the refresh path and the history panel both update.
private let spendLedgerLock = NSLock()
/// Often enough that Claude Code's 30-day transcript cleanup never runs ahead of the ledger.
let spendLedgerRescanInterval: TimeInterval = 6 * 3600

func loadSpendLedger() -> SpendLedger {
    spendLedgerLock.lock()
    defer { spendLedgerLock.unlock() }
    return readSpendLedger()
}

private func readSpendLedger() -> SpendLedger {
    guard
        let data = try? Data(contentsOf: spendLedgerURL),
        let ledger = try? JSONDecoder().decode(SpendLedger.self, from: data)
    else { return SpendLedger() }
    return ledger
}

private func writeSpendLedger(_ ledger: SpendLedger) {
    try? FileManager.default.createDirectory(
        at: spendLedgerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let data = try? JSONEncoder().encode(ledger) {
        try? data.write(to: spendLedgerURL, options: .atomic)
    }
}

/// Reads every local Claude Code transcript and Codex session: all usage for the usage view,
/// Codex overage, and the requests behind pending Claude Extra increases. Slow on a busy machine,
/// so callers run it off the main thread.
@discardableResult
func rescanSpendLedger(includeCodex: Bool, now: Date = Date()) -> SpendLedger {
    let pending = loadSpendLedger().pendingClaudeExtra
    let twentyYears = 24 * 365 * 20
    let claude = ClaudeCodeTranscripts.recentRequests(windowHours: twentyYears, now: now)
    let codex = includeCodex ? scanCodexSessions(modifiedSince: .distantPast) : (requests: [], readings: [])
    let codexExtra = SpendLedgerBuilder.codexDays(requests: codex.requests, readings: codex.readings)
    let usage = SpendLedgerBuilder.usageDays(claude: claude, codex: codex.requests)

    spendLedgerLock.lock()
    defer { spendLedgerLock.unlock() }
    var ledger = readSpendLedger()
    // A scan that finished first has already attributed and cleared some of `pending`, and adding
    // those again would double them. Increases recorded while the scan ran stay pending.
    let unclaimed = pending.filter { ledger.pendingClaudeExtra.contains($0) }
    ledger.add(days: SpendLedgerBuilder.claudeDays(increases: unclaimed, requests: claude))
    ledger.pendingClaudeExtra.removeAll { unclaimed.contains($0) }
    ledger.mergeCodex(days: codexExtra)
    ledger.mergeUsage(days: usage)
    ledger.lastScan = now
    writeSpendLedger(ledger)
    return ledger
}

/// Called on every Claude refresh, so each increase is bounded by the reading before it.
func recordClaudeExtraSpend(dollars: Double, now: Date = Date()) {
    spendLedgerLock.lock()
    defer { spendLedgerLock.unlock() }
    var ledger = readSpendLedger()
    ledger.recordClaudeExtra(dollars: dollars, at: now)
    writeSpendLedger(ledger)
}
