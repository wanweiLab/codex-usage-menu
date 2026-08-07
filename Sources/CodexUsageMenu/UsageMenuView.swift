import AppKit
import SwiftUI

struct UsageMenuView: View {
    @ObservedObject var service: CodexUsageService
    @ObservedObject var reminderService: ReminderService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShowingPreferences = false
    @State private var menuBarPrefixDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            accentBar
            header
            Divider()
            if isShowingPreferences {
                preferences
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing)))
            } else {
                content
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .leading)))
            }
            Divider()
            footer
        }
        .frame(width: CodexTheme.panelWidth)
        .background(.ultraThinMaterial)
    }

    private var accentBar: some View {
        LinearGradient(
            colors: [CodexTheme.accentLight, CodexTheme.accent],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 5)
        .accessibilityHidden(true)
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Codex Pulse")
                    .font(.system(size: 15, weight: .semibold))
                Text(planLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Label("已连接", systemImage: "circle.fill")
                .labelStyle(ConnectedLabelStyle())
                .opacity(service.snapshot == nil ? 0 : 1)
                .accessibilityLabel("Codex 已连接")
        }
        .padding(.horizontal, 18)
        .frame(height: 67)
    }

    @ViewBuilder
    private var content: some View {
        if let weekly = service.snapshot?.weeklyWindow {
            VStack(spacing: 0) {
                UsagePrimaryView(window: weekly)

                if let short = service.snapshot?.shortWindow {
                    UsageSecondaryView(window: short)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 17)
                }

                if let failure = service.lastFailure {
                    staleDataBanner(failure)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 17)
                }
            }
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
        } else {
            stateView
        }
    }

    private var stateView: some View {
        VStack(spacing: 12) {
            switch service.state {
            case .loading, .idle:
                ProgressView()
                    .controlSize(.small)
                Text("正在读取 Codex 额度…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 20))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                HStack(spacing: 14) {
                    Button("重新读取") {
                        Task { await service.refresh() }
                    }
                    Button("复制诊断") {
                        copyDiagnostics()
                    }
                }
            case .loaded:
                Text("暂时没有额度数据")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 190)
        .padding(.horizontal, 24)
    }

    private var footer: some View {
        Group {
            if isShowingPreferences {
                HStack {
                    Button("恢复默认") {
                        service.resetMenuBarPrefix()
                        menuBarPrefixDraft = service.menuBarPrefix
                    }
                    .disabled(service.menuBarPrefix == CodexUsageService.defaultMenuBarPrefix)

                    Spacer()

                    Button("完成") {
                        withAnimation(.easeInOut(duration: reduceMotion ? 0 : 0.18)) {
                            isShowingPreferences = false
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 18)
            } else {
                HStack {
                    Text(lastUpdatedText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Spacer()

                    Button {
                        withAnimation(.easeInOut(duration: reduceMotion ? 0 : 0.18)) {
                            isShowingPreferences = true
                        }
                    } label: {
                        Image(systemName: "gearshape")
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .help("显示设置")
                    .accessibilityLabel("打开显示设置")

                    Button {
                        Task { await service.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .disabled(service.isRefreshing)
                    .help("刷新额度")
                    .accessibilityLabel("刷新额度")

                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Image(systemName: "power")
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .help("退出 Codex Pulse")
                    .accessibilityLabel("退出 Codex Pulse")
                }
                .padding(.horizontal, 14)
            }
        }
        .frame(height: 54)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.45))
    }

    private var preferences: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("状态栏显示")
                        .font(.system(size: 13, weight: .semibold))
                    Text("自定义周额度前面的文字，留空则只显示额度。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        TextField(
                            "例如 CodeX",
                            text: $menuBarPrefixDraft
                        )
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: menuBarPrefixDraft) { newValue in
                            let limitedValue = service.updateMenuBarPrefix(newValue)
                            if limitedValue != newValue {
                                menuBarPrefixDraft = limitedValue
                            }
                        }

                        Text(
                            "\(menuBarPrefixDraft.count)/\(CodexUsageService.maximumMenuBarPrefixLength)"
                        )
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 30, alignment: .trailing)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "chart.donut")
                        Text(service.menuBarText)
                            .monospacedDigit()
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                    .accessibilityLabel("状态栏预览：\(service.menuBarText)")
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("健康提醒")
                            .font(.system(size: 13, weight: .semibold))
                        Text("屏幕中央置顶弹窗，60 秒后自动关闭。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    ReminderSettingRow(
                        kind: .sedentary,
                        configuration: reminderService.configuration(for: .sedentary),
                        setEnabled: { isEnabled in
                            reminderService.setEnabled(isEnabled, for: .sedentary)
                        },
                        setInterval: { interval in
                            reminderService.updateInterval(interval, for: .sedentary)
                        }
                    )

                    ReminderSettingRow(
                        kind: .hydration,
                        configuration: reminderService.configuration(for: .hydration),
                        setEnabled: { isEnabled in
                            reminderService.setEnabled(isEnabled, for: .hydration)
                        },
                        setInterval: { interval in
                            reminderService.updateInterval(interval, for: .hydration)
                        }
                    )
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .frame(height: 354)
        .onAppear {
            menuBarPrefixDraft = service.menuBarPrefix
        }
    }

    private var planLabel: String {
        let plan = service.account?.planType?.capitalized
            ?? service.snapshot?.planType?.capitalized
            ?? "账户"

        if let email = service.account?.email, !email.isEmpty {
            return "\(Self.maskedEmail(email)) · \(plan)"
        }
        return "个人账户 · \(plan)"
    }

    private func staleDataBanner(_ failure: UsageFailure) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("刷新失败，正在显示上次数据")
                    .font(.system(size: 11, weight: .medium))
                Text(failure.message)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button {
                copyDiagnostics()
            } label: {
                Image(systemName: "doc.on.doc")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("复制诊断信息")
            .accessibilityLabel("复制诊断信息")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
    }

    private func copyDiagnostics() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(service.diagnosticText, forType: .string)
    }

    private static func maskedEmail(_ email: String) -> String {
        let parts = email.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2, let first = parts[0].first else { return "已登录账户" }
        return "\(first)***@\(parts[1])"
    }

    private var lastUpdatedText: String {
        guard let updatedAt = service.snapshot?.updatedAt else {
            return service.state == .loading ? "正在更新" : "等待更新"
        }
        return "更新于 " + updatedAt.formatted(date: .omitted, time: .shortened)
    }
}

