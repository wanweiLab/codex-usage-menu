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
        let line = #"{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":32,"windowDurationMins":10080,"resetsAt":1785289790},"secondary":{"usedPercent":18,"windowDurationMins":300,"resetsAt":1784694000},"planType":"plus"},"rateLimitsByLimitId":null}}"#

        let snapshot = try XCTUnwrap(CodexAppServerClient.parseRateLimitResponse(line))

        XCTAssertEqual(snapshot.weeklyWindow?.usedPercent, 32)
        XCTAssertEqual(snapshot.weeklyWindow?.remainingPercent, 68)
        XCTAssertEqual(snapshot.weeklyWindow?.durationMinutes, 10_080)
        XCTAssertEqual(snapshot.shortWindow?.usedPercent, 18)
        XCTAssertEqual(snapshot.shortWindow?.durationMinutes, 300)
        XCTAssertEqual(snapshot.planType, "plus")
    }

    func testParsesCurrentMultiBucketResponse() throws {
        let line = #"{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":1,"windowDurationMins":10080,"resetsAt":1785289790},"secondary":null,"planType":"plus"},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":1,"windowDurationMins":10080,"resetsAt":1785289790},"secondary":null,"planType":"plus"}}}}"#

        let snapshot = try XCTUnwrap(CodexAppServerClient.parseRateLimitResponse(line))

        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.weeklyWindow?.usedPercent, 1)
        XCTAssertNil(snapshot.shortWindow)
    }

    func testIgnoresUnrelatedNotifications() throws {
        let line = #"{"method":"remoteControl/status/changed","params":{"status":"disabled"}}"#
        XCTAssertNil(try CodexAppServerClient.parseRateLimitResponse(line))
    }

    func testParsesChatGPTAccount() throws {
        let line = #"{"id":2,"result":{"account":{"type":"chatgpt","email":"allen@example.com","planType":"plus"},"requiresOpenaiAuth":true}}"#

        let account = try XCTUnwrap(CodexAppServerClient.parseAccountResponse(line))

        XCTAssertEqual(account.email, "allen@example.com")
        XCTAssertEqual(account.planType, "plus")
        XCTAssertEqual(account.type, "chatgpt")
    }

    func testParsesApiKeyAccountWithoutEmail() throws {
        let line = #"{"id":2,"result":{"account":{"type":"apiKey"},"requiresOpenaiAuth":true}}"#

        let account = try XCTUnwrap(CodexAppServerClient.parseAccountResponse(line))

        XCTAssertNil(account.email)
        XCTAssertNil(account.planType)
        XCTAssertEqual(account.type, "apiKey")
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
}
