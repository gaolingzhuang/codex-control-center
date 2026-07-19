import AppKit
import SwiftUI
import WidgetKit

struct CodexWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct CodexWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CodexWidgetEntry {
        CodexWidgetEntry(date: Date(), snapshot: Self.previewSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (CodexWidgetEntry) -> Void) {
        completion(CodexWidgetEntry(
            date: Date(),
            snapshot: context.isPreview ? Self.previewSnapshot : WidgetSnapshotReader().read()
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CodexWidgetEntry>) -> Void) {
        let now = Date()
        let entry = CodexWidgetEntry(date: now, snapshot: WidgetSnapshotReader().read())
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 5, to: now)
            ?? now.addingTimeInterval(300)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private static let previewSnapshot = WidgetSnapshot(
        remainingPercent: 68,
        resetsAt: Date().addingTimeInterval(3 * 24 * 60 * 60),
        resetCreditsAvailable: 1,
        fetchedAt: Date(),
        todayTotalTokens: 5_900_000,
        tasks: [
            WidgetTaskSnapshot(title: "产品需求整理", todayTokens: 2_840_000),
            WidgetTaskSnapshot(title: "登录流程修复", todayTokens: 1_260_000),
            WidgetTaskSnapshot(title: "周报生成", todayTokens: 680_000),
            WidgetTaskSnapshot(title: "数据核对", todayTokens: 520_000),
            WidgetTaskSnapshot(title: "组件设计", todayTokens: 360_000),
            WidgetTaskSnapshot(title: "文档更新", todayTokens: 240_000)
        ]
    )
}

struct CodexWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: CodexWidgetEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                loadedView(snapshot)
            } else {
                emptyView
            }
        }
        .containerBackground(for: .widget) {
            adaptiveContainerBackground
        }
        .widgetURL(URL(string: "codex-control-center://details"))
    }

    @ViewBuilder
    private var adaptiveContainerBackground: some View {
        if #available(macOS 26.0, *), renderingMode == .fullColor {
            Color.clear
                .glassEffect(
                    .regular,
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                )
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func loadedView(_ snapshot: WidgetSnapshot) -> some View {
        switch family {
        case .systemSmall:
            smallView(snapshot)
        case .systemLarge:
            largeView(snapshot)
        default:
            mediumView(snapshot)
        }
    }

    private func smallView(_ snapshot: WidgetSnapshot) -> some View {
        VStack(spacing: 5) {
            Spacer(minLength: 0)
            quotaIndicator(snapshot.remainingPercent, size: 68, percentageFont: .title2)
            Spacer(minLength: 0)
            compactResetMetadata(snapshot)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Codex 每周剩余 \(roundedPercent(snapshot.remainingPercent))%")
    }

    private func mediumView(_ snapshot: WidgetSnapshot) -> some View {
        VStack(spacing: 10) {
            header(snapshot)
            HStack(alignment: .center, spacing: 12) {
                quotaIndicator(snapshot.remainingPercent, size: 64, percentageFont: .title3)
                .frame(width: 82)

                Divider()

                taskList(snapshot, limit: 3, showsBars: false)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Codex 每周剩余 \(roundedPercent(snapshot.remainingPercent))%")
    }

    private func largeView(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            header(snapshot)

            HStack(spacing: 18) {
                quotaIndicator(snapshot.remainingPercent, size: 82, percentageFont: .title2)
                VStack(alignment: .leading, spacing: 5) {
                    if let total = snapshot.todayTotalTokens {
                        Text("今日消耗")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formatTokens(total))
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                        Text("tokens")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            Divider()
            taskList(snapshot, limit: 6, showsBars: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Codex 每周剩余 \(roundedPercent(snapshot.remainingPercent))%")
    }

    private func header(_ snapshot: WidgetSnapshot) -> some View {
        HStack(spacing: 8) {
            Text("Codex")
                .font(.headline)
            Spacer()
            resetMetadata(snapshot)
        }
    }

    private func quotaIndicator(
        _ percent: Double,
        size: CGFloat,
        percentageFont: Font
    ) -> some View {
        VStack(spacing: 5) {
            quotaGauge(percent, size: size)
            Text("\(roundedPercent(percent))%")
                .font(percentageFont.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.78))
                .widgetAccentable(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("每周剩余额度")
        .accessibilityValue("\(roundedPercent(percent))%")
    }

    private func quotaGauge(_ percent: Double, size: CGFloat) -> some View {
        let clamped = max(0, min(100, percent))
        // The Apple Batteries widget uses a stroke close to 9.5% of the
        // circle diameter. Drawing the ring ourselves keeps that proportion
        // and its white-on-glass treatment stable across widget render modes.
        let lineWidth = size * 0.095
        return ZStack {
            Circle()
                .stroke(
                    Color.white.opacity(0.16),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .widgetAccentable(false)
            Circle()
                .trim(from: 0, to: clamped / 100)
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .widgetAccentable(true)

            codexMark(size: size * 0.40)
        }
        .padding(lineWidth / 2)
        .frame(width: size, height: size)
        .accessibilityLabel("每周剩余额度")
        .accessibilityValue("\(roundedPercent(clamped))%")
    }

    private func codexMark(size: CGFloat) -> some View {
        Image(nsImage: Self.codexVectorMarkImage)
            .resizable()
            .renderingMode(.template)
            .interpolation(.high)
            .scaledToFit()
            .foregroundStyle(Color.white.opacity(0.70))
            .frame(width: size, height: size)
    }

    // Transparent vector data is decoded inside the Widget process. Unlike
    // the previous PNG, it has no opaque background for WidgetKit to flatten
    // into a square when the desktop uses an accented rendering mode.
    private static let codexVectorMarkImage: NSImage = {
        let svg = """
        <svg width="100" height="100" viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
          <path fill="white" d="M83.77 42.81c1.89-5.69 1.27-11.91-1.72-16.37-4.36-7.6-13.13-11.5-21.7-9.67A20.18 20.18 0 0 0 26.1 24.01a20.2 20.2 0 0 0-10.85 33.32 20.18 20.18 0 0 0 23.42 26.04 20.18 20.18 0 0 0 34.27-7.32 20.2 20.2 0 0 0 10.83-33.24ZM53.7 84.84a14.9 14.9 0 0 1-9.59-3.47l16.4-9.46a2.63 2.63 0 0 0 1.31-2.28V47.18l6.73 3.89c.08.04.13.11.13.18v18.6A15 15 0 0 1 53.7 84.84ZM21.5 71.08a14.9 14.9 0 0 1-1.78-10.04l16.41 9.48c.8.47 1.8.47 2.6 0L58.21 59.3v7.77a.24.24 0 0 1-.11.2l-16.13 9.3a15.02 15.02 0 0 1-20.47-5.48ZM17.3 36.39a15 15 0 0 1 7.89-6.58v18.93c-.01.93.49 1.8 1.29 2.25l19.38 11.18-6.73 3.9a.24.24 0 0 1-.24 0l-16.1-9.29a15.02 15.02 0 0 1-5.49-20.39Zm55.32 12.85L53.18 37.95l6.72-3.88a.24.24 0 0 1 .24 0l16.1 9.3a15 15 0 0 1-2.26 27.02V51.47c-.02-.93-.53-1.78-1.36-2.23Zm6.71-10.07-16.39-9.56a2.63 2.63 0 0 0-2.62 0L40.86 40.84v-7.78a.24.24 0 0 1 .1-.2l16.1-9.29a15 15 0 0 1 22.27 15.6ZM37.19 52.95l-6.74-3.88a.24.24 0 0 1-.12-.19V30.32a15 15 0 0 1 24.58-11.51l-16.4 9.46a2.63 2.63 0 0 0-1.31 2.27l-.01 22.41Zm3.66-7.89 8.67-5 8.69 5v10l-8.66 5-8.69-5-.01-10Z"/>
        </svg>
        """
        guard let image = NSImage(data: Data(svg.utf8)) else {
            preconditionFailure("Embedded Codex vector mark is invalid")
        }
        image.isTemplate = true
        return image
    }()

    @ViewBuilder
    private func resetMetadata(_ snapshot: WidgetSnapshot) -> some View {
        HStack(spacing: 5) {
            if let reset = snapshot.resetsAt {
                Text("\(resetCaption(reset)) 重置")
            }
            if snapshot.resetsAt != nil, snapshot.resetCreditsAvailable != nil {
                Text("·")
                    .foregroundStyle(.tertiary)
            }
            if let count = snapshot.resetCreditsAvailable {
                Text("\(count) 张卡")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func compactResetMetadata(_ snapshot: WidgetSnapshot) -> some View {
        HStack(spacing: 4) {
            if let reset = snapshot.resetsAt {
                Text(resetCaption(reset))
            }
            if snapshot.resetsAt != nil, snapshot.resetCreditsAvailable != nil {
                Text("·")
                    .foregroundStyle(.tertiary)
            }
            if let count = snapshot.resetCreditsAvailable {
                Text("\(count) 张卡")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.82)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(resetAccessibilityLabel(snapshot))
    }

    private func resetAccessibilityLabel(_ snapshot: WidgetSnapshot) -> String {
        var parts: [String] = []
        if let reset = snapshot.resetsAt {
            parts.append("\(resetCaption(reset))重置")
        }
        if let count = snapshot.resetCreditsAvailable {
            parts.append("可用重置卡\(count)张")
        }
        return parts.joined(separator: "，")
    }

    private func taskList(
        _ snapshot: WidgetSnapshot,
        limit: Int,
        showsBars: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: showsBars ? 9 : 7) {
            HStack {
                Text("今日消耗")
                    .font(.headline)
            }

            if snapshot.tasks.isEmpty {
                Text("今天还没有任务消耗")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ForEach(Array(snapshot.tasks.prefix(limit).enumerated()), id: \.offset) { index, task in
                    taskRow(
                        task,
                        totalTokens: max(snapshot.todayTotalTokens ?? 0, 1),
                        showsBar: showsBars
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func taskRow(
        _ task: WidgetTaskSnapshot,
        totalTokens: Int64,
        showsBar: Bool
    ) -> some View {
        let share = min(1, max(0, Double(task.todayTokens) / Double(totalTokens)))
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Text(task.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(formatTokens(task.todayTokens))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize()
            }
            if showsBar {
                GeometryReader { geometry in
                    Capsule()
                        .fill(.primary.opacity(0.09))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(taskTint(for: task).opacity(0.72))
                                .frame(width: max(share > 0 ? 2 : 0, geometry.size.width * CGFloat(share)))
                        }
                }
                .frame(height: 4)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(task.title)，占今日总消耗 \(Int((share * 100).rounded()))%，\(formatTokens(task.todayTokens)) tokens")
    }

    private func taskTint(for task: WidgetTaskSnapshot) -> Color {
        guard renderingMode == .fullColor else { return .primary }
        let palette: [Color] = [.blue, .teal, .indigo, .purple, .mint, .cyan]
        return palette[max(0, task.colorIndex ?? 0) % palette.count]
    }

    @ViewBuilder
    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Codex")
                .font(.headline)
            Spacer()
            Text("打开 Codex 控制中心以同步额度")
                .font(.body.weight(.medium))
            Text("同步后，小组件会自动更新。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func resetCaption(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    private func roundedPercent(_ percent: Double) -> Int {
        Int(percent.rounded())
    }

    private func formatTokens(_ value: Int64) -> String {
        let number = Double(value)
        if value >= 1_000_000_000 { return String(format: "%.1fB", number / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "%.1fM", number / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", number / 1_000) }
        return "\(value)"
    }
}

@main
struct CodexControlCenterWidget: Widget {
    private let kind = "CodexControlCenterWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CodexWidgetProvider()) { entry in
            CodexWidgetView(entry: entry)
        }
        .configurationDisplayName("Codex 控制中心")
        .description("查看 Codex 剩余额度、重置卡与今日任务消耗。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