private struct ReminderSettingRow: View {
    let kind: ReminderKind
    let configuration: ReminderConfiguration
    let setEnabled: (Bool) -> Void
    let setInterval: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Label(kind.title, systemImage: kind.systemImage)
                    .font(.system(size: 12, weight: .medium))

                Spacer()

                Toggle(
                    "",
                    isOn: Binding(
                        get: { configuration.isEnabled },
                        set: { isEnabled in setEnabled(isEnabled) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(kind.title)
                .accessibilityHint("开启后按设置的分钟数重复提醒")
            }

            HStack(spacing: 6) {
                Text("每")

                TextField(
                    "分钟",
                    value: Binding(
                        get: { configuration.intervalMinutes },
                        set: { setInterval($0) }
                    ),
                    format: .number
                )
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 58)
                .accessibilityLabel("\(kind.title)间隔分钟数")

                Text("分钟提醒")
            }
            .font(.system(size: 11))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.72),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
    }
}

private struct UsagePrimaryView: View {
    let window: UsageWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("本周额度")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(resetText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(window.remainingPercent)%")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .tracking(-2)
                    .monospacedDigit()
                Text("剩余")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 7)

            ProgressView(value: Double(window.remainingPercent), total: 100)
                .progressViewStyle(.linear)
                .tint(CodexTheme.accent)
                .accessibilityLabel("本周额度")
                .accessibilityValue("剩余百分之 \(window.remainingPercent)，已使用百分之 \(window.usedPercent)")
                .padding(.top, 13)

            HStack {
                Text("已使用 \(window.usedPercent)%")
                Spacer()
                Text("剩余 \(window.remainingPercent)%")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .padding(.top, 7)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 18)
    }

    private var resetText: String {
        guard let resetsAt = window.resetsAt else { return "重置时间未知" }
        return ResetTimeFormatter.relativeText(to: resetsAt) + "后重置"
    }
}

private struct UsageSecondaryView: View {
    let window: UsageWindow

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(durationLabel)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(window.remainingPercent)%")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }

            ProgressView(value: Double(window.remainingPercent), total: 100)
                .progressViewStyle(.linear)
                .tint(CodexTheme.accent)
                .accessibilityLabel(durationLabel)
                .accessibilityValue("剩余百分之 \(window.remainingPercent)")

            HStack {
                Text("短周期限制")
                Spacer()
                Text(resetText)
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(14)
        .background(CodexTheme.secondaryCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CodexTheme.border, lineWidth: 1)
        }
    }

    private var durationLabel: String {
        guard let minutes = window.durationMinutes else { return "短周期额度" }
        if minutes.isMultiple(of: 60) {
            return "\(minutes / 60)小时额度"
        }
        return "\(minutes)分钟额度"
    }

    private var resetText: String {
        guard let resetsAt = window.resetsAt else { return "重置时间未知" }
        return ResetTimeFormatter.relativeText(to: resetsAt) + "后重置"
    }
}

private struct ConnectedLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .font(.system(size: 7))
                .foregroundStyle(.green)
            configuration.title
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

enum ResetTimeFormatter {
    static func relativeText(to date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60

        if days > 0 {
            return "\(days)天\(hours)小时"
        }
        if hours > 0 {
            return "\(hours)小时\(minutes)分"
        }
        return "\(minutes)分钟"
    }
}
