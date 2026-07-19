import Foundation
import Testing
@testable import CodexControlCenterCore

@Test func writesCompactRankedWidgetSnapshot() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = WidgetSnapshotStore(fileURL: root.appendingPathComponent("snapshot.json"))
    let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let reset = fetchedAt.addingTimeInterval(3600)
    let snapshot = ProviderSnapshot(
        providerID: "codex",
        providerName: "Codex",
        plan: "plus",
        windows: [UsageWindow(
            kind: .weekly,
            label: "每周",
            usedPercent: 72,
            windowDurationMinutes: 10_080,
            resetsAt: reset
        )],
        creditsBalance: nil,
        resetCreditsAvailable: 1,
        fetchedAt: fetchedAt,
        source: "test"
    )
    let tasks = [
        makeTask(id: "a", title: "低", today: 10),
        makeTask(id: "b", title: "高", today: 30),
        makeTask(id: "c", title: "零", today: 0),
        makeTask(id: "d", title: "中", today: 20)
    ]

    try store.write(snapshot: snapshot, tasks: tasks)
    let stored = try #require(store.read())

    #expect(stored.remainingPercent == 28)
    #expect(stored.resetsAt == reset)
    #expect(stored.resetCreditsAvailable == 1)
    #expect(stored.todayTotalTokens == 60)
    #expect(stored.tasks.map(\.title) == ["高", "中", "低"])
    #expect(stored.tasks.allSatisfy { $0.colorIndex != nil })
}

@Test func compactsImportedConversationTitlesForTheWidget() {
    let imported = "Continuing from [示例额度任务](chatgpt-conversation://example-id)"
    let truncated = "Continuing from [示例额度任务](chatgpt-conversation://example-id"
    let markdown = "[示例功能规划](https://example.com/task)"

    #expect(WidgetSnapshotStore.compactTaskTitle(imported) == "示例额度任务")
    #expect(WidgetSnapshotStore.compactTaskTitle(truncated) == "示例额度任务")
    #expect(WidgetSnapshotStore.compactTaskTitle(markdown) == "示例功能规划")
    #expect(WidgetSnapshotStore.compactTaskTitle("  普通任务  ") == "普通任务")
    #expect(
        WidgetSnapshotStore.compactTaskTitle("请帮我梳理一套数据处理流程，完成后告诉我")
            == "梳理一套数据处理流程"
    )
    #expect(WidgetSnapshotStore.compactTaskTitle("2026-07-15") == "7 月 15 日任务")
    #expect(WidgetSnapshotStore.compactTaskTitle("2026-07-15-2026-07-15") == "7 月 15 日任务")
    #expect(WidgetSnapshotStore.compactTaskTitle("2026-07-15-2026-07-18") == "7 月 15–18 日任务")
    #expect(WidgetSnapshotStore.compactTaskTitle("这是一个特别特别特别特别特别特别长的任务名称") == "这是一个特别特别特别特…")
    #expect(
        WidgetSnapshotStore.compactTaskTitle(
            "Continuing from [示例任务](chatgpt-conversation://example-id): 开始搭建一个 macOS「示例控制中心」"
        ) == "示例控制中心"
    )
    #expect(
        WidgetSnapshotStore.compactTaskTitle(
            """
            Continuing from [示例任务](chatgpt-conversation://example-id): 初始需求

            [2] user: 第一个修改

            [3] assistant: 已处理

            [4] user: 任务说明显示太长了

            [5] assistant: 正在修改
            """
        ) == "任务说明显示太长了"
    )
    #expect(
        WidgetSnapshotStore.compactTaskTitle(
            """
            Continuing from [示例任务](chatgpt-conversation://example-id): 开始搭建一个 macOS「示例控制中心」

            [2] user: 去做

            [3] user: 我怎么没看到
            """
        ) == "示例控制中心"
    )
}

@Test func widgetCombinesTasksWithTheSameSummarizedTitle() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = WidgetSnapshotStore(fileURL: root.appendingPathComponent("snapshot.json"))
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let snapshot = ProviderSnapshot(
        providerID: "codex",
        providerName: "Codex",
        plan: nil,
        windows: [UsageWindow(
            kind: .weekly,
            label: "每周",
            usedPercent: 10,
            windowDurationMinutes: 10_080,
            resetsAt: now.addingTimeInterval(3600)
        )],
        creditsBalance: nil,
        resetCreditsAvailable: nil,
        fetchedAt: now,
        source: "test"
    )
    let tasks = [
        makeTask(id: "a", title: "开始搭建「示例控制中心」", today: 20),
        makeTask(id: "b", title: "继续修改「示例控制中心」", today: 30)
    ]

    try store.write(snapshot: snapshot, tasks: tasks)
    let stored = try #require(store.read())
    #expect(stored.tasks.count == 1)
    #expect(stored.tasks[0].title == "示例控制中心")
    #expect(stored.tasks[0].todayTokens == 50)
}

private func makeTask(id: String, title: String, today: Int64) -> TaskUsage {
    TaskUsage(
        id: id,
        title: title,
        projectPath: "/tmp/project",
        todayTokens: today,
        weeklyTokens: today,
        totalTokens: today,
        updatedAt: .distantPast
    )
}
