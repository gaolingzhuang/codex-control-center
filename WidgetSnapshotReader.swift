import Foundation
import Darwin

struct WidgetTaskSnapshot: Codable, Equatable {
    let title: String
    let todayTokens: Int64
    let colorIndex: Int?

    init(title: String, todayTokens: Int64, colorIndex: Int? = nil) {
        self.title = title
        self.todayTokens = todayTokens
        self.colorIndex = colorIndex
    }
}

struct WidgetSnapshot: Codable, Equatable {
    let remainingPercent: Double
    let resetsAt: Date?
    let resetCreditsAvailable: Int?
    let fetchedAt: Date
    let todayTotalTokens: Int64?
    let tasks: [WidgetTaskSnapshot]
}

struct WidgetSnapshotReader {
    private var fileURL: URL {
        realUserHomeDirectory
            .appendingPathComponent("Library/Application Support/CodexControlCenter")
            .appendingPathComponent("widget-snapshot.json")
    }

    // Inside an App Sandbox, FileManager's home directory points at the
    // extension container. The passwd database still returns the login
    // user's real home, which is covered by the extension's read-only
    // home-relative entitlement.
    private var realUserHomeDirectory: URL {
        guard let record = getpwuid(getuid()), let path = record.pointee.pw_dir else {
            return FileManager.default.homeDirectoryForCurrentUser
        }
        return URL(fileURLWithPath: String(cString: path), isDirectory: true)
    }

    func read() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}
