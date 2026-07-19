import Foundation

public struct WidgetTaskSnapshot: Codable, Equatable, Sendable {
    public let title: String
    public let todayTokens: Int64
    public let colorIndex: Int?

    public init(title: String, todayTokens: Int64, colorIndex: Int? = nil) {
        self.title = title
        self.todayTokens = todayTokens
        self.colorIndex = colorIndex
    }
}

public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public let remainingPercent: Double
    public let resetsAt: Date?
    public let resetCreditsAvailable: Int?
    public let fetchedAt: Date
    public let todayTotalTokens: Int64?
    public let tasks: [WidgetTaskSnapshot]

    public init(
        remainingPercent: Double,
        resetsAt: Date?,
        resetCreditsAvailable: Int?,
        fetchedAt: Date,
        todayTotalTokens: Int64? = nil,
        tasks: [WidgetTaskSnapshot]
    ) {
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
        self.resetCreditsAvailable = resetCreditsAvailable
        self.fetchedAt = fetchedAt
        self.todayTotalTokens = todayTotalTokens
        self.tasks = tasks
    }
}

public struct WidgetSnapshotStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("CodexControlCenter", isDirectory: true)
        self.fileURL = fileURL ?? directory.appendingPathComponent("widget-snapshot.json")
    }

    public func write(snapshot: ProviderSnapshot, tasks: [TaskUsage]) throws {
        let weekly = snapshot.windows.first(where: { $0.kind == .weekly })
            ?? snapshot.windows.max(by: {
                ($0.windowDurationMinutes ?? 0) < ($1.windowDurationMinutes ?? 0)
            })
        let todayTasks = tasks.filter { $0.todayTokens > 0 }
        var groupedTokens: [String: Int64] = [:]
        for task in todayTasks {
            groupedTokens[task.displayTitle, default: 0] += task.todayTokens
        }
        let ranked = groupedTokens
            .map {
                WidgetTaskSnapshot(
                    title: $0.key,
                    todayTokens: $0.value,
                    colorIndex: TaskVisualIdentity.colorIndex(for: $0.key)
                )
            }
            .sorted { $0.todayTokens > $1.todayTokens }
            .prefix(6)
        let widgetSnapshot = WidgetSnapshot(
            remainingPercent: weekly?.remainingPercent ?? snapshot.lowestRemainingPercent ?? 0,
            resetsAt: weekly?.resetsAt,
            resetCreditsAvailable: snapshot.resetCreditsAvailable,
            fetchedAt: snapshot.fetchedAt,
            todayTotalTokens: todayTasks.reduce(Int64(0)) { $0 + $1.todayTokens },
            tasks: Array(ranked)
        )
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(widgetSnapshot).write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    public func read() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    public static func compactTaskTitle(_ rawTitle: String) -> String {
        var title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if let topicMessage = bestTranscriptUserMessage(in: title) {
            title = topicMessage
        }
        // Older snapshots may contain a title truncated in the middle of its
        // conversation URL, so matching only the complete label is deliberate.
        let continuationPattern = #"(?i)^Continuing\s+from\s+\[([^\]]+)\]"#
        if let expression = try? NSRegularExpression(pattern: continuationPattern),
           let match = expression.firstMatch(
                in: title,
                range: NSRange(title.startIndex..., in: title)
           ),
           match.numberOfRanges > 1,
           let capturedRange = Range(match.range(at: 1), in: title) {
            if let suffixRange = title.range(of: "):"),
               !title[suffixRange.upperBound...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty {
                title = String(title[suffixRange.upperBound...])
            } else {
                title = String(title[capturedRange])
            }
        } else {
            let markdownLinkPattern = #"\[([^\]]+)\]\([^)]+\)"#
            if let expression = try? NSRegularExpression(pattern: markdownLinkPattern) {
                let range = NSRange(title.startIndex..., in: title)
                title = expression.stringByReplacingMatches(
                    in: title,
                    range: range,
                    withTemplate: "$1"
                )
            }
        }

        title = title
            .replacingOccurrences(of: "## My request for Codex:", with: "")
            .trimmingCharacters(
                in: .whitespacesAndNewlines.union(
                    CharacterSet(charactersIn: "：:，,。；;！？!?-—")
                )
            )
        return summarizeTaskTitle(title)
    }

    private static func summarizeTaskTitle(_ title: String) -> String {
        if let dateTitle = compactDateTitle(title) {
            return dateTitle
        }

        if let opening = title.firstIndex(of: "「"),
           let closing = title[title.index(after: opening)...].firstIndex(of: "」") {
            let quoted = String(title[title.index(after: opening)..<closing])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !quoted.isEmpty {
                return truncateByVisualWidth(quoted, maximum: 24)
            }
        }

        let clauses = title
            .components(separatedBy: CharacterSet(charactersIn: "，,。；;！？!?\n"))
            .map(normalizeClause)
            .filter { !$0.isEmpty }

        guard !clauses.isEmpty else { return "未命名任务" }
        let genericThemes = Set(["工作流", "任务", "功能", "问题", "需求"])
        let best = clauses.max { left, right in
            semanticScore(left, genericThemes: genericThemes)
                < semanticScore(right, genericThemes: genericThemes)
        } ?? clauses[0]

        var summary = best
        if best != "工作流", !best.contains("工作流"), clauses.contains("工作流") {
            summary += "工作流"
        }
        return truncateByVisualWidth(summary, maximum: 24)
    }

    private static func compactDateTitle(_ title: String) -> String? {
        let pattern = #"^(\d{4})-(\d{2})-(\d{2})(?:-(\d{4})-(\d{2})-(\d{2}))?$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: title,
                range: NSRange(title.startIndex..., in: title)
              ),
              let startMonth = integerCapture(2, match: match, text: title),
              let startDay = integerCapture(3, match: match, text: title) else {
            return nil
        }

        guard let endYear = integerCapture(4, match: match, text: title),
              let endMonth = integerCapture(5, match: match, text: title),
              let endDay = integerCapture(6, match: match, text: title),
              let startYear = integerCapture(1, match: match, text: title) else {
            return "\(startMonth) 月 \(startDay) 日任务"
        }

        if startYear == endYear, startMonth == endMonth, startDay == endDay {
            return "\(startMonth) 月 \(startDay) 日任务"
        }
        if startYear == endYear, startMonth == endMonth {
            return "\(startMonth) 月 \(startDay)–\(endDay) 日任务"
        }
        return "\(startMonth) 月 \(startDay) 日–\(endMonth) 月 \(endDay) 日任务"
    }

    private static func integerCapture(
        _ index: Int,
        match: NSTextCheckingResult,
        text: String
    ) -> Int? {
        guard match.numberOfRanges > index,
              match.range(at: index).location != NSNotFound,
              let range = Range(match.range(at: index), in: text) else {
            return nil
        }
        return Int(text[range])
    }

    private static func normalizeClause(_ rawClause: String) -> String {
        var clause = rawClause.trimmingCharacters(in: .whitespacesAndNewlines)
        let leadingPhrases = [
            "我们来做一个", "我们来做", "请帮我", "我的第一个", "我需要",
            "我想要", "需要调用", "帮我", "我想", "需要", "调用", "我的", "请"
        ]
        let trailingPhrases = [
            "准备好后告诉我", "准备好后跟我说", "完成后告诉我", "告诉我", "可以吗", "怎么样", "一下"
        ]

        for phrase in leadingPhrases where clause.hasPrefix(phrase) {
            clause.removeFirst(phrase.count)
            break
        }
        for phrase in trailingPhrases where clause.hasSuffix(phrase) {
            clause.removeLast(phrase.count)
            break
        }
        return clause.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private static func semanticScore(_ text: String, genericThemes: Set<String>) -> Int {
        visualWidth(text) - (genericThemes.contains(text) ? 4 : 0)
    }

    private static func truncateByVisualWidth(_ text: String, maximum: Int) -> String {
        guard visualWidth(text) > maximum else { return text }
        var result = ""
        var used = 0
        for character in text {
            let width = character.unicodeScalars.allSatisfy { $0.value < 128 } ? 1 : 2
            guard used + width <= maximum - 1 else { break }
            result.append(character)
            used += width
        }
        return result + "…"
    }

    private static func visualWidth(_ text: String) -> Int {
        text.reduce(0) { width, character in
            width + (character.unicodeScalars.allSatisfy { $0.value < 128 } ? 1 : 2)
        }
    }

    private static func bestTranscriptUserMessage(in title: String) -> String? {
        let markerPattern = #"(?m)^\[\d+\]\s+user:\s*"#
        guard let markerExpression = try? NSRegularExpression(pattern: markerPattern) else {
            return nil
        }
        let fullRange = NSRange(title.startIndex..., in: title)
        let markers = markerExpression.matches(in: title, range: fullRange)
        guard !markers.isEmpty else {
            return nil
        }

        let anyMarkerPattern = #"(?m)^\[\d+\]\s+"#
        let anyMarker = try? NSRegularExpression(pattern: anyMarkerPattern)
        var messages: [String] = []
        if let firstMarkerRange = Range(markers[0].range, in: title) {
            var initialRequest = String(title[..<firstMarkerRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let suffix = initialRequest.range(of: "):") {
                initialRequest = String(initialRequest[suffix.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !initialRequest.isEmpty { messages.append(initialRequest) }
        }
        for marker in markers {
            guard let markerRange = Range(marker.range, in: title) else { continue }
            let tail = String(title[markerRange.upperBound...])
            let next = anyMarker?.firstMatch(in: tail, range: NSRange(tail.startIndex..., in: tail))
            let message: String
            if let next, let nextRange = Range(next.range, in: tail) {
                message = String(tail[..<nextRange.lowerBound])
            } else {
                message = tail
            }
            let cleaned = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { messages.append(cleaned) }
        }
        return messages.max { transcriptTopicScore($0) < transcriptTopicScore($1) }
    }

    private static func transcriptTopicScore(_ message: String) -> Int {
        let compact = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let generic = ["好了", "改", "去做", "同意", "可以", "我怎么没看到", "颜色在哪里"]
        var score = min(visualWidth(compact), 240)
        if generic.contains(where: { compact == $0 || compact.hasPrefix($0) }) { score -= 160 }
        if compact.contains("「") && compact.contains("」") { score += 100 }
        let topicTerms = ["实现", "修复", "设计", "构建", "整理", "分析", "测试", "部署", "配置"]
        score += topicTerms.filter(compact.contains).count * 16
        return score
    }
}
