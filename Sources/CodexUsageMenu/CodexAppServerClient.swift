import Darwin
import Foundation

enum CodexClientError: LocalizedError {
    case executableNotFound
    case launchFailed(String)
    case timeout
    case connectionClosed
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
        case .connectionClosed:
            return "Codex 连接已断开，请稍后重试。"
        case .emptyResponse:
            return "Codex 没有返回额度数据。"
        case .invalidResponse:
            return "Codex 返回了无法识别的数据。"
        case .serverError(let message):
            return "Codex 返回错误：\(message)"
        }
    }

    var diagnosticCode: String {
        switch self {
        case .executableNotFound: "executable_not_found"
        case .launchFailed: "launch_failed"
        case .timeout: "timeout"
        case .connectionClosed: "connection_closed"
        case .emptyResponse: "empty_response"
        case .invalidResponse: "invalid_response"
        case .serverError: "server_error"
        }
    }

    var canRetryWithNewConnection: Bool {
        switch self {
        case .launchFailed, .timeout, .connectionClosed, .emptyResponse, .invalidResponse:
            true
        case .executableNotFound, .serverError:
            false
        }
    }
}

protocol CodexUsageClient: Sendable {
    func fetchRateLimits() async throws -> UsageSnapshot
    func fetchAccount() async throws -> CodexAccount?
    func shutdown()
}

private final class CodexAppServerConnection: @unchecked Sendable {
    private let timeout: TimeInterval
    private let queue = DispatchQueue(label: "lab.wanwei.codex-pulse.app-server")
    private let debugEnabled = ProcessInfo.processInfo.environment["CODEX_USAGE_DEBUG"] == "1"

    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var bufferedData = Data()
    private var stderrTail = Data()
    private var nextRequestID = 2

    init(timeout: TimeInterval) {
        self.timeout = timeout
    }

    func request(method: String, paramsJSON: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    continuation.resume(
                        returning: try requestWithReconnect(
                            method: method,
                            paramsJSON: paramsJSON
                        )
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func shutdown() {
        queue.async { [self] in
            stopProcess()
        }
    }

    private func requestWithReconnect(method: String, paramsJSON: String) throws -> String {
        for attempt in 0...1 {
            do {
                return try performRequest(method: method, paramsJSON: paramsJSON)
            } catch let error as CodexClientError
                where attempt == 0 && error.canRetryWithNewConnection {
                debugLog("request \(method) failed (\(error.diagnosticCode)); reconnecting")
                stopProcess()
            }
        }

        throw CodexClientError.emptyResponse
    }

    private func performRequest(method: String, paramsJSON: String) throws -> String {
        try ensureStarted()

        guard let inputPipe else {
            throw CodexClientError.connectionClosed
        }

        let requestID = nextRequestID
        nextRequestID += 1
        let request = #"{"method":"\#(method)","id":\#(requestID),"params":\#(paramsJSON)}"#

        do {
            guard let data = "\(request)\n".data(using: .utf8) else {
                throw CodexClientError.invalidResponse
            }
            try inputPipe.fileHandleForWriting.write(contentsOf: data)
            debugLog("sent \(method) id=\(requestID)")
        } catch let error as CodexClientError {
            throw error
        } catch {
            throw CodexClientError.launchFailed(error.localizedDescription)
        }

        return try readResponse(requestID: requestID)
    }

    private func ensureStarted() throws {
        if process?.isRunning == true {
            return
        }

        stopProcess()

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

        do {
            try process.run()
        } catch {
            throw CodexClientError.launchFailed(error.localizedDescription)
        }

        self.process = process
        self.inputPipe = inputPipe
        self.outputPipe = outputPipe
        self.errorPipe = errorPipe
        bufferedData.removeAll(keepingCapacity: true)
        stderrTail.removeAll(keepingCapacity: true)
        nextRequestID = 2

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async { [weak self] in
                self?.appendStderr(data)
            }
        }

        let initializationMessages = [
            #"{"method":"initialize","id":1,"params":{"clientInfo":{"name":"wanwei_codex_pulse","title":"Codex Pulse","version":"0.4.1"}}}"#,
            #"{"method":"initialized","params":{}}"#
        ]

        do {
            for message in initializationMessages {
                guard let data = "\(message)\n".data(using: .utf8) else {
                    continue
                }
                try inputPipe.fileHandleForWriting.write(contentsOf: data)
            }
            debugLog("started persistent app-server")
        } catch {
            stopProcess()
            throw CodexClientError.launchFailed(error.localizedDescription)
        }
    }

    private func readResponse(requestID: Int) throws -> String {
        guard let outputPipe else {
            throw CodexClientError.connectionClosed
        }

        let outputHandle = outputPipe.fileHandleForReading
        var descriptor = pollfd(
            fd: outputHandle.fileDescriptor,
            events: Int16(POLLIN | POLLHUP | POLLERR),
            revents: 0
        )
        let deadline = Date().addingTimeInterval(timeout)

        while deadline.timeIntervalSinceNow > 0 {
            while let line = popBufferedLine() {
                if try isMatchingResponse(line, requestID: requestID) {
                    debugLog("received response id=\(requestID)")
                    return line
                }
            }

            guard process?.isRunning == true else {
                throw CodexClientError.connectionClosed
            }

            descriptor.revents = 0
            let remainingMilliseconds = max(
                1,
                min(Int32.max, Int32(deadline.timeIntervalSinceNow * 1_000))
            )
            let pollResult = Darwin.poll(&descriptor, 1, remainingMilliseconds)

            if pollResult < 0 {
                if errno == EINTR {
                    continue
                }
                throw CodexClientError.launchFailed(String(cString: strerror(errno)))
            }
            if pollResult == 0 {
                break
            }

            let hasReadableData = descriptor.revents & Int16(POLLIN) != 0
            let streamClosed = descriptor.revents & Int16(POLLHUP | POLLERR) != 0
            guard hasReadableData || streamClosed else {
                continue
            }

            let data = outputHandle.availableData
            if !data.isEmpty {
                bufferedData.append(data)
            }
            if data.isEmpty, streamClosed {
                throw CodexClientError.connectionClosed
            }
        }

        throw CodexClientError.timeout
    }

    private func popBufferedLine() -> String? {
        guard let newlineIndex = bufferedData.firstIndex(of: 0x0A) else {
            return nil
        }

        let lineData = bufferedData.prefix(upTo: newlineIndex)
        bufferedData.removeSubrange(...newlineIndex)
        guard !lineData.isEmpty else {
            return ""
        }
        return String(data: lineData, encoding: .utf8)
    }

    private func isMatchingResponse(_ line: String, requestID: Int) throws -> Bool {
        guard !line.isEmpty,
              let data = line.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            debugLog("ignored non-JSON app-server output")
            return false
        }

        guard let responseID = root["id"] as? Int, responseID == requestID else {
            return false
        }

        if let error = root["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "未知错误"
            throw CodexClientError.serverError(message)
        }
        return true
    }

