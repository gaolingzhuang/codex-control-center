import Foundation
import UserNotifications
#if canImport(CodexControlCenterCore)
import CodexControlCenterCore
#endif

@MainActor
final class AlertManager {
    private let defaults: UserDefaults
    let threshold: Double

    init(defaults: UserDefaults = .standard, threshold: Double = 20) {
        self.defaults = defaults
        self.threshold = threshold
    }

    func requestPermission() {
        Task {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        }
    }

    func evaluate(_ snapshot: ProviderSnapshot) {
        for window in snapshot.windows where window.remainingPercent <= threshold {
            let cycle = Int(window.resetsAt?.timeIntervalSince1970 ?? 0)
            let key = "lastAlert.\(snapshot.providerID).\(window.kind.rawValue)"
            guard defaults.integer(forKey: key) != cycle || cycle == 0 else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Codex 额度偏低"
            content.body = "\(window.label)仅剩 \(Int(window.remainingPercent.rounded()))%"
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "\(snapshot.providerID)-\(window.kind.rawValue)-\(cycle)",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
            defaults.set(cycle, forKey: key)
        }
    }
}
