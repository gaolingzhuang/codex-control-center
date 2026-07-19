import Foundation

public enum QuotaHealth: String, Codable, CaseIterable, Sendable {
    case healthy
    case moderate
    case warning
    case critical

    public static func evaluate(remainingPercent: Double) -> Self {
        if remainingPercent < 25 { return .critical }
        if remainingPercent < 50 { return .warning }
        if remainingPercent < 75 { return .moderate }
        return .healthy
    }

    public var displayName: String {
        switch self {
        case .healthy: "充足"
        case .moderate: "尚可"
        case .warning: "需要注意"
        case .critical: "紧张"
        }
    }
}

public struct QuotaAssessment: Equatable, Sendable {
    public let health: QuotaHealth
    public let statusText: String
    public let detailText: String
    public let projectedExhaustion: Date?
}

public enum UsageWindowKind: String, Codable, Sendable {
    case session
    case weekly
    case other

    public var displayName: String {
        switch self {
        case .session: "5 小时"
        case .weekly: "每周"
        case .other: "额度"
        }
    }
}

public struct UsageWindow: Codable, Equatable, Sendable {
    public let kind: UsageWindowKind
    public let label: String
    public let usedPercent: Double
    public let windowDurationMinutes: Int?
    public let resetsAt: Date?

    public var remainingPercent: Double {
        max(0, min(100, 100 - usedPercent))
    }

    public var quotaHealth: QuotaHealth {
        .evaluate(remainingPercent: remainingPercent)
    }

    public func assessment(at now: Date) -> QuotaAssessment {
        let remaining = remainingPercent
        let used = max(0, min(100, usedPercent))
        let amountHealth = QuotaHealth.evaluate(remainingPercent: remaining)

        guard let resetsAt,
              let windowDurationMinutes,
              windowDurationMinutes > 0,
              used > 0 else {
            return QuotaAssessment(
                health: amountHealth,
                statusText: amountHealth.displayName,
                detailText: amountHealth == .healthy ? "剩余额度处于正常范围" : "请留意剩余额度",
                projectedExhaustion: nil
            )
        }

        let duration = TimeInterval(windowDurationMinutes * 60)
        let cycleStart = resetsAt.addingTimeInterval(-duration)
        let elapsed = min(max(now.timeIntervalSince(cycleStart), 0), duration)
        guard elapsed >= 15 * 60 else {
            return QuotaAssessment(
                health: amountHealth,
                statusText: amountHealth.displayName,
                detailText: "额度周期刚开始，正在观察消耗速度",
                projectedExhaustion: nil
            )
        }

        let timeToExhaust = elapsed * remaining / used
        let projectedExhaustion = now.addingTimeInterval(timeToExhaust)
        let runsOutBeforeReset = projectedExhaustion < resetsAt
        let urgentHorizon = min(24 * 60 * 60, duration * 0.20)
        let earlyBy = resetsAt.timeIntervalSince(projectedExhaustion)
        let paceIsCritical = runsOutBeforeReset
            && (timeToExhaust <= urgentHorizon || earlyBy >= duration * 0.15)
        let paceIsWarning = runsOutBeforeReset

        var health = amountHealth
        if paceIsWarning || paceIsCritical {
            // Pace is supporting context, so it can make the remaining-amount
            // status one level more cautious without replacing that model.
            switch amountHealth {
            case .healthy: health = .moderate
            case .moderate: health = .warning
            case .warning: health = .critical
            case .critical: health = .critical
            }
        }

        let detailText: String
        if runsOutBeforeReset {
            detailText = "按当前速度预计\(Self.durationCaption(timeToExhaust))后耗尽"
        } else if health == .healthy {
            detailText = "按当前速度可持续到本次重置"
        } else {
            detailText = "已使用 \(Int(used.rounded()))%，请留意后续消耗"
        }

        return QuotaAssessment(
            health: health,
            statusText: health.displayName,
            detailText: detailText,
            projectedExhaustion: projectedExhaustion
        )
    }

    private static func durationCaption(_ interval: TimeInterval) -> String {
        if interval < 60 * 60 { return "不到 1 小时" }
        if interval < 48 * 60 * 60 {
            return "约 \(max(1, Int((interval / 3600).rounded()))) 小时"
        }
        return "约 \(max(1, Int((interval / 86_400).rounded()))) 天"
    }
}

public struct ProviderSnapshot: Codable, Equatable, Sendable {
    public let providerID: String
    public let providerName: String
    public let plan: String?
    public let windows: [UsageWindow]
    public let creditsBalance: String?
    public let resetCreditsAvailable: Int?
    public let fetchedAt: Date
    public let source: String

    public var lowestRemainingPercent: Double? {
        windows.map(\.remainingPercent).min()
    }
}

public struct TaskUsage: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let projectPath: String
    public let todayTokens: Int64
    public let weeklyTokens: Int64
    public let totalTokens: Int64
    public let updatedAt: Date

    public var projectName: String {
        URL(fileURLWithPath: projectPath).lastPathComponent
    }

    public var displayTitle: String {
        WidgetSnapshotStore.compactTaskTitle(title)
    }

    public func tokens(for range: TaskUsageRange) -> Int64 {
        switch range {
        case .today: todayTokens
        case .weekly: weeklyTokens
        case .all: totalTokens
        }
    }
}

public enum TaskUsageRange: String, CaseIterable, Identifiable, Sendable {
    case today
    case weekly
    case all

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .today: "今日"
        case .weekly: "本周"
        case .all: "全部"
        }
    }
}

public enum TaskUsageMetrics {
    public static func totalTokens(in tasks: [TaskUsage], for range: TaskUsageRange) -> Int64 {
        tasks.reduce(0) { partial, task in
            let (sum, overflow) = partial.addingReportingOverflow(task.tokens(for: range))
            return overflow ? Int64.max : sum
        }
    }

    public static func share(tokens: Int64, of totalTokens: Int64) -> Double {
        guard tokens > 0, totalTokens > 0 else { return 0 }
        return min(1, max(0, Double(tokens) / Double(totalTokens)))
    }
}

public enum TaskVisualIdentity {
    public static let paletteSize = 6

    public static func colorIndex(for title: String) -> Int {
        // Swift's hashValue changes between launches. FNV-1a keeps a task's
        // visual identity stable across refreshes, processes and WidgetKit.
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in title.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Int(hash % UInt64(paletteSize))
    }
}

struct HistoryRecord: Codable, Equatable, Sendable {
    let snapshot: ProviderSnapshot
}

enum UsageError: LocalizedError {
    case codexNotFound
    case launchFailed(String)
    case timedOut
    case malformedResponse
    case rpc(String)
    case noRateLimits

    var errorDescription: String? {
        switch self {
        case .codexNotFound:
            "未找到 Codex。请先安装或登录 Codex CLI / Codex App。"
        case .launchFailed(let reason):
            "无法启动 Codex：\(reason)"
        case .timedOut:
            "读取额度超时，请确认 Codex 已登录。"
        case .malformedResponse:
            "Codex 返回了无法识别的数据。"
        case .rpc(let message):
            "Codex 接口错误：\(message)"
        case .noRateLimits:
            "当前账户没有返回可显示的额度窗口。"
        }
    }
}
