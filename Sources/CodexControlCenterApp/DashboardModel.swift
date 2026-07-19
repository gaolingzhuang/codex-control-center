#if canImport(CodexControlCenterCore)
import CodexControlCenterCore
#endif
import Foundation
import SwiftUI

@MainActor
final class DashboardModel: ObservableObject {
    @Published var snapshot: ProviderSnapshot?
    @Published var tasks: [TaskUsage] = []
    @Published var selectedRange: TaskUsageRange = .today
    @Published var historySummary: HistorySummary?
    @Published var isRefreshing = false
    @Published var errorMessage: String?
}
