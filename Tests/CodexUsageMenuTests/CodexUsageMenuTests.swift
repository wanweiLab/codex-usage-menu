import XCTest
@testable import CodexUsageMenu

final class CodexUsageMenuTests: XCTestCase {
    func testLiveClientReadsAccountThenRateLimits() async throws {
        guard ProcessInfo.processInfo.environment["CODEX_USAGE_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set CODEX_USAGE_LIVE_TEST=1 to use the current Codex login.")
        }

        let client = CodexAppServerClient(timeout: 20)
        let account = try await client.fetchAccount()
        let usage = try await client.fetchRateLimits()
        let refreshedUsage = try await client.fetchRateLimits()

        XCTAssertNotNil(account)
        XCTAssertNotNil(usage.weeklyWindow)
        XCTAssertNotNil(refreshedUsage.weeklyWindow)
    }

    func testParsesWeeklyAndShortWindows() throws {
        let line = try fixture("rate-limits-legacy")

        let snapshot = try XCTUnwrap(CodexAppServerClient.parseRateLimitResponse(line))

        XCTAssertEqual(snapshot.weeklyWindow?.usedPercent, 32)
        XCTAssertEqual(snapshot.weeklyWindow?.remainingPercent, 68)
        XCTAssertEqual(snapshot.weeklyWindow?.durationMinutes, 10_080)
        XCTAssertEqual(snapshot.shortWindow?.usedPercent, 18)
        XCTAssertEqual(snapshot.shortWindow?.durationMinutes, 300)
        XCTAssertEqual(snapshot.planType, "plus")
    }

    func testParsesCurrentMultiBucketResponse() throws {
        let line = try fixture("rate-limits-current")

        let snapshot = try XCTUnwrap(CodexAppServerClient.parseRateLimitResponse(line))

        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.weeklyWindow?.usedPercent, 1)
        XCTAssertNil(snapshot.shortWindow)
    }

    func testIgnoresUnrelatedNotifications() throws {
        let line = try fixture("unrelated-notification")
        XCTAssertNil(try CodexAppServerClient.parseRateLimitResponse(line))
    }

    func testParsesChatGPTAccount() throws {
        let line = try fixture("account-chatgpt")

        let account = try XCTUnwrap(CodexAppServerClient.parseAccountResponse(line))

        XCTAssertEqual(account.email, "allen@example.com")
        XCTAssertEqual(account.planType, "plus")
        XCTAssertEqual(account.type, "chatgpt")
    }

    func testParsesApiKeyAccountWithoutEmail() throws {
        let line = try fixture("account-api-key")

        let account = try XCTUnwrap(CodexAppServerClient.parseAccountResponse(line))

        XCTAssertNil(account.email)
        XCTAssertNil(account.planType)
        XCTAssertEqual(account.type, "apiKey")
    }

    func testReportsServerErrorsFromAnyRequestID() throws {
        let line = try fixture("server-error")

        XCTAssertThrowsError(try CodexAppServerClient.parseRateLimitResponse(line)) { error in
            guard case CodexClientError.serverError(let message) = error else {
                return XCTFail("Expected serverError, got \(error)")
            }
            XCTAssertEqual(message, "Method not found")
        }
    }

    func testRejectsResponseWithoutResult() throws {
        let line = try fixture("missing-result")

        XCTAssertThrowsError(try CodexAppServerClient.parseRateLimitResponse(line)) { error in
            guard case CodexClientError.invalidResponse = error else {
                return XCTFail("Expected invalidResponse, got \(error)")
            }
        }
    }

    func testCoalescesConcurrentRefreshes() async {
        let client = StubUsageClient(
            results: [.success(makeSnapshot(remainingPercent: 72))],
            delay: .milliseconds(100)
        )
        let service = await MainActor.run {
            CodexUsageService(client: client)
        }

        async let first: Void = service.refresh()
        async let second: Void = service.refresh()
        _ = await (first, second)

        XCTAssertEqual(client.fetchCount, 1)
        let remaining = await MainActor.run {
            service.snapshot?.weeklyWindow?.remainingPercent
        }
        XCTAssertEqual(remaining, 72)
    }

    func testRefreshFailureKeepsLastSnapshotAndAddsDiagnostics() async {
        let original = makeSnapshot(remainingPercent: 64)
        let client = StubUsageClient(
            results: [
                .success(original),
                .failure(StubError.offline)
            ]
        )
        let service = await MainActor.run {
            CodexUsageService(client: client)
        }

        await service.refresh()
        await service.refresh()

        let result = await MainActor.run {
            (
                service.snapshot,
                service.lastFailure,
                service.menuBarText,
                service.diagnosticText
            )
        }

        XCTAssertEqual(result.0, original)
        XCTAssertEqual(result.1?.code, "unexpected_error")
        XCTAssertEqual(result.2, "CodeX｜周 64%")
        XCTAssertTrue(result.3.contains("认证信息: 未读取、未包含"))
    }

    func testCustomMenuBarPrefixPersistsAndCanBeBlank() async {
        let suiteName = "CodexUsageMenuTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let service = await MainActor.run {
            CodexUsageService(
                client: StubUsageClient(results: []),
                defaults: UserDefaults(suiteName: suiteName)!
            )
        }

        let initialText = await MainActor.run { service.menuBarText }
        XCTAssertEqual(initialText, "CodeX｜周 --")

        _ = await MainActor.run {
            service.updateMenuBarPrefix("万维 Lab")
        }
        let customText = await MainActor.run { service.menuBarText }
        XCTAssertEqual(customText, "万维 Lab｜周 --")

        let restoredService = await MainActor.run {
            CodexUsageService(
                client: StubUsageClient(results: []),
                defaults: UserDefaults(suiteName: suiteName)!
            )
        }
        let restoredText = await MainActor.run { restoredService.menuBarText }
        XCTAssertEqual(restoredText, "万维 Lab｜周 --")

        _ = await MainActor.run {
            restoredService.updateMenuBarPrefix("   ")
        }
        let blankText = await MainActor.run { restoredService.menuBarText }
        XCTAssertEqual(blankText, "周 --")
    }

    func testMenuBarPrefixIsSingleLineAndLimitedToEightCharacters() async {
        let suiteName = "CodexUsageMenuTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let service = await MainActor.run {
            CodexUsageService(
                client: StubUsageClient(results: []),
                defaults: UserDefaults(suiteName: suiteName)!
            )
        }

        let limitedValue = await MainActor.run {
            service.updateMenuBarPrefix(" 1234\n567890 ")
        }

        let result = await MainActor.run {
            (service.menuBarPrefix, service.menuBarText)
        }
        XCTAssertEqual(limitedValue, "1234 567")
        XCTAssertEqual(result.0, "1234 567")
        XCTAssertEqual(result.1, "1234 567｜周 --")
    }

    func testReminderDefaultsPersistAndClampIntervals() async {
        let suiteName = "CodexUsageMenuTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let presenter = await MainActor.run { RecordingReminderPresenter() }
        let service = await MainActor.run {
            ReminderService(
                presenter: presenter,
                defaults: UserDefaults(suiteName: suiteName)!,
                secondsPerMinute: 3_600
            )
        }

        let defaults = await MainActor.run {
            (
                service.configuration(for: .sedentary),
                service.configuration(for: .hydration)
            )
        }
        XCTAssertEqual(defaults.0, ReminderConfiguration(isEnabled: false, intervalMinutes: 60))
        XCTAssertEqual(defaults.1, ReminderConfiguration(isEnabled: false, intervalMinutes: 45))

        await MainActor.run {
            service.updateInterval(0, for: .sedentary)
            service.setEnabled(true, for: .sedentary)
            service.updateInterval(999, for: .hydration)
        }

        let restoredService = await MainActor.run {
            ReminderService(
                presenter: presenter,
                defaults: UserDefaults(suiteName: suiteName)!,
                secondsPerMinute: 3_600
            )
        }
        let restored = await MainActor.run {
            (
                restoredService.configuration(for: .sedentary),
                restoredService.configuration(for: .hydration)
            )
        }
        XCTAssertEqual(restored.0, ReminderConfiguration(isEnabled: true, intervalMinutes: 1))
        XCTAssertEqual(restored.1, ReminderConfiguration(isEnabled: false, intervalMinutes: 720))

        await MainActor.run {
            service.setEnabled(false, for: .sedentary)
        }
    }

    func testEnabledReminderPresentsAndStopsAfterDisabling() async throws {
        let suiteName = "CodexUsageMenuTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let presenter = await MainActor.run { RecordingReminderPresenter() }
        let service = await MainActor.run {
            ReminderService(
                presenter: presenter,
                defaults: UserDefaults(suiteName: suiteName)!,
                secondsPerMinute: 0.02
            )
        }

        await MainActor.run {
            service.updateInterval(1, for: .hydration)
            service.setEnabled(true, for: .hydration)
        }
        try await Task.sleep(for: .milliseconds(35))

        let firstCount = await MainActor.run { presenter.presentedKinds.count }
        XCTAssertGreaterThanOrEqual(firstCount, 1)

        await MainActor.run {
            service.setEnabled(false, for: .hydration)
        }
        try await Task.sleep(for: .milliseconds(30))

        let finalCount = await MainActor.run { presenter.presentedKinds.count }
        XCTAssertEqual(finalCount, firstCount)
    }

    func testRelativeResetFormatting() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(
            ResetTimeFormatter.relativeText(to: now.addingTimeInterval(2 * 86_400 + 3 * 3_600), now: now),
            "2天3小时"
        )
        XCTAssertEqual(
            ResetTimeFormatter.relativeText(to: now.addingTimeInterval(2 * 3_600 + 14 * 60), now: now),
            "2小时14分"
        )
    }

    private func fixture(_ name: String) throws -> String {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: name,
                withExtension: "json",
                subdirectory: "Fixtures"
            )
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func makeSnapshot(remainingPercent: Int) -> UsageSnapshot {
        UsageSnapshot(
            windows: [
                UsageWindow(
                    id: "codex-primary",
                    usedPercent: 100 - remainingPercent,
                    durationMinutes: 10_080,
                    resetsAt: Date(timeIntervalSince1970: 1_800_000_000)
                )
            ],
            planType: "plus",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}

@MainActor
private final class RecordingReminderPresenter: ReminderPresenting {
    private(set) var presentedKinds: [ReminderKind] = []

    func present(_ kind: ReminderKind) {
        presentedKinds.append(kind)
    }
}

private enum StubError: LocalizedError {
    case offline

    var errorDescription: String? {
        "测试连接失败"
    }
}

private final class StubUsageClient: CodexUsageClient, @unchecked Sendable {
    private let queue = DispatchQueue(label: "CodexUsageMenuTests.StubUsageClient")
    private var results: [Result<UsageSnapshot, Error>]
    private let delay: Duration
    private var count = 0

    init(
        results: [Result<UsageSnapshot, Error>],
        delay: Duration = .zero
    ) {
        self.results = results
        self.delay = delay
    }

    var fetchCount: Int {
        queue.sync { count }
    }

    func fetchRateLimits() async throws -> UsageSnapshot {
        let result = queue.sync {
            count += 1
            if results.count == 1 {
                return results[0]
            }
            return results.removeFirst()
        }

        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        return try result.get()
    }

    func fetchAccount() async throws -> CodexAccount? {
        nil
    }

    func shutdown() {}
}
