import Combine
import Foundation

@MainActor
final class CodexUsageService: ObservableObject {
    static let defaultMenuBarPrefix = "CodeX"
    static let maximumMenuBarPrefixLength = 8

    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var account: CodexAccount?
    @Published private(set) var state: UsageLoadState = .idle
    @Published private(set) var lastFailure: UsageFailure?
    @Published private(set) var isRefreshing = false
    @Published private(set) var menuBarPrefix: String

    private let client: any CodexUsageClient
    private let defaults: UserDefaults
    private var pollingTask: Task<Void, Never>?
    private var activeRefresh: Task<Void, Never>?
    private var activeRefreshID: UUID?

    init(
        client: any CodexUsageClient = CodexAppServerClient(),
        defaults: UserDefaults = .standard
    ) {
        self.client = client
        self.defaults = defaults
        let savedPrefix = defaults.string(forKey: Self.menuBarPrefixDefaultsKey)
        menuBarPrefix = Self.sanitizedMenuBarPrefix(
            savedPrefix ?? Self.defaultMenuBarPrefix
        )
    }

    deinit {
        pollingTask?.cancel()
        activeRefresh?.cancel()
        client.shutdown()
    }

    var menuBarText: String {
        let usageText: String
        if let percent = snapshot?.weeklyWindow?.remainingPercent {
            usageText = "周 \(percent)%"
        } else {
            usageText = state == .loading ? "周 …" : "周 --"
        }

        guard !menuBarPrefix.isEmpty else {
            return usageText
        }
        return "\(menuBarPrefix)｜\(usageText)"
    }

    var menuBarAccessibilityLabel: String {
        if let percent = snapshot?.weeklyWindow?.remainingPercent {
            return "Codex 本周额度剩余百分之 \(percent)"
        }
        return "Codex 周额度暂不可用"
    }

    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            guard let self else { return }

            // Account metadata only changes when the user switches Codex accounts.
            // Read it once over the same persistent, serialized app-server session.
            account = try? await client.fetchAccount()
            await refresh()

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled else { return }
                await refresh(silently: true)
            }
        }
    }

    func refresh(silently: Bool = false) async {
        if let activeRefresh {
            await activeRefresh.value
            return
        }

        let refreshID = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            await performRefresh(silently: silently)
        }
        activeRefreshID = refreshID
        activeRefresh = task
        isRefreshing = true

        await task.value

        if activeRefreshID == refreshID {
            activeRefresh = nil
            activeRefreshID = nil
            isRefreshing = false
        }
    }

    func updateMenuBarPrefix(_ value: String) {
        let sanitized = Self.sanitizedMenuBarPrefix(value)
        guard sanitized != menuBarPrefix else { return }
        menuBarPrefix = sanitized
        defaults.set(sanitized, forKey: Self.menuBarPrefixDefaultsKey)
    }

    func resetMenuBarPrefix() {
        updateMenuBarPrefix(Self.defaultMenuBarPrefix)
    }

    var diagnosticText: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "development"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let executable = CodexAppServerClient.executableDisplayPath ?? "未找到"
        let failure = lastFailure

        return [
            "Codex Pulse 诊断信息",
            "App: \(version) (\(build))",
            "macOS: \(osVersion)",
            "Codex: \(executable)",
            "错误代码: \(failure?.code ?? "none")",
            "错误信息: \(failure?.message ?? "无")",
            "失败时间: \(Self.diagnosticDate(failure?.occurredAt))",
            "数据时间: \(Self.diagnosticDate(snapshot?.updatedAt))",
            "认证信息: 未读取、未包含"
        ].joined(separator: "\n")
    }

    private func performRefresh(silently: Bool) async {
        if !silently || snapshot == nil {
            state = .loading
        }

        do {
            snapshot = try await client.fetchRateLimits()
            lastFailure = nil
            state = .loaded
        } catch {
            let message = error.localizedDescription
            let code = (error as? CodexClientError)?.diagnosticCode ?? "unexpected_error"
            lastFailure = UsageFailure(message: message, code: code, occurredAt: Date())
            state = .failed(message)
        }
    }

    private static func diagnosticDate(_ date: Date?) -> String {
        guard let date else { return "无" }
        return date.formatted(
            .iso8601
                .year()
                .month()
                .day()
                .dateSeparator(.dash)
                .time(includingFractionalSeconds: false)
                .timeSeparator(.colon)
        )
    }

    private static let menuBarPrefixDefaultsKey = "menuBarPrefix"

    private static func sanitizedMenuBarPrefix(_ value: String) -> String {
        let singleLine = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return String(singleLine.prefix(maximumMenuBarPrefixLength))
    }
}
