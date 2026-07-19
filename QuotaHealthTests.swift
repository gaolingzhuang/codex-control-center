import Foundation
import Testing
@testable import CodexControlCenterCore

@Test func quotaHealthUsesExpectedBoundaries() {
    #expect(QuotaHealth.evaluate(remainingPercent: 100) == .healthy)
    #expect(QuotaHealth.evaluate(remainingPercent: 75) == .healthy)
    #expect(QuotaHealth.evaluate(remainingPercent: 74.9) == .moderate)
    #expect(QuotaHealth.evaluate(remainingPercent: 50) == .moderate)
    #expect(QuotaHealth.evaluate(remainingPercent: 49.9) == .warning)
    #expect(QuotaHealth.evaluate(remainingPercent: 25) == .warning)
    #expect(QuotaHealth.evaluate(remainingPercent: 24.9) == .critical)
    #expect(QuotaHealth.evaluate(remainingPercent: 0) == .critical)
}

@Test func usageWindowExposesQuotaHealth() {
    let window = UsageWindow(
        kind: .weekly,
        label: "每周",
        usedPercent: 80,
        windowDurationMinutes: 10_080,
        resetsAt: nil
    )

    #expect(window.quotaHealth == .critical)
}

@Test func weeklyPaceMakesRemainingStatusOneLevelMoreCautious() {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let window = UsageWindow(
        kind: .weekly,
        label: "每周",
        usedPercent: 45,
        windowDurationMinutes: 10_080,
        resetsAt: now.addingTimeInterval(6.5 * 24 * 60 * 60)
    )

    let assessment = window.assessment(at: now)
    #expect(window.quotaHealth == .moderate)
    #expect(assessment.health == .warning)
    #expect(assessment.statusText == "需要注意")
    #expect(assessment.detailText.contains("耗尽"))
}

@Test func sustainableWeeklyPaceKeepsHealthyStatus() {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let window = UsageWindow(
        kind: .weekly,
        label: "每周",
        usedPercent: 20,
        windowDurationMinutes: 10_080,
        resetsAt: now.addingTimeInterval(5 * 24 * 60 * 60)
    )

    let assessment = window.assessment(at: now)
    #expect(assessment.health == .healthy)
    #expect(assessment.statusText == "充足")
}
