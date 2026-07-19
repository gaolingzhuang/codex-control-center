import AppKit
#if canImport(CodexControlCenterCore)
import CodexControlCenterCore
#endif
import SwiftUI

struct ControlCenterView: View {
    static let preferredSize = NSSize(width: 264, height: 480)

    @ObservedObject var model: DashboardModel
    let onRefresh: () -> Void
    let onOpenHistory: () -> Void
    let onQuit: () -> Void
    let onClose: (() -> Void)?
    @State private var expandedLowConsumptionRange: TaskUsageRange?

    private var rankedTasks: [TaskSummary] {
        var grouped: [String: TaskSummary] = [:]
        for task in model.tasks {
            let tokens = task.tokens(for: model.selectedRange)
            guard tokens > 0 else { continue }
            let title = task.displayTitle
            let existing = grouped[title]
            grouped[title] = TaskSummary(
                title: title,
                tokens: (existing?.tokens ?? 0) + tokens,
                updatedAt: max(existing?.updatedAt ?? .distantPast, task.updatedAt)
            )
        }
        return grouped.values.sorted {
            $0.tokens == $1.tokens ? $0.updatedAt > $1.updatedAt : $0.tokens > $1.tokens
        }
    }

    private var selectedRangeTotalTokens: Int64 {
        TaskUsageMetrics.totalTokens(in: model.tasks, for: model.selectedRange)
    }

    private var visibleTasks: [TaskSummary] {
        rankedTasks.enumerated().compactMap { index, task in
            let share = TaskUsageMetrics.share(tokens: task.tokens, of: selectedRangeTotalTokens)
            return index < 4 || share >= 0.005 ? task : nil
        }
    }

    private var lowConsumptionTasks: [TaskSummary] {
        rankedTasks.enumerated().compactMap { index, task in
            let share = TaskUsageMetrics.share(tokens: task.tokens, of: selectedRangeTotalTokens)
            return index >= 4 && share < 0.005 ? task : nil
        }
    }

    private var lowConsumptionTotalTokens: Int64 {
        lowConsumptionTasks.reduce(0) { $0 + $1.tokens }
    }

