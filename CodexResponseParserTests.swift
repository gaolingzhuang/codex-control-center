import Foundation
import Testing
@testable import CodexControlCenterCore

@Test func parsesSessionAndWeeklyWindowsByDuration() throws {
    let json = #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":81,"windowDurationMins":300,"resetsAt":1784780000},"secondary":{"usedPercent":40,"windowDurationMins":10080,"resetsAt":1784900000},"credits":{"balance":"12.5"},"planType":"plus"},"rateLimitResetCredits":{"availableCount":3}}}"#
    let snapshot = try CodexResponseParser.parse(data: Data(json.utf8))

    #expect(snapshot.windows.count == 2)
    #expect(snapshot.windows[0].kind == .session)
    #expect(snapshot.windows[0].remainingPercent == 19)
    #expect(snapshot.windows[1].kind == .weekly)
    #expect(snapshot.creditsBalance == "12.5")
    #expect(snapshot.resetCreditsAvailable == 3)
}

@Test func acceptsAccountsWithOnlyAWeeklyWindow() throws {
    let json = #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":51,"windowDurationMins":10080,"resetsAt":1784780527},"secondary":null,"credits":{"balance":"0"},"planType":"plus"},"rateLimitResetCredits":{"availableCount":1}}}"#
    let snapshot = try CodexResponseParser.parse(data: Data(json.utf8))

    #expect(snapshot.windows.count == 1)
    #expect(snapshot.windows[0].kind == .weekly)
    #expect(snapshot.lowestRemainingPercent == 49)
}

@Test func rejectsMissingRateLimits() {
    let json = #"{"id":2,"result":{}}"#
    #expect(throws: UsageError.self) {
        try CodexResponseParser.parse(data: Data(json.utf8))
    }
}
