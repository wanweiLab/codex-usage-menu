import Darwin
import Foundation

enum CodexClientError: LocalizedError {
    case executableNotFound
    case launchFailed(String)
    case timeout
    case emptyResponse
    case invalidResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "没有找到 Codex，请先安装并登录 ChatGPT/Codex。"
        case .launchFailed(let message):
            return "Codex 启动失败：\(message)"
        case .timeout:
            return "读取额度超时，请稍后重试。"
        case .emptyResponse:
            return "Codex 没有返回额度数据。"
        case .invalidResponse:
            return "Codex 返回了无法识别的数据。"
        case .serverError(let message):
            return "Codex 返回错误：\(message)"
        }
    }
}

struct CodexAppServerClient: Sendable {
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 15) {
        self.timeout = timeout
    }

    func fetchRateLimits() async throws -> UsageSnapshot {
        try await Task.detached(priority: .utility) {
            try fetchRateLimitsBlocking()
        }.value
    }

    func fetchAccount() async throws -> CodexAccount? {
        try await Task.detached(priority: .utility) {
            try fetchAccountBlocking()
        }.value
    }

    private func fetchRateLimitsBlocking() throws -> UsageSnapshot {
        let line = try performRequestBlocking(
            method: "account/rateLimits/read",
            paramsJSON: "null"
        )
        guard let snapshot = try Self.parseRateLimitResponse(line) else {
            throw CodexClientError.invalidResponse
        }
        return snapshot
    }

    private func fetchAccountBlocking() throws -> CodexAccount? {
        let line = try performRequestBlocking(
            method: "account/read",
            paramsJSON: #"{"refreshToken":false}"#
        )
        return try Self.parseAccountResponse(line)
    }

    private func performRequestBlocking(method: String, paramsJSON: String) throws -> String {
        guard let executableURL = CodexExecutableLocator.locate() else {
            throw CodexClientError.executableNotFound
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let debugEnabled = ProcessInfo.processInfo.environment["CODEX_USAGE_DEBUG"] == "1"

        do {
            try process.run()
        } catch {
            throw CodexClientError.launchFailed(error.localizedDescription)
        }

        let messages = [
            #"{"method":"initialize","id":1,"params":{"clientInfo":{"name":"wanwei_codex_usage_menu","title":"Codex Usage Menu","version":"0.1.0"}}}"#,
            #"{"method":"initialized","params":{}}"#,
            #"{"method":"\#(method)","id":2,"params":\#(paramsJSON)}"#
        ]

        do {
            for message in messages {
                guard let data = "\(message)\n".data(using: .utf8) else { continue }
                try inputPipe.fileHandleForWriting.write(contentsOf: data)
            }
            if debugEnabled {
                Self.debugLog("sent \(method)")
            }
        } catch {
            process.terminate()
            throw CodexClientError.launchFailed(error.localizedDescription)
        }

        func stopProcess() {
            try? inputPipe.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
            }
            process.waitUntilExit()
        }

        let outputHandle = outputPipe.fileHandleForReading
        var descriptor = pollfd(
            fd: outputHandle.fileDescriptor,
            events: Int16(POLLIN | POLLHUP | POLLERR),
            revents: 0
        )
        var bufferedData = Data()
        let deadline = Date().addingTimeInterval(timeout)

        while process.isRunning, deadline.timeIntervalSinceNow > 0 {
            descriptor.revents = 0
            let remainingMilliseconds = max(
                1,
                min(Int32.max, Int32(deadline.timeIntervalSinceNow * 1_000))
            )
            let pollResult = Darwin.poll(&descriptor, 1, remainingMilliseconds)

            if pollResult < 0 {
                if errno == EINTR { continue }
                let message = String(cString: strerror(errno))
                stopProcess()
                throw CodexClientError.launchFailed(message)
            }
            if pollResult == 0 { break }

            let hasReadableData = descriptor.revents & Int16(POLLIN) != 0
            let streamClosed = descriptor.revents & Int16(POLLHUP | POLLERR) != 0
            guard hasReadableData || streamClosed else { continue }

            let data = outputHandle.availableData
            if !data.isEmpty {
                bufferedData.append(data)
            }

            while let newlineIndex = bufferedData.firstIndex(of: 0x0A) {
                let lineData = bufferedData.prefix(upTo: newlineIndex)
                bufferedData.removeSubrange(...newlineIndex)
                guard let line = String(data: lineData, encoding: .utf8), !line.isEmpty else {
                    continue
                }

                if debugEnabled {
                    Self.debugLog("received JSON line (\(lineData.count) bytes)")
                }

                do {
                    if try Self.isRequestedResponse(line) {
                        stopProcess()
                        return line
                    }
                } catch {
                    stopProcess()
                    throw error
                }
            }

            if data.isEmpty, streamClosed { break }
        }

        stopProcess()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrText = String(data: errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if deadline.timeIntervalSinceNow <= 0 {
            if debugEnabled {
                Self.debugLog("timed out; stdout buffered=\(bufferedData.count) bytes; stderr=\(stderrText)")
            }
            throw CodexClientError.timeout
        }
        if !stderrText.isEmpty {
            throw CodexClientError.launchFailed(stderrText)
        }
        throw CodexClientError.emptyResponse
    }

    private static func debugLog(_ message: String) {
        guard let data = "[CodexUsage] \(message)\n".data(using: .utf8) else { return }
        try? FileHandle.standardError.write(contentsOf: data)
    }

    private static func isRequestedResponse(_ line: String) throws -> Bool {
        guard let data = line.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexClientError.invalidResponse
        }

        guard let responseID = root["id"] as? Int, responseID == 2 else {
            return false
        }

        if let error = root["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "未知错误"
            throw CodexClientError.serverError(message)
        }
        return true
    }

    static func parseRateLimitResponse(_ line: String) throws -> UsageSnapshot? {
        guard let data = line.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexClientError.invalidResponse
        }

        if let responseID = root["id"] as? Int, responseID == 2 {
            if let error = root["error"] as? [String: Any] {
                let message = error["message"] as? String ?? "未知错误"
                throw CodexClientError.serverError(message)
            }

            guard let result = root["result"] as? [String: Any] else {
                throw CodexClientError.invalidResponse
            }
            return try parseSnapshot(result)
        }

        return nil
    }

    static func parseAccountResponse(_ line: String) throws -> CodexAccount? {
        guard let data = line.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexClientError.invalidResponse
        }

        guard let responseID = root["id"] as? Int, responseID == 2 else {
            return nil
        }

        if let error = root["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "未知错误"
            throw CodexClientError.serverError(message)
        }

        guard let result = root["result"] as? [String: Any] else {
            throw CodexClientError.invalidResponse
        }
        guard let account = result["account"] as? [String: Any] else {
            return nil
        }

        return CodexAccount(
            email: account["email"] as? String,
            planType: account["planType"] as? String,
            type: account["type"] as? String ?? "unknown"
        )
    }

    private static func parseSnapshot(_ result: [String: Any]) throws -> UsageSnapshot {
        var snapshots: [(id: String, value: [String: Any])] = []

        if let byID = result["rateLimitsByLimitId"] as? [String: Any] {
            for (key, value) in byID {
                if let snapshot = value as? [String: Any] {
                    snapshots.append((key, snapshot))
                }
            }
        }

        if snapshots.isEmpty, let legacy = result["rateLimits"] as? [String: Any] {
            snapshots.append((legacy["limitId"] as? String ?? "codex", legacy))
        }

        guard !snapshots.isEmpty else {
            throw CodexClientError.invalidResponse
        }

        var windows: [UsageWindow] = []
        var planType: String?

        for snapshot in snapshots {
            planType = planType ?? snapshot.value["planType"] as? String

            for key in ["primary", "secondary"] {
                guard let window = snapshot.value[key] as? [String: Any],
                      let usedPercent = window["usedPercent"] as? Int else {
                    continue
                }

                let durationMinutes = window["windowDurationMins"] as? Int
                let resetSeconds = window["resetsAt"] as? Int
                let resetsAt = resetSeconds.map { Date(timeIntervalSince1970: TimeInterval($0)) }

                windows.append(
                    UsageWindow(
                        id: "\(snapshot.id)-\(key)",
                        usedPercent: min(max(usedPercent, 0), 100),
                        durationMinutes: durationMinutes,
                        resetsAt: resetsAt
                    )
                )
            }
        }

        guard !windows.isEmpty else {
            throw CodexClientError.emptyResponse
        }

        return UsageSnapshot(windows: windows, planType: planType, updatedAt: Date())
    }
}

private enum CodexExecutableLocator {
    static func locate() -> URL? {
        let fileManager = FileManager.default
        let environment = ProcessInfo.processInfo.environment
        let home = fileManager.homeDirectoryForCurrentUser.path

        let candidates = [
            environment["CODEX_CLI_PATH"],
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "\(home)/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ].compactMap { $0 }

        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }

        return locateFromPath(environment["PATH"])
    }

    private static func locateFromPath(_ path: String?) -> URL? {
        guard let path else { return nil }
        let fileManager = FileManager.default

        for directory in path.split(separator: ":") {
            let candidate = String(directory) + "/codex"
            if fileManager.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }
}