    private var isLowConsumptionExpanded: Bool {
        expandedLowConsumptionRange == model.selectedRange
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.55)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    quotaSection
                    taskSection
                    if let error = model.errorMessage { errorView(error) }
                }
                .padding(12)
            }
            Divider().opacity(0.55)
            footer
        }
        .frame(width: Self.preferredSize.width, height: Self.preferredSize.height)
        .background(Color.clear)
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text("Codex")
                        .font(.system(size: 15, weight: .semibold))
                    Circle()
                        .fill(model.errorMessage == nil ? Color.green : Color.orange)
                        .frame(width: 5, height: 5)
                        .accessibilityHidden(true)
                }
                Text("额度与任务")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 28, height: 28)
            } else {
                toolbarButton("arrow.clockwise", label: "刷新", action: onRefresh)
            }
            if let onClose {
                toolbarButton("xmark", label: "关闭详情", action: onClose)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
    }

    private var quotaSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("额度")
            VStack(spacing: 0) {
                if let snapshot = model.snapshot, !snapshot.windows.isEmpty {
                    ForEach(Array(snapshot.windows.enumerated()), id: \.offset) { index, window in
                        QuotaRow(
                            window: window,
                            assessedAt: snapshot.fetchedAt,
                            plan: index == 0 ? snapshot.plan : nil,
                            resetCredits: index == 0 ? snapshot.resetCreditsAvailable : nil
                        )
                        if index < snapshot.windows.count - 1 {
                            Divider().padding(.leading, 60)
                        }
                    }
                } else {
                    HStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        Text("正在读取 Codex 额度…")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(12)
                }
            }
            .background(sectionBackground)
        }
    }

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                sectionTitle("任务消耗")
                Spacer()
                Text(rangeCaption)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Picker("统计范围", selection: $model.selectedRange) {
                ForEach(TaskUsageRange.allCases) { range in
                    Text(range.displayName).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)

            VStack(spacing: 0) {
                if rankedTasks.isEmpty {
                    VStack(spacing: 7) {
                        Image(systemName: "chart.bar")
                            .font(.system(size: 18, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text(emptyMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    ForEach(Array(visibleTasks.enumerated()), id: \.element.id) { index, task in
                        TaskUsageRow(
                            task: task,
                            totalTokens: selectedRangeTotalTokens
                        )
                        if index < visibleTasks.count - 1 || !lowConsumptionTasks.isEmpty {
                            Divider().padding(.leading, 12)
                        }
                    }

                    if !lowConsumptionTasks.isEmpty {
                        LowConsumptionTaskGroupRow(
                            taskCount: lowConsumptionTasks.count,
                            tokens: lowConsumptionTotalTokens,
                            totalTokens: selectedRangeTotalTokens,
                            isExpanded: isLowConsumptionExpanded,
                            onToggle: {
                                withAnimation(.easeInOut(duration: 0.16)) {
                                    expandedLowConsumptionRange = isLowConsumptionExpanded
                                        ? nil
                                        : model.selectedRange
                                }
                            }
                        )

                        if isLowConsumptionExpanded {
                            ForEach(lowConsumptionTasks) { task in
                                Divider().padding(.leading, 22)
                                TaskUsageRow(
                                    task: task,
                                    totalTokens: selectedRangeTotalTokens
                                )
                                .padding(.leading, 10)
                            }
                        }
                    }
                }
            }
            .background(sectionBackground)
        }
    }

    private var rangeCaption: String {
        switch model.selectedRange {
        case .today: "今日总消耗 \(Self.formatTokens(selectedRangeTotalTokens))"
        case .weekly: "本周期总消耗 \(Self.formatTokens(selectedRangeTotalTokens))"
        case .all: "本机累计总消耗 \(Self.formatTokens(selectedRangeTotalTokens))"
        }
    }

    private var emptyMessage: String {
        switch model.selectedRange {
        case .today: "今天还没有任务消耗"
        case .weekly: "当前额度周期内没有任务消耗"
        case .all: "还没有可统计的任务"
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let date = model.snapshot?.fetchedAt {
                Text("更新于 \(date.formatted(date: .omitted, time: .shortened))")
            } else {
                Text("等待更新")
            }
            Spacer()
            Button("历史", action: onOpenHistory).buttonStyle(.plain)
            Button("退出", action: onQuit).buttonStyle(.plain)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private var sectionBackground: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(Color.primary.opacity(0.045))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.primary.opacity(0.055), lineWidth: 0.6)
            }
    }

    private func toolbarButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
    }

    private static func formatTokens(_ value: Int64) -> String {
        let number = Double(value)
        if value >= 1_000_000_000 { return String(format: "%.1fB", number / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "%.1fM", number / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", number / 1_000) }
        return "\(value)"
    }

    private func errorView(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.system(size: 11))
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct QuotaRow: View {
    let window: UsageWindow
    let assessedAt: Date
    let plan: String?
    let resetCredits: Int?

    private var assessment: QuotaAssessment {
        window.assessment(at: assessedAt)
    }

    private var tint: Color {
        switch assessment.health {
        case .healthy: .green
        case .moderate: .blue
        case .warning: .orange
        case .critical: .red
        }
    }

    private var compactDetailText: String {
        assessment.detailText
            .replacingOccurrences(of: "按当前速度预计不到 ", with: "")
            .replacingOccurrences(of: "按当前速度预计", with: "")
            .replacingOccurrences(of: "后耗尽", with: "内耗尽")
            .replacingOccurrences(of: "按当前速度可持续到本次重置", with: "当前速度可持续到重置")
            .replacingOccurrences(of: "额度周期刚开始，正在观察消耗速度", with: "周期刚开始，正在观察")
    }

    private var resetCaption: String? {
        guard let reset = window.resetsAt else { return nil }
        let weekdayIndex = Calendar.current.component(.weekday, from: reset) - 1
        let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let weekday = weekdays.indices.contains(weekdayIndex) ? weekdays[weekdayIndex] : ""
        let time = reset.formatted(date: .omitted, time: .shortened)
        return "\(weekday) \(time) 重置"
    }

    private var detailTint: Color {
        compactDetailText.contains("耗尽")
            ? Color(red: 0.92, green: 0, blue: 0.035)
            : tint
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.08), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: window.remainingPercent / 100)
                    .stroke(tint, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(window.remainingPercent.rounded()))")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(assessment.statusText)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(tint.opacity(0.11), in: Capsule())
                    if let plan {
                        Text(plan.capitalized)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                if resetCaption != nil || resetCredits != nil {
                    HStack(spacing: 4) {
                        if let resetCaption {
                            Text(resetCaption)
                        }
                        if resetCaption != nil, resetCredits != nil {
                            Text("·")
                        }
                        if let resetCredits {
                            Text("\(resetCredits) 张重置卡")
                                .monospacedDigit()
                        }
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                }
                Text(compactDetailText)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(detailTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .allowsTightening(true)
                    .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(11)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(window.label)剩余 \(Int(window.remainingPercent.rounded()))%，状态\(assessment.statusText)，\(assessment.detailText)，可用重置卡 \(resetCredits ?? 0) 张")
    }
}

private struct TaskSummary: Identifiable {
    let title: String
    let tokens: Int64
    let updatedAt: Date
    var id: String { title }
}

private struct TaskUsageRow: View {
    let task: TaskSummary
    let totalTokens: Int64

    private var share: Double {
        TaskUsageMetrics.share(tokens: task.tokens, of: totalTokens)
    }

    private var barTint: Color {
        let palette: [Color] = [
            .blue,
            .teal,
            .indigo,
            .purple,
            .mint,
            .cyan
        ]
        return palette[TaskVisualIdentity.colorIndex(for: task.title)]
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(task.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(Self.formatTokens(task.tokens))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                GeometryReader { geometry in
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(barTint.opacity(0.72))
                                .frame(width: max(share > 0 ? 2 : 0, geometry.size.width * CGFloat(share)))
                        }
                }
                .frame(height: 4)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(task.title)，占所选周期总消耗 \(Self.accessibilityPercent(share))，\(Self.formatTokens(task.tokens)) tokens")
    }

    private static func accessibilityPercent(_ share: Double) -> String {
        let percent = share * 100
        if percent > 0, percent < 0.1 { return "<0.1%" }
        return String(format: "%.1f%%", percent)
    }

    private static func formatTokens(_ value: Int64) -> String {
        let number = Double(value)
        if value >= 1_000_000_000 { return String(format: "%.1fB", number / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "%.1fM", number / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", number / 1_000) }
        return "\(value)"
    }
}

private struct LowConsumptionTaskGroupRow: View {
    let taskCount: Int
    let tokens: Int64
    let totalTokens: Int64
    let isExpanded: Bool
    let onToggle: () -> Void

    private var share: Double {
        TaskUsageMetrics.share(tokens: tokens, of: totalTokens)
    }

    var body: some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text("其他低消耗任务")
                        .font(.system(size: 11, weight: .medium))
                    Text("\(taskCount) 项")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text(Self.formatTokens(tokens))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                GeometryReader { geometry in
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.55))
                                .frame(width: max(share > 0 ? 2 : 0, geometry.size.width * CGFloat(share)))
                        }
                }
                .frame(height: 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .accessibilityLabel("其他低消耗任务，\(taskCount) 项，合计 \(Self.formatTokens(tokens)) tokens")
        .accessibilityValue(isExpanded ? "已展开" : "已折叠")
    }

    private static func formatTokens(_ value: Int64) -> String {
        let number = Double(value)
        if value >= 1_000_000_000 { return String(format: "%.1fB", number / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "%.1fM", number / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", number / 1_000) }
        return "\(value)"
    }
}
