import Foundation

enum CodexResponseParser {
    static func parse(data: Data, fetchedAt: Date = Date()) throws -> ProviderSnapshot {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw UsageError.malformedResponse }

        if let error = root["error"] as? [String: Any] {
            throw UsageError.rpc(error["message"] as? String ?? "未知错误")
        }

        guard
            let result = root["result"] as? [String: Any],
            let limits = result["rateLimits"] as? [String: Any]
        else { throw UsageError.malformedResponse }

        var windows: [UsageWindow] = []
        appendWindow(from: limits["primary"], fallbackLabel: "主要额度", to: &windows)
        appendWindow(from: limits["secondary"], fallbackLabel: "次要额度", to: &windows)

        guard !windows.isEmpty else { throw UsageError.noRateLimits }

        // Sort short rolling windows before weekly/long windows.
        windows.sort {
            ($0.windowDurationMinutes ?? .max) < ($1.windowDurationMinutes ?? .max)
        }

        let credits = limits["credits"] as? [String: Any]
        let balance = credits?["balance"] as? String
        let plan = limits["planType"] as? String
        let resetCredits = result["rateLimitResetCredits"] as? [String: Any]
        let resetCount = number(resetCredits?["availableCount"]).map(Int.init)

        return ProviderSnapshot(
            providerID: "codex",
            providerName: "Codex",
            plan: plan,
            windows: windows,
            creditsBalance: balance,
            resetCreditsAvailable: resetCount,
            fetchedAt: fetchedAt,
            source: "codex app-server"
        )
    }

    private static func appendWindow(
        from rawValue: Any?,
        fallbackLabel: String,
        to windows: inout [UsageWindow]
    ) {
        guard
            let raw = rawValue as? [String: Any],
            let used = number(raw["usedPercent"])
        else { return }

        let duration = number(raw["windowDurationMins"]).map(Int.init)
        let reset = number(raw["resetsAt"]).map(Date.init(timeIntervalSince1970:))
        let kind: UsageWindowKind
        if let duration, duration <= 12 * 60 {
            kind = .session
        } else if let duration, duration >= 5 * 24 * 60 {
            kind = .weekly
        } else {
            kind = .other
        }

        let label = kind == .other ? fallbackLabel : kind.displayName
        windows.append(UsageWindow(
            kind: kind,
            label: label,
            usedPercent: used,
            windowDurationMinutes: duration,
            resetsAt: reset
        ))
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
}
