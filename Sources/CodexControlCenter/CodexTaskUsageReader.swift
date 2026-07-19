import Foundation

public final class CodexTaskUsageReader: @unchecked Sendable {
    public let databaseURL: URL
    public let limit: Int?
    private let sessionsURLs: [URL]
    private let lock = NSLock()
    private var fileCache: [String: CachedSession] = [:]

    public init(
        databaseURL: URL? = nil,
        sessionsURLs: [URL]? = nil,
        limit: Int? = nil
    ) {
        let codexHome = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        self.databaseURL = databaseURL ?? codexHome.appendingPathComponent("state_5.sqlite")
        self.sessionsURLs = sessionsURLs ?? [
            codexHome.appendingPathComponent("sessions", isDirectory: true),
            codexHome.appendingPathComponent("archived_sessions", isDirectory: true)
        ]
        self.limit = limit
    }

    public func fetch(
        weekStart: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> [TaskUsage] {
        let rows = try fetchTaskRows()
        guard !rows.isEmpty else { return [] }

        let todayStart = calendar.startOfDay(for: now)
        let scanStart = min(todayStart, weekStart)
        let recentUsage = scanRecentUsage(since: scanStart, todayStart: todayStart, weekStart: weekStart, now: now)

        return rows.map { row in
            let usage = recentUsage[row.id] ?? .zero
            return TaskUsage(
                id: row.id,
                title: row.title.isEmpty ? "未命名任务" : row.title,
                projectPath: row.cwd,
                todayTokens: usage.today,
                weeklyTokens: usage.weekly,
                totalTokens: row.tokens_used,
                updatedAt: Date(timeIntervalSince1970: TimeInterval(row.updated_at))
            )
        }
    }

    private func fetchTaskRows() throws -> [TaskRow] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return [] }
        let data = try runSQLite(query: Self.query(limit: limit))
        guard !data.isEmpty else { return [] }
        return try JSONDecoder().decode([TaskRow].self, from: data)
    }

    private func scanRecentUsage(
        since scanStart: Date,
        todayStart: Date,
        weekStart: Date,
        now: Date
    ) -> [String: RangeTotals] {
        let files = recentSessionFiles(since: scanStart)
        var result: [String: RangeTotals] = [:]

        for file in files {
            guard let session = cachedSession(for: file) else { continue }
            var totals = result[session.threadID] ?? .zero
            for event in session.events where event.timestamp <= now {
                if event.timestamp >= todayStart { totals.today += event.tokens }
                if event.timestamp >= weekStart { totals.weekly += event.tokens }
            }
            result[session.threadID] = totals
        }
        return result
    }

    private func recentSessionFiles(since date: Date) -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        var files: [URL] = []
        for root in sessionsURLs {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(forKeys: keys),
                      values.isRegularFile == true,
                      let modified = values.contentModificationDate,
                      modified >= date else { continue }
                files.append(url)
            }
        }
        return files
    }

    private func cachedSession(for url: URL) -> CachedSession? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              let modified = attributes[.modificationDate] as? Date else { return nil }
        let signature = FileSignature(size: size.int64Value, modifiedAt: modified.timeIntervalSince1970)

        lock.lock()
        if let cached = fileCache[url.path], cached.signature == signature {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let parsed = parseSession(at: url, signature: signature) else { return nil }
        lock.lock()
        fileCache[url.path] = parsed
        lock.unlock()
        return parsed
    }

    private func parseSession(at url: URL, signature: FileSignature) -> CachedSession? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        var threadID = String(url.deletingPathExtension().lastPathComponent.suffix(36))
        var events: [TokenEvent] = []
        var previousTotal: Int64 = 0
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standardFormatter = ISO8601DateFormatter()

        for rawLine in data.split(separator: 0x0A) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(rawLine)) as? [String: Any],
                  let type = object["type"] as? String else { continue }

            if type == "session_meta",
               let payload = object["payload"] as? [String: Any],
               let id = payload["id"] as? String ?? payload["session_id"] as? String {
                threadID = id
                continue
            }

            guard type == "event_msg",
                  let payload = object["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let totalUsage = info["total_token_usage"] as? [String: Any],
                  let currentTotal = int64(totalUsage["total_tokens"]),
                  let timestampString = object["timestamp"] as? String,
                  let timestamp = fractionalFormatter.date(from: timestampString)
                    ?? standardFormatter.date(from: timestampString) else { continue }

            let delta = currentTotal >= previousTotal ? currentTotal - previousTotal : currentTotal
            previousTotal = currentTotal
            if delta > 0 { events.append(TokenEvent(timestamp: timestamp, tokens: delta)) }
        }
        return CachedSession(threadID: threadID, signature: signature, events: events)
    }

    private func runSQLite(query: String) throws -> Data {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-json", databaseURL.path, query]
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8) ?? "读取任务数据库失败"
            throw UsageError.launchFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return data
    }

    private static func query(limit: Int?) -> String {
        let limitClause = limit.map { "LIMIT \(max(1, $0))" } ?? ""
        return """
        SELECT id, title, cwd, tokens_used, updated_at
        FROM threads
        WHERE tokens_used > 0 AND title <> ''
        ORDER BY tokens_used DESC, updated_at DESC
        \(limitClause);
        """
    }

    private func int64(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber { return number.int64Value }
        if let string = value as? String { return Int64(string) }
        return nil
    }
}

private struct TaskRow: Decodable {
    let id: String
    let title: String
    let cwd: String
    let tokens_used: Int64
    let updated_at: Int64
}

private struct FileSignature: Equatable, Sendable {
    let size: Int64
    let modifiedAt: TimeInterval
}

private struct CachedSession: Sendable {
    let threadID: String
    let signature: FileSignature
    let events: [TokenEvent]
}

private struct TokenEvent: Sendable {
    let timestamp: Date
    let tokens: Int64
}

private struct RangeTotals: Sendable {
    var today: Int64
    var weekly: Int64
    static let zero = RangeTotals(today: 0, weekly: 0)
}
