import Foundation
import Testing
@testable import CodexControlCenterCore

@Test func readsTaskRankingFromCodexStateDatabase() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let database = directory.appendingPathComponent("state.sqlite")

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    process.arguments = [database.path, """
        CREATE TABLE threads (
          id TEXT, title TEXT, cwd TEXT, tokens_used INTEGER,
          updated_at INTEGER, has_user_event INTEGER
        );
        INSERT INTO threads VALUES ('a', '轻量任务', '/tmp/alpha', 1200, 100, 1);
        INSERT INTO threads VALUES ('b', '主要任务', '/tmp/beta', 9800, 200, 1);
        INSERT INTO threads VALUES ('c', '', '/tmp/gamma', 50000, 300, 0);
        """]
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)

    let tasks = try CodexTaskUsageReader(databaseURL: database, sessionsURLs: [], limit: 10)
        .fetch(weekStart: Date(timeIntervalSince1970: 0))
    #expect(tasks.count == 2)
    #expect(tasks[0].title == "主要任务")
    #expect(tasks[0].totalTokens == 9800)
    #expect(tasks[0].projectName == "beta")
}

@Test func defaultReaderIncludesEveryRecordedTaskInTotals() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let database = directory.appendingPathComponent("state.sqlite")

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    process.arguments = [database.path, """
        CREATE TABLE threads (
          id TEXT, title TEXT, cwd TEXT, tokens_used INTEGER,
          updated_at INTEGER, has_user_event INTEGER
        );
        WITH RECURSIVE sequence(value) AS (
          SELECT 1 UNION ALL SELECT value + 1 FROM sequence WHERE value < 501
        )
        INSERT INTO threads
        SELECT printf('task-%03d', value), printf('任务 %03d', value), '/tmp/project', value, value, 1
        FROM sequence;
        """]
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)

    let tasks = try CodexTaskUsageReader(databaseURL: database, sessionsURLs: [])
        .fetch(weekStart: Date(timeIntervalSince1970: 0))
    #expect(tasks.count == 501)
    #expect(TaskUsageMetrics.totalTokens(in: tasks, for: .all) == 125_751)
}

@Test func aggregatesTodayAndQuotaWeekFromTokenEvents() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sessions = directory.appendingPathComponent("sessions", isDirectory: true)
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let database = directory.appendingPathComponent("state.sqlite")
    let threadID = "019f0000-0000-7000-8000-000000000001"

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    process.arguments = [database.path, """
        CREATE TABLE threads (
          id TEXT, title TEXT, cwd TEXT, tokens_used INTEGER,
          updated_at INTEGER, has_user_event INTEGER
        );
        INSERT INTO threads VALUES ('\(threadID)', '测试任务', '/tmp/project', 400, 1784347200, 0);
        """]
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)

    let log = [
        #"{"timestamp":"2026-07-15T12:00:00.125Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":100}}}}"#,
        #"{"timestamp":"2026-07-16T12:00:00.250Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":250}}}}"#,
        #"{"timestamp":"2026-07-18T01:00:00.500Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":400}}}}"#
    ].joined(separator: "\n") + "\n"
    let logURL = sessions.appendingPathComponent("rollout-\(threadID).jsonl")
    try Data(log.utf8).write(to: logURL)

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let formatter = ISO8601DateFormatter()
    let now = formatter.date(from: "2026-07-18T04:00:00Z")!
    let weekStart = formatter.date(from: "2026-07-16T00:00:00Z")!
    let tasks = try CodexTaskUsageReader(
        databaseURL: database,
        sessionsURLs: [sessions],
        limit: 10
    ).fetch(weekStart: weekStart, now: now, calendar: calendar)

    #expect(tasks.count == 1)
    #expect(tasks[0].todayTokens == 150)
    #expect(tasks[0].weeklyTokens == 300)
    #expect(tasks[0].totalTokens == 400)
}
