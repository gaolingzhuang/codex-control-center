import Foundation
import Testing
@testable import CodexControlCenterCore

@Test func taskSharesUseTheSelectedPeriodsTotal() {
    let tasks = [
        makeMetricsTask(id: "a", today: 60, weekly: 90, total: 100),
        makeMetricsTask(id: "b", today: 40, weekly: 210, total: 300)
    ]

    #expect(TaskUsageMetrics.totalTokens(in: tasks, for: .today) == 100)
    #expect(TaskUsageMetrics.totalTokens(in: tasks, for: .weekly) == 300)
    #expect(TaskUsageMetrics.totalTokens(in: tasks, for: .all) == 400)
    #expect(TaskUsageMetrics.share(tokens: 60, of: 100) == 0.6)
    #expect(TaskUsageMetrics.share(tokens: 90, of: 300) == 0.3)
    #expect(TaskUsageMetrics.share(tokens: 100, of: 400) == 0.25)
}

@Test func taskVisualIdentityIsStableAndUsesTheAvailablePalette() {
    let title = "Codex 控制中心"
    let first = TaskVisualIdentity.colorIndex(for: title)
    let second = TaskVisualIdentity.colorIndex(for: title)

    #expect(first == second)
    #expect((0..<TaskVisualIdentity.paletteSize).contains(first))
}

private func makeMetricsTask(
    id: String,
    today: Int64,
    weekly: Int64,
    total: Int64
) -> TaskUsage {
    TaskUsage(
        id: id,
        title: id,
        projectPath: "/tmp/project",
        todayTokens: today,
        weeklyTokens: weekly,
        totalTokens: total,
        updatedAt: .distantPast
    )
}
