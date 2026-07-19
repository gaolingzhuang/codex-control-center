import Foundation

public protocol UsageProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    func fetch() throws -> ProviderSnapshot
}

/// Future Claude/Cursor/Gemini adapters implement this protocol and return the
/// same normalized snapshot. The menu, history, and alert layers need no changes.
struct UnavailableProvider: UsageProvider {
    let id: String
    let displayName: String

    func fetch() throws -> ProviderSnapshot {
        throw UsageError.launchFailed("\(displayName) Provider 尚未启用")
    }
}
