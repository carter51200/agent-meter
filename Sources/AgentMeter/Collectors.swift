import Foundation
import Security
import LocalAuthentication
import MenuBarCore

enum MeterError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

// Redirects are refused so authorization never follows an unexpected origin.
final class RequestPolicy: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    let loopback: Bool
    init(loopback: Bool = false) { self.loopback = loopback }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Antigravity's own local server uses a self-signed certificate. This exception is ONLY for loopback.
        if loopback, challenge.protectionSpace.host == "127.0.0.1",
           challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else { completionHandler(.performDefaultHandling, nil) }
    }
}

enum Collectors {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    private static let keychainLock = NSLock()
    static func session(loopback: Bool = false) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = loopback ? 2 : 12
        config.timeoutIntervalForResource = loopback ? 3 : 15
        config.httpShouldSetCookies = false
        config.urlCache = nil
        return URLSession(configuration: config, delegate: RequestPolicy(loopback: loopback), delegateQueue: nil)
    }
    static func requestJSON(_ request: URLRequest, loopback: Bool = false) async throws -> [String: Any] {
        let client = session(loopback: loopback)
        defer { client.invalidateAndCancel() }
        let (data, response) = try await client.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MeterError.message("서버 응답을 확인할 수 없어요.") }
        switch http.statusCode {
        case 200..<300: return try UsageParser.object(data)
        case 401: throw MeterError.message("로그인이 만료됐어요. 해당 도구에서 다시 로그인해 주세요.")
        case 403: throw MeterError.message("계정에 사용량 조회 권한이 없어요. 해당 도구의 로그인과 구독을 확인해 주세요.")
        case 429: throw MeterError.message("조회 요청이 잠시 제한됐어요. 다음 자동 갱신을 기다려 주세요.")
        default: throw MeterError.message("조회 서버 오류 (\(http.statusCode)). 잠시 후 새로고침해 주세요.")
        }
    }
    static func fetch(_ provider: Provider, allowKeychainPrompt: Bool = false, forceCLI: Bool = false) async -> Snapshot {
        do {
            if forceCLI && provider != .codex { return try await cliSnapshot(provider) }
            switch provider {
            case .codex: return try await codex()
            case .claude:
                do { return try await claude(allowPrompt: allowKeychainPrompt) }
                catch {
                    guard TerminalProbe.workspace(.claude) != nil else { throw error }
                    return try await cliSnapshot(.claude)
                }
            case .antigravity:
                // Configured CLI workspaces support current agy builds whose local API is private.
                if TerminalProbe.workspace(.antigravity) != nil { return try await TerminalProbe.fetch(.antigravity) }
                return try await antigravity()
            }
        } catch {
            let message: String
            if let error = error as? MeterError { message = error.localizedDescription }
            else if error is URLError { message = "연결할 수 없어요. 네트워크와 도구 실행 상태를 확인해 주세요." }
            else { message = "사용량 응답 형식을 읽을 수 없어요. 도구 업데이트 후 다시 확인해 주세요." }
            // A failed read is unknown, never zero remaining and never a cached reading from another account.
            return Snapshot(provider: provider, issue: message)
        }
    }
    static func cliSnapshot(_ provider: Provider) async throws -> Snapshot {
        var snapshot = try await TerminalProbe.fetch(provider)
        if provider == .claude, let auth = try? claudeCredential(allowPrompt: false), let oauth = auth["claudeAiOauth"] as? [String: Any],
           let plan = UsageParser.claudePlan(oauth) {
            snapshot.plan = plan; snapshot.planSource = "로그인 정보에 기록된 요금제 · 변경 후 재로그인이 필요할 수 있어요."
        }
        return snapshot
    }
    static func codex() async throws -> Snapshot {
        let folder = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".codex")
        let auth: [String: Any]
        do { auth = try UsageParser.object(Data(contentsOf: folder.appendingPathComponent("auth.json"))) }
        catch { throw MeterError.message("Codex CLI에서 로그인해 주세요. 터미널 명령: codex login") }
        guard let tokens = auth["tokens"] as? [String: Any], let token = tokens["access_token"] as? String, !token.isEmpty else {
            throw MeterError.message("ChatGPT 계정 로그인이 필요해요. API 키의 비용과 구독 한도는 별개예요.")
        }
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("AgentMeter/0.3", forHTTPHeaderField: "User-Agent")
        if let account = tokens["account_id"] as? String { request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id") }
        return UsageParser.codex(try await requestJSON(request))
    }
    static func claudeCredential(allowPrompt: Bool) throws -> [String: Any] {
        let folder = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".claude")
        let file = folder.appendingPathComponent(".credentials.json")
        if let data = try? Data(contentsOf: file), let root = try? UsageParser.object(data), root["claudeAiOauth"] != nil { return root }
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "Claude Code-credentials",
                                  kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        if !allowPrompt {
            let context = LAContext(); context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
            // Classic application-access ACL dialogs also need the UI-fail policy.
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        }
        // Claude Code can use the classic login keychain, where the modern
        // authentication-context policy alone does not suppress ACL prompts.
        // Serialize our reads and restore this process's interaction policy.
        keychainLock.lock()
        var previousInteraction: DarwinBoolean = true
        let restoreInteraction = !allowPrompt && SecKeychainGetUserInteractionAllowed(&previousInteraction) == errSecSuccess
        if restoreInteraction { SecKeychainSetUserInteractionAllowed(false) }
        defer {
            if restoreInteraction { SecKeychainSetUserInteractionAllowed(previousInteraction.boolValue) }
            keychainLock.unlock()
        }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecInteractionNotAllowed || status == errSecAuthFailed || status == errSecUserCanceled {
            throw MeterError.message("‘Claude 연결’을 눌러 macOS 키체인 접근을 허용해 주세요.")
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw MeterError.message("Claude Code 로그인을 찾지 못했어요. 터미널에서 claude를 열고 /login 후 연결해 주세요.")
        }
        return try UsageParser.object(data)
    }
    static func claude(allowPrompt: Bool) async throws -> Snapshot {
        let auth = try await Task.detached { try claudeCredential(allowPrompt: allowPrompt) }.value
        guard let oauth = auth["claudeAiOauth"] as? [String: Any], let token = oauth["accessToken"] as? String, !token.isEmpty else {
            throw MeterError.message("Claude Code 구독 로그인 정보가 없어요. claude에서 /login을 실행해 주세요.")
        }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("AgentMeter/0.3", forHTTPHeaderField: "User-Agent")
        var snapshot = UsageParser.claude(try await requestJSON(request))
        snapshot.plan = UsageParser.claudePlan(oauth)
        snapshot.planSource = "로그인 정보에 기록된 요금제 · 변경 후 재로그인이 필요할 수 있어요."
        return snapshot
    }
    static func command(_ path: String, _ arguments: [String], timeout: Double = 4) async throws -> String {
        try await Task.detached {
            let process = Process(); process.executableURL = URL(fileURLWithPath: path); process.arguments = arguments
            process.currentDirectoryURL = home
            let output = Pipe(); process.standardOutput = output
            process.standardError = FileHandle.nullDevice; process.standardInput = FileHandle.nullDevice
            try process.run()
            // Drain concurrently, including process lists larger than the OS pipe buffer.
            let reader = Task.detached { output.fileHandleForReading.readDataToEndOfFile() }
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline { usleep(30_000) }
            if process.isRunning { process.terminate() }
            let killDeadline = Date().addingTimeInterval(0.3)
            while process.isRunning && Date() < killDeadline { usleep(20_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            let data = await reader.value
            return String(decoding: data, as: UTF8.self)
        }.value
    }
    static func flag(_ name: String, in command: String) -> String? {
        let pattern = "(?:^|\\s)" + NSRegularExpression.escapedPattern(for: name) + "(?:=|\\s+)([^\\s]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: command, range: NSRange(command.startIndex..., in: command)),
              let range = Range(match.range(at: 1), in: command) else { return nil }
        return String(command[range]).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }
    static func antigravity() async throws -> Snapshot {
        // Read command lines only to locate the provider's own local server and its CSRF token; never log them.
        let list = try await command("/bin/ps", ["-ax", "-o", "pid=,command="])
        var servers: [(String, String, String?, String?)] = []
        for line in list.split(separator: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
            guard parts.count == 2, Int(parts[0]) != nil else { continue }
            let commandLine = String(parts[1]), lower = commandLine.lowercased()
            let languageServer = (lower.contains("language_server") || lower.contains("language-server")) && lower.contains("antigravity")
            let agy = lower.hasPrefix("/opt/homebrew/bin/agy ") || lower.hasPrefix("/usr/local/bin/agy ") || lower.hasPrefix(home.path.lowercased() + "/.local/bin/agy ") || lower == "agy" || lower.hasPrefix("agy ")
            guard languageServer || agy else { continue }
            let csrf = flag("--csrf_token", in: commandLine) ?? ""
            if languageServer && csrf.isEmpty { continue }
            servers.append((String(parts[0]), csrf, flag("--extension_server_port", in: commandLine), flag("--extension_server_csrf_token", in: commandLine)))
        }
        guard !servers.isEmpty else { throw MeterError.message("이 맥에서 Antigravity 또는 agy를 실행하고 로그인한 뒤 새로고침해 주세요.") }
        let deadline = Date().addingTimeInterval(18)
        for (pid, csrf, fallbackPort, fallbackToken) in servers.prefix(4) {
            let sockets = try await command("/usr/sbin/lsof", ["-nP", "-a", "-p", pid, "-iTCP", "-sTCP:LISTEN", "-F", "n"])
            var ports: [Int] = []
            for line in sockets.split(separator: "\n") where line.hasPrefix("n") {
                if let last = line.split(separator: ":").last, let port = Int(last), (1...65535).contains(port), !ports.contains(port) { ports.append(port) }
            }
            var targets = ports.prefix(6).map { ("https", $0, csrf) }
            if let fallbackPort, let port = Int(fallbackPort), (1...65535).contains(port) { targets.append(("http", port, fallbackToken ?? csrf)) }
            for (scheme, port, token) in targets {
                for method in ["RetrieveUserQuotaSummary", "GetUserStatus"] {
                    guard Date() < deadline else { throw MeterError.message("Antigravity 사용량 서버가 응답하지 않아요. 앱 또는 CLI를 다시 열고 확인해 주세요.") }
                    let url = URL(string: "\(scheme)://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/\(method)")!
                    var request = URLRequest(url: url); request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
                    if !token.isEmpty { request.setValue(token, forHTTPHeaderField: "X-Codeium-Csrf-Token") }
                    request.httpBody = try JSONSerialization.data(withJSONObject: ["metadata": ["ideName": "antigravity", "extensionName": "antigravity", "locale": "en", "ideVersion": "unknown"]])
                    if let json = try? await requestJSON(request, loopback: true) {
                        var snapshot = UsageParser.antigravity(json)
                        if !snapshot.quotas.isEmpty {
                            if snapshot.plan == nil, method == "RetrieveUserQuotaSummary", Date() < deadline {
                                var statusRequest = request
                                statusRequest.url = URL(string: "\(scheme)://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/GetUserStatus")!
                                if let status = try? await requestJSON(statusRequest, loopback: true) {
                                    let identity = UsageParser.antigravity(status)
                                    snapshot.plan = identity.plan; snapshot.planSource = identity.planSource
                                }
                            }
                            return snapshot
                        }
                    }
                }
            }
        }
        throw MeterError.message("Antigravity는 실행 중이지만 한도에 접근할 수 없어요. 최신 버전의 로컬 서버 지원을 확인해 주세요.")
    }
}
