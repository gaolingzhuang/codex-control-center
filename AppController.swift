import AppKit
#if canImport(CodexControlCenterCore)
import CodexControlCenterCore
#endif
import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let provider: any UsageProvider = CodexProvider()
    private let taskReader = CodexTaskUsageReader()
    private let history = HistoryStore()
    private let widgetStore = WidgetSnapshotStore()
    private let alerts = AlertManager()
    private let model = DashboardModel()
    private lazy var detailsMenu: NSMenu = makeDetailsMenu()
    private var pendingMenuPresentation: DispatchWorkItem?
    private var isDetailsMenuOpen = false
    private var timer: Timer?

    private var refreshMinutes: Int {
        let saved = UserDefaults.standard.integer(forKey: "refreshMinutes")
        return saved == 0 ? 5 : saved
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        alerts.requestPermission()
        scheduleTimer()
        refresh()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "codex-control-center" }) else { return }
        showDetailsMenu()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .noImage
        updateStatusItem(title: "…", accessibilityValue: "正在读取额度")
        button.toolTip = "Codex 控制中心 · 正在读取额度"
        statusItem.menu = detailsMenu
    }

    private func detailView() -> ControlCenterView {
        ControlCenterView(
            model: model,
            onRefresh: { [weak self] in self?.refresh() },
            onOpenHistory: { [weak self] in
                self?.detailsMenu.cancelTracking()
                self?.openHistoryFolder()
            },
            onQuit: { NSApp.terminate(nil) },
            onClose: nil
        )
    }

    private func makeDetailsMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        let item = NSMenuItem()
        let hostingView = NSHostingView(rootView: detailView())
        hostingView.frame = NSRect(origin: .zero, size: ControlCenterView.preferredSize)
        item.view = hostingView
        menu.addItem(item)
        return menu
    }

    private func showDetailsMenu() {
        pendingMenuPresentation?.cancel()
        NSApp.activate(ignoringOtherApps: true)

        let presentation = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.isDetailsMenuOpen {
                self.detailsMenu.cancelTracking()
            } else if let button = self.statusItem.button {
                self.detailsMenu.popUp(
                    positioning: nil,
                    at: NSPoint(x: button.bounds.minX, y: button.bounds.minY),
                    in: button
                )
            }
            self.pendingMenuPresentation = nil
        }
        pendingMenuPresentation = presentation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: presentation)
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === detailsMenu else { return }
        isDetailsMenuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === detailsMenu else { return }
        isDetailsMenuOpen = false
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(refreshMinutes * 60), repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func refresh() {
        guard !model.isRefreshing else { return }
        model.isRefreshing = true
        model.errorMessage = nil
        if model.snapshot == nil {
            updateStatusItem(title: "…", accessibilityValue: "正在读取额度")
        }

        let provider = self.provider
        let taskReader = self.taskReader
        let history = self.history
        Task.detached(priority: .utility) { [weak self] in
            do {
                let snapshot = try provider.fetch()
                let weekStart = Self.quotaWeekStart(from: snapshot)
                let tasks = (try? taskReader.fetch(weekStart: weekStart)) ?? []
                try history.append(snapshot)
                let summary = history.summary()
                await self?.apply(snapshot: snapshot, tasks: tasks, summary: summary)
            } catch {
                let fallbackStart = Date().addingTimeInterval(-7 * 24 * 60 * 60)
                let tasks = (try? taskReader.fetch(weekStart: fallbackStart)) ?? []
                await self?.apply(error: error, tasks: tasks)
            }
        }
    }

    private func apply(snapshot: ProviderSnapshot, tasks: [TaskUsage], summary: HistorySummary) {
        model.snapshot = snapshot
        model.tasks = tasks
        model.historySummary = summary
        model.isRefreshing = false
        model.errorMessage = nil

        do {
            try widgetStore.write(snapshot: snapshot, tasks: tasks)
        } catch {
            NSLog("Codex Control Center could not update widget snapshot: %@", String(describing: error))
        }
#if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
#endif

        let remainingPercent = snapshot.lowestRemainingPercent ?? 0
        let remaining = Int(remainingPercent.rounded())
        updateStatusItem(
            title: "\(remaining)%",
            accessibilityValue: "当前最紧张额度剩余 \(remaining)%"
        )
        statusItem.button?.toolTip = Self.statusToolTip(for: snapshot)
        alerts.evaluate(snapshot)
    }

    private func apply(error: Error, tasks: [TaskUsage]) {
        model.tasks = tasks
        model.isRefreshing = false
        model.errorMessage = error.localizedDescription
        updateStatusItem(title: "!", accessibilityValue: "额度读取失败")
        statusItem.button?.toolTip = "Codex 控制中心 · \(error.localizedDescription)"
    }

    private func updateStatusItem(
        title: String,
        accessibilityValue: String
    ) {
        guard let button = statusItem.button else { return }
        button.image = nil
        button.title = title
        button.contentTintColor = nil
        button.setAccessibilityLabel("Codex 控制中心")
        button.setAccessibilityValue(accessibilityValue)
    }

    private static func statusToolTip(for snapshot: ProviderSnapshot) -> String {
        let windows = snapshot.windows.map { window in
            "\(window.label)剩余 \(Int(window.remainingPercent.rounded()))%"
        }
        return (["Codex 控制中心"] + windows).joined(separator: " · ")
    }

    private func openHistoryFolder() {
        try? FileManager.default.createDirectory(at: history.directoryURL, withIntermediateDirectories: true)
        NSWorkspace.shared.open(history.directoryURL)
    }

    nonisolated private static func quotaWeekStart(from snapshot: ProviderSnapshot) -> Date {
        let weekly = snapshot.windows.first(where: { $0.kind == .weekly })
            ?? snapshot.windows.max(by: {
                ($0.windowDurationMinutes ?? 0) < ($1.windowDurationMinutes ?? 0)
            })
        guard let window = weekly,
              let reset = window.resetsAt,
              let duration = window.windowDurationMinutes else {
            return Date().addingTimeInterval(-7 * 24 * 60 * 60)
        }
        return reset.addingTimeInterval(-TimeInterval(duration * 60))
    }
}
