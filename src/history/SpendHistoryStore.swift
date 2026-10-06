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
    guard let data = try? Data(contentsOf: spendLedgerURL) else { return SpendLedger() }
    if let ledger = try? JSONDecoder().decode(SpendLedger.self, from: data) { return ledger }
    // History past Claude Code's 30-day transcript window exists only in this file, so an
    // unreadable one is set aside for recovery rather than overwritten by the next write.
    let aside = spendLedgerURL.deletingPathExtension()
        .appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
    try? FileManager.default.moveItem(at: spendLedgerURL, to: aside)
    return SpendLedger()
}

private func writeSpendLedger(_ ledger: SpendLedger) {
    try? FileManager.default.createDirectory(
        at: spendLedgerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let data = try? JSONEncoder().encode(ledger) {
        try? data.write(to: spendLedgerURL, options: .atomic)
    }
}

/// Reads Codex sessions for overage, opencode's database, and the Claude Code transcripts behind
/// pending Claude Extra increases. After the first scan only Codex files touched since the last
/// one are read. Callers run it off the main thread, since the first scan reads every Codex session.
@discardableResult
func rescanSpendLedger(includeCodex: Bool, includeOpencode: Bool, now: Date = Date()) -> SpendLedger {
    let saved = loadSpendLedger()
    let pending = saved.pendingClaudeExtra
    // Only requests inside a pending increase's window are needed to split it by model.
    let claude = pending.compactMap(\.start).min().map { start in
        ClaudeCodeTranscripts.recentRequests(windowHours: Int(now.timeIntervalSince(start) / 3600) + 1, now: now)
    } ?? []
    let codexCutoff = saved.lastCodexScan.map { SpendLedgerBuilder.codexRescanCutoff(lastScan: $0) } ?? .distantPast
    let codex = includeCodex ? scanCodexSessions(modifiedSince: codexCutoff) : (requests: [], readings: [])
    let codexExtra = SpendLedgerBuilder.codexDays(requests: codex.requests, readings: codex.readings)
    // Opencode keeps its own history, so it is always read in full.
    let opencode = SpendLedgerBuilder.opencodeDays(
        requests: includeOpencode ? fetchOpencodeRequestCosts(since: .distantPast) ?? [] : [])

    spendLedgerLock.lock()
    defer { spendLedgerLock.unlock() }
    var ledger = readSpendLedger()
    // A scan that finished first has already attributed and cleared some of `pending`, and adding
    // those again would double them. Increases recorded while the scan ran stay pending.
    let unclaimed = pending.filter { ledger.pendingClaudeExtra.contains($0) }
    ledger.add(days: SpendLedgerBuilder.claudeDays(increases: unclaimed, requests: claude))
    ledger.pendingClaudeExtra.removeAll { unclaimed.contains($0) }
    ledger.merge(.codex, days: codexExtra)
    ledger.merge(.opencode, days: opencode)
    ledger.lastScan = now
    if includeCodex { ledger.lastCodexScan = now }
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
