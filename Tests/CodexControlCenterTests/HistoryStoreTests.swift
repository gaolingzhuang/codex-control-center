import Foundation
import Testing
@testable import CodexControlCenterCore

@Test func appendsAndSummarizesHistory() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = HistoryStore(directoryURL: directory)
    let snapshot = ProviderSnapshot(
        providerID: "codex",
        providerName: "Codex",
        plan: "plus",
        windows: [UsageWindow(
            kind: .weekly,
            label: "每周",
            usedPercent: 51,
            windowDurationMinutes: 10080,
            resetsAt: nil
        )],
        creditsBalance: "0",
        resetCreditsAvailable: 1,
        fetchedAt: Date(),
        source: "test"
    )

    try store.append(snapshot)
    try store.append(snapshot)

    #expect(store.records().count == 2)
    #expect(store.summary().todayCount == 2)
    #expect(store.summary().weekLowestRemaining == 49)
}
