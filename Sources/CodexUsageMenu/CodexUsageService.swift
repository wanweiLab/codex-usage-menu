import Combine
import Foundation

@MainActor
final class CodexUsageService: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var account: CodexAccount?
    @Published private(set) var state: UsageLoadState = .idle

    private let client: CodexAppServerClient
    private var refreshTask: Task<Void, Never>?

    init(client: CodexAppServerClient = CodexAppServerClient()) {
        self.client = client
    }

    deinit {
        refreshTask?.cancel()
    }

    var menuBarText: String {
        if let percent = snapshot?.weeklyWindow?.remainingPercent {
            return "CodeX｜周 \(percent)%"
        }
        return state == .loading ? "CodeX｜周 …" : "CodeX｜周 --"
    }

    var menuBarAccessibilityLabel: String {
        if let percent = snapshot?.weeklyWindow?.remainingPercent {
            return "Codex 本周额度剩余百分之 \(percent)"
        }
        return "Codex 周额度暂不可用"
    }

    func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            guard let self else { return }

            // Account metadata only changes when the user switches Codex accounts.
            // Read it once and let that app-server process exit before starting the
            // independently refreshed rate-limit connection.
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
        if !silently || snapshot == nil {
            state = .loading
        }

        do {
            snapshot = try await client.fetchRateLimits()
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