    private func stopProcess() {
        guard process != nil || inputPipe != nil || outputPipe != nil || errorPipe != nil else {
            return
        }

        try? inputPipe?.fileHandleForWriting.close()
        if process?.isRunning == true {
            process?.terminate()
        }
        process?.waitUntilExit()
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        try? outputPipe?.fileHandleForReading.close()
        try? errorPipe?.fileHandleForReading.close()

        process = nil
        inputPipe = nil
        outputPipe = nil
        errorPipe = nil
        bufferedData.removeAll(keepingCapacity: false)
    }

    private func appendStderr(_ data: Data) {
        stderrTail.append(data)
        let maximumTailBytes = 4_096
        if stderrTail.count > maximumTailBytes {
            stderrTail.removeFirst(stderrTail.count - maximumTailBytes)
        }
    }

    private func debugLog(_ message: String) {
        guard debugEnabled,
              let data = "[CodexPulse] \(message)\n".data(using: .utf8) else {
            return
        }
        try? FileHandle.standardError.write(contentsOf: data)
    }
}

struct CodexAppServerClient: CodexUsageClient, Sendable {
    private let connection: CodexAppServerConnection

    init(timeout: TimeInterval = 15) {
        connection = CodexAppServerConnection(timeout: timeout)
    }

    func fetchRateLimits() async throws -> UsageSnapshot {
        let line = try await connection.request(
            method: "account/rateLimits/read",
            paramsJSON: "null"
        )
        guard let snapshot = try Self.parseRateLimitResponse(line) else {
            throw CodexClientError.invalidResponse
        }
        return snapshot
    }

    func fetchAccount() async throws -> CodexAccount? {
        let line = try await connection.request(
            method: "account/read",
            paramsJSON: #"{"refreshToken":false}"#
        )
        return try Self.parseAccountResponse(line)
    }

    func shutdown() {
        connection.shutdown()
    }

    static var executableDisplayPath: String? {
        guard let path = CodexExecutableLocator.locate()?.path else {
            return nil
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    static func parseRateLimitResponse(_ line: String) throws -> UsageSnapshot? {
        guard let data = line.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexClientError.invalidResponse
        }

        if root["id"] is Int {
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

        guard root["id"] is Int else {
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
