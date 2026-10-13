import Foundation
import MenuBarCore

final class TerminalBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ value: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(value)
        if data.count > 512_000 { data.removeFirst(data.count - 512_000) }
    }
    var text: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
}

enum TerminalProbe {
    static func executable(_ provider: Provider) -> String? {
        let name = provider == .antigravity ? "agy" : "claude"
        let paths = ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", Collectors.home.path + "/.local/bin/\(name)"]
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    static func workspace(_ provider: Provider) -> String? {
        let key = provider.rawValue + "CLIWorkspace"
        guard let path = UserDefaults.standard.string(forKey: key), path.hasPrefix("/"), FileManager.default.fileExists(atPath: path) else { return nil }
        return path
    }
    static func fetch(_ provider: Provider) async throws -> Snapshot {
        guard let directory = workspace(provider) else { throw MeterError.message("‘CLI 연결’을 눌러 해당 도구에서 이미 신뢰한 작업 폴더를 선택해 주세요.") }
        guard let executable = executable(provider) else { throw MeterError.message("이 맥에 \(provider == .antigravity ? "agy" : "claude") CLI를 먼저 설치해 주세요.") }
        return try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
            // The CLI path is a positional argument, never interpolated into shell code.
            process.arguments = ["-q", "/dev/null", "/bin/zsh", "-c", "stty rows 80 cols 140; exec \"$1\"", "agentmeter-probe", executable]
            process.currentDirectoryURL = URL(fileURLWithPath: directory)
            var environment = ProcessInfo.processInfo.environment
            environment["TERM"] = "xterm-256color"
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            process.environment = environment
            let input = Pipe(), output = Pipe()
            process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
            let buffer = TerminalBuffer()
            output.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty { handle.readabilityHandler = nil }
                else { buffer.append(chunk) }
            }
            try process.run()
            defer {
                // Stop only the CLI spawned by our script. Existing user sessions are never touched.
                let finder = Process(); finder.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
                finder.arguments = ["-P", String(process.processIdentifier)]
                let children = Pipe(); finder.standardOutput = children; finder.standardError = FileHandle.nullDevice
                if (try? finder.run()) != nil {
                    let data = children.fileHandleForReading.readDataToEndOfFile(); finder.waitUntilExit()
                    for child in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                        if let pid = Int32(child) { kill(pid, SIGTERM) }
                    }
                }
                try? input.fileHandleForWriting.close()
                if process.isRunning { process.terminate() }
                let deadline = Date().addingTimeInterval(0.5)
                while process.isRunning && Date() < deadline { usleep(20_000) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
                output.fileHandleForReading.readabilityHandler = nil
            }
            let deadline = Date().addingTimeInterval(25)
            var sent = false, firstMeasurement: Date?, snapshot: Snapshot?
            while process.isRunning && Date() < deadline {
                let text = buffer.text, clean = TerminalScreen.render(text)
                let lower = clean.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
                if lower.contains("trust the contents") || lower.contains("trust this folder") || lower.contains("trust this directory") || lower.contains("is this a project you created") {
                    throw MeterError.message("선택한 폴더를 아직 신뢰하지 않았어요. 해당 폴더에서 CLI를 직접 열어 초기 설정을 마친 뒤 다시 연결해 주세요.")
                }
                if !sent && (lower.contains("for shortcuts") || lower.contains("bypass permissions on") || lower.contains("shift+tab to cycle")) {
                    try input.fileHandleForWriting.write(contentsOf: Data("/usage\r".utf8)); sent = true
                }
                if sent {
                    let parsed = provider == .antigravity ? UsageParser.antigravityTerminal(text) : UsageParser.claudeTerminal(text)
                    if !parsed.quotas.isEmpty {
                        snapshot = parsed
                        if firstMeasurement == nil { firstMeasurement = Date() }
                        if Date().timeIntervalSince(firstMeasurement!) > 2 { return parsed }
                    }
                }
                usleep(100_000)
            }
            if let snapshot { return snapshot }
            throw MeterError.message("CLI의 /usage 화면을 읽지 못했어요. 선택한 폴더에서 도구를 직접 열고 로그인·초기 설정을 확인해 주세요.")
        }.value
    }
}
