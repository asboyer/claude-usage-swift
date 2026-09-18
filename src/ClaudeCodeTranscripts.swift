import Foundation

/// Reads the Claude Code session transcripts this machine writes under `~/.claude/projects`.
/// Main-thread requests live in `<project>/<session>.jsonl`; a session's subagents write to
/// `<project>/<session>/subagents/agent-*.jsonl`, so the scan walks the tree rather than one level.
enum ClaudeCodeTranscripts {
    static let defaultWindowHours = 24

    static var projectsDirectory: URL {
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }

    // ISO8601DateFormatter is safe to parse from concurrently, and building one per line would
    // dominate the scan, so the two formats share one formatter each.
    private nonisolated(unsafe) static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private nonisolated(unsafe) static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parseTimestamp(_ value: String) -> Date? {
        return fractionalFormatter.date(from: value) ?? plainFormatter.date(from: value)
    }

    /// Returns every assistant request logged since `now` minus the window.
    static func recentRequests(windowHours: Int = defaultWindowHours, now: Date = Date()) -> [TranscriptRequest] {
        let cutoff = now.addingTimeInterval(-Double(windowHours) * 3600)
        var requests: [TranscriptRequest] = []
        var seenRequestIDs = Set<String>()

        for file in transcriptFiles(modifiedSince: cutoff) {
            for line in LineReader(url: file) {
                // Every record worth reading carries this type, so the scan skips the rest cheaply.
                guard line.contains("\"assistant\"") else { continue }
                guard
                    let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
                    let record = object as? [String: Any],
                    let request = parseRequest(record, cutoff: cutoff, seen: &seenRequestIDs)
                else { continue }
                requests.append(request)
            }
        }
        return requests
    }

    static func transcriptFiles(modifiedSince cutoff: Date) -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard
            let enumerator = FileManager.default.enumerator(
                at: projectsDirectory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
            )
        else { return [] }

        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            // A transcript untouched since the cutoff cannot hold a request inside the window.
            guard let modified = values?.contentModificationDate, modified >= cutoff else { continue }
            files.append(url)
        }
        return files
    }

    /// Returns nil when the record is not a billable in-window request, or is one already counted.
    /// A resumed session replays earlier records, so `requestId` is what keeps the count honest.
    private static func parseRequest(
        _ record: [String: Any], cutoff: Date, seen: inout Set<String>
    ) -> TranscriptRequest? {
        guard
            record["type"] as? String == "assistant",
            record["isApiErrorMessage"] as? Bool != true,
            let sessionID = record["sessionId"] as? String,
            let rawTimestamp = record["timestamp"] as? String,
            let timestamp = parseTimestamp(rawTimestamp),
            timestamp >= cutoff,
            let message = record["message"] as? [String: Any],
            let usage = message["usage"] as? [String: Any]
        else { return nil }

        if let requestID = record["requestId"] as? String {
            guard seen.insert(requestID).inserted else { return nil }
        }

        let totalCacheWrite = usage["cache_creation_input_tokens"] as? Int ?? 0
        let cacheCreation = usage["cache_creation"] as? [String: Any]
        var write5m = cacheCreation?["ephemeral_5m_input_tokens"] as? Int ?? 0
        let write1h = cacheCreation?["ephemeral_1h_input_tokens"] as? Int ?? 0
        // Older records report only the total; charge it at the 5-minute rate rather than drop it.
        if write5m + write1h == 0 {
            write5m = totalCacheWrite
        }

        return TranscriptRequest(
            sessionID: sessionID,
            timestamp: timestamp,
            model: message["model"] as? String,
            inputTokens: usage["input_tokens"] as? Int ?? 0,
            cacheWrite5mTokens: write5m,
            cacheWrite1hTokens: write1h,
            cacheReadTokens: usage["cache_read_input_tokens"] as? Int ?? 0,
            outputTokens: usage["output_tokens"] as? Int ?? 0,
            isSubagent: record["isSidechain"] as? Bool ?? false,
            agent: record["attributionAgent"] as? String,
            skill: record["attributionSkill"] as? String
        )
    }
}

/// Streams a file one line at a time. Transcripts reach tens of megabytes, so the whole
/// scan stays bounded by the chunk size rather than by the largest session on disk.
struct LineReader: Sequence, IteratorProtocol {
    private let handle: FileHandle?
    private let chunkSize: Int
    private var buffer = Data()
    private var reachedEnd = false

    init(url: URL, chunkSize: Int = 1 << 20) {
        self.handle = try? FileHandle(forReadingFrom: url)
        self.chunkSize = chunkSize
    }

    mutating func next() -> String? {
        guard let handle else { return nil }
        let newline = UInt8(ascii: "\n")
        while true {
            if let index = buffer.firstIndex(of: newline) {
                let line = buffer[buffer.startIndex..<index]
                buffer = buffer[buffer.index(after: index)...]
                if !line.isEmpty {
                    return String(decoding: line, as: UTF8.self)
                }
                continue
            }
            if reachedEnd {
                defer { buffer = Data() }
                if buffer.isEmpty {
                    try? handle.close()
                    return nil
                }
                return String(decoding: buffer, as: UTF8.self)
            }
            let chunk = (try? handle.read(upToCount: chunkSize)) ?? nil
            if let chunk, !chunk.isEmpty {
                buffer.append(chunk)
            } else {
                reachedEnd = true
            }
        }
    }
}
