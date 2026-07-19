import Foundation

public struct HistorySummary: Sendable {
    public let todayCount: Int
    public let weekCount: Int
    public let todayLowestRemaining: Double?
    public let weekLowestRemaining: Double?
}

public final class HistoryStore: @unchecked Sendable {
    public let directoryURL: URL
    public let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock = NSLock()

    public init(directoryURL: URL? = nil) {
        let defaultDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("CodexControlCenter", isDirectory: true)
        self.directoryURL = directoryURL ?? defaultDirectory
        self.fileURL = self.directoryURL.appendingPathComponent("history.jsonl")
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func append(_ snapshot: ProviderSnapshot) throws {
        lock.lock()
        defer { lock.unlock() }
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        var line = try encoder.encode(HistoryRecord(snapshot: snapshot))
        line.append(0x0A)

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try line.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
            return
        }
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    func records() -> [HistoryRecord] {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return data.split(separator: 0x0A).compactMap {
            try? decoder.decode(HistoryRecord.self, from: Data($0))
        }
    }

    public func summary(now: Date = Date(), calendar: Calendar = .current) -> HistorySummary {
        let all = records()
        let today = all.filter { calendar.isDate($0.snapshot.fetchedAt, inSameDayAs: now) }
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now)
        let week = all.filter {
            weekInterval?.contains($0.snapshot.fetchedAt) == true
        }
        return HistorySummary(
            todayCount: today.count,
            weekCount: week.count,
            todayLowestRemaining: today.compactMap(\.snapshot.lowestRemainingPercent).min(),
            weekLowestRemaining: week.compactMap(\.snapshot.lowestRemainingPercent).min()
        )
    }
}
