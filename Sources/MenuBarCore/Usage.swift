import Foundation
import CoreFoundation

public enum Provider: String, CaseIterable, Codable, Sendable {
    case codex, claude, antigravity
    public var title: String {
        switch self { case .codex: return "Codex"; case .claude: return "Claude Code"; case .antigravity: return "Antigravity" }
    }
    public var short: String {
        switch self { case .codex: return "C"; case .claude: return "L"; case .antigravity: return "A" }
    }
}

public struct Quota: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var remaining: Double
    public var resetsAt: Date?
    public var resetDescription: String?
    public init(id: String, title: String, remaining: Double, resetsAt: Date? = nil, resetDescription: String? = nil) {
        self.id = id; self.title = title; self.remaining = remaining
        self.resetsAt = resetsAt; self.resetDescription = resetDescription
    }
}

public struct Snapshot: Identifiable, Codable, Sendable {
    public var id: Provider { provider }
    public var provider: Provider
    public var quotas: [Quota]
    public var source: String
    public var updatedAt: Date?
    public var issue: String?
    public var account: String?
    public var minimum: Double? { quotas.map(\.remaining).min() }
    public init(provider: Provider, quotas: [Quota] = [], source: String = "", updatedAt: Date? = nil, issue: String? = nil, account: String? = nil) {
        self.provider = provider; self.quotas = quotas; self.source = source
        self.updatedAt = updatedAt; self.issue = issue; self.account = account
    }
}

public enum UsageParser {
    public static func terminalText(_ raw: String) -> String {
        var value = raw
        for pattern in ["\\u{001B}\\][^\\u{0007}]*(?:\\u{0007}|\\u{001B}\\\\)", "\\u{001B}\\[[0-?]*[ -/]*[@-~]"] {
            // Foundation regex uses literal control characters rather than Swift scalar notation.
            let regexPattern = pattern.replacingOccurrences(of: "\\u{001B}", with: "\u{001B}").replacingOccurrences(of: "\\u{0007}", with: "\u{0007}")
            if let regex = try? NSRegularExpression(pattern: regexPattern) {
                value = regex.stringByReplacingMatches(in: value, range: NSRange(value.startIndex..., in: value), withTemplate: "")
            }
        }
        return value.replacingOccurrences(of: "\r", with: "\n")
    }
    private static func capture(_ pattern: String, from string: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) else { return nil }
        return (1..<match.numberOfRanges).map { index in Range(match.range(at: index), in: string).map { String(string[$0]) } ?? "" }
    }
    public static func antigravityTerminal(_ raw: String, now: Date = Date()) -> Snapshot {
        let text = terminalText(raw)
        guard let start = text.range(of: "Models & Quota", options: .backwards) else { return Snapshot(provider: .antigravity, issue: "CLI 사용량 화면을 찾지 못했어요.") }
        let lines = String(text[start.lowerBound...]).components(separatedBy: .newlines)
        var group = "모델", title: String?, percentage: Double?, quotas: [Quota] = []
        func append(reset: Date? = nil, description: String? = nil) {
            guard let title, let percentage, (0...100).contains(percentage) else { return }
            let id = group + "-" + title
            if !quotas.contains(where: { $0.id == id }) { quotas.append(Quota(id: id, title: group + " · " + title, remaining: percentage, resetsAt: reset, resetDescription: description)) }
        }
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("MODELS"), trimmed == trimmed.uppercased() {
                append(); title = nil; percentage = nil
                group = trimmed.contains("GEMINI") ? "Gemini" : "Claude + GPT"
            } else if trimmed.contains("Weekly Limit Remaining") || trimmed.contains("Five Hour Limit Remaining") {
                append(); title = trimmed.contains("Weekly") ? "주간" : "5시간"; percentage = nil
            } else if title != nil, let captures = capture("([0-9]+(?:\\.[0-9]+)?)%", from: trimmed), let value = Double(captures[0]) {
                percentage = value
            } else if trimmed.contains("Refreshes in"), percentage != nil {
                let duration = capture("Refreshes in\\s+(?:([0-9]+)d\\s*)?(?:([0-9]+)h\\s*)?(?:([0-9]+)m)?", from: trimmed) ?? []
                let seconds = duration.count == 3 ? (Double(duration[0]) ?? 0) * 86400 + (Double(duration[1]) ?? 0) * 3600 + (Double(duration[2]) ?? 0) * 60 : 0
                append(reset: seconds > 0 ? now.addingTimeInterval(seconds) : nil)
                title = nil; percentage = nil
            } else if trimmed.contains("Quota available"), percentage != nil {
                append(description: "현재 사용 가능"); title = nil; percentage = nil
            }
        }
        append()
        return Snapshot(provider: .antigravity, quotas: quotas, source: "계정 한도 · agy /usage", updatedAt: now,
                        issue: quotas.isEmpty ? "CLI 사용량 화면에서 측정값을 읽지 못했어요." : nil)
    }
    public static func claudeTerminal(_ raw: String, now: Date = Date()) -> Snapshot {
        let text = TerminalScreen.render(raw)
        var title: String?, quotas: [Quota] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            let lower = trimmed.lowercased()
            if lower.contains("current session") { title = "5시간" }
            else if lower.contains("current week") {
                let model = capture("current week\\s*\\(([^)]+)\\)", from: trimmed)?.first
                title = model.map { $0.lowercased() == "all models" ? "주간" : $0 + " · 주간" } ?? "주간"
            }
            if let title, let capture = capture("([0-9]+(?:\\.[0-9]+)?)%\\s*(used|left|remaining)", from: trimmed), let number = Double(capture[0]), (0...100).contains(number) {
                let remaining = capture[1].lowercased() == "used" ? 100 - number : number
                if !quotas.contains(where: { $0.id == title }) { quotas.append(Quota(id: title, title: title, remaining: remaining)) }
            } else if lower.hasPrefix("resets"), let index = quotas.indices.last {
                quotas[index].resetDescription = trimmed
            }
        }
        return Snapshot(provider: .claude, quotas: quotas, source: "계정 한도 · claude /usage", updatedAt: now,
                        issue: quotas.isEmpty ? "CLI 사용량 화면에서 측정값을 읽지 못했어요." : nil)
    }
    public static func object(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ParseError.invalid }
        return value
    }
    public enum ParseError: Error { case invalid }
    private static func number(_ value: Any?) -> Double? {
        guard let value, !(value is NSNull) else { return nil }
        if let n = value as? NSNumber {
            guard CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
            let d = n.doubleValue; return d.isFinite ? d : nil
        }
        if let s = value as? String, let d = Double(s), d.isFinite { return d }
        return nil
    }
    private static func percent(_ value: Any?) -> Double? {
        guard let n = number(value), (0...100).contains(n) else { return nil }
        return n
    }
    public static func date(_ value: Any?) -> Date? {
        if let n = number(value), n > 0 { return Date(timeIntervalSince1970: n) }
        guard let s = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
    public static func durationTitle(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "사용 한도" }
        if seconds == 604800 { return "주간" }
        if seconds.truncatingRemainder(dividingBy: 86400) == 0 { return "\(Int(seconds / 86400))일" }
        if seconds.truncatingRemainder(dividingBy: 3600) == 0 { return "\(Int(seconds / 3600))시간" }
        return "\(Int(seconds / 60))분"
    }
    public static func codex(_ root: [String: Any], now: Date = Date()) -> Snapshot {
        var quotas: [Quota] = []
        func append(_ limit: [String: Any], prefix: String, name: String?) {
            for key in ["primary_window", "secondary_window"] {
                guard let window = limit[key] as? [String: Any], let used = percent(window["used_percent"]) else { continue }
                // A primary window can be WEEKLY; use the reported duration rather than its position.
                let title = durationTitle(number(window["limit_window_seconds"]))
                let reset = date(window["reset_at"]) ?? number(window["reset_after_seconds"]).flatMap { $0 >= 0 ? now.addingTimeInterval($0) : nil }
                quotas.append(Quota(id: prefix + key, title: [name, title].compactMap { $0 }.joined(separator: " · "), remaining: 100 - used, resetsAt: reset))
            }
        }
        if let limit = root["rate_limit"] as? [String: Any] { append(limit, prefix: "main-", name: nil) }
        for (i, extra) in ((root["additional_rate_limits"] as? [[String: Any]]) ?? []).enumerated() {
            if let limit = extra["rate_limit"] as? [String: Any] {
                append(limit, prefix: "extra-\(i)-", name: extra["limit_name"] as? String ?? extra["metered_feature"] as? String ?? "추가 한도")
            }
        }
        return Snapshot(provider: .codex, quotas: quotas, source: "계정 한도 · Codex 로그인", updatedAt: now,
                        issue: quotas.isEmpty ? "이 계정은 조회 가능한 한도를 반환하지 않았어요." : nil, account: root["email"] as? String)
    }
    public static func claude(_ root: [String: Any], now: Date = Date()) -> Snapshot {
        var quotas: [Quota] = []
        let keys = [("five_hour", "5시간"), ("seven_day", "주간"), ("seven_day_opus", "Opus · 주간"), ("seven_day_sonnet", "Sonnet · 주간")]
        for (key, title) in keys {
            guard let window = root[key] as? [String: Any], let used = percent(window["utilization"]) else { continue }
            quotas.append(Quota(id: key, title: title, remaining: 100 - used, resetsAt: date(window["resets_at"])))
        }
        for key in root.keys.sorted() where key.hasPrefix("seven_day_") && !keys.contains(where: { $0.0 == key }) {
            guard let window = root[key] as? [String: Any], let used = percent(window["utilization"]) else { continue }
            let name = key.replacingOccurrences(of: "seven_day_", with: "").replacingOccurrences(of: "_", with: " ").capitalized
            quotas.append(Quota(id: key, title: name + " · 주간", remaining: 100 - used, resetsAt: date(window["resets_at"])))
        }
        for (i, window) in ((root["limits"] as? [[String: Any]]) ?? []).enumerated() {
            guard let used = percent(window["utilization"]), window["weekly_scoped"] != nil else { continue }
            let name = window["display_name"] as? String ?? window["name"] as? String ?? "모델별 주간"
            quotas.append(Quota(id: "scoped-\(i)", title: name, remaining: 100 - used, resetsAt: date(window["resets_at"])))
        }
        return Snapshot(provider: .claude, quotas: quotas, source: "계정 한도 · Claude Code 로그인", updatedAt: now,
                        issue: quotas.isEmpty ? "이 계정은 조회 가능한 한도를 반환하지 않았어요." : nil)
    }
    public static func antigravity(_ root: [String: Any], now: Date = Date()) -> Snapshot {
        var quotas: [Quota] = []
        let response = root["response"] as? [String: Any] ?? root
        for (groupIndex, group) in ((response["groups"] as? [[String: Any]]) ?? []).enumerated() {
            let groupName = group["displayName"] as? String ?? "모델"
            for (index, bucket) in ((group["buckets"] as? [[String: Any]]) ?? []).enumerated() {
                let remaining = bucket["remaining"] as? [String: Any] ?? [:]
                guard let fraction = number(remaining["remainingFraction"]), (0...1).contains(fraction) else { continue }
                let title = bucket["displayName"] as? String ?? groupName
                quotas.append(Quota(id: "\(groupIndex)-\(index)", title: title == groupName ? title : "\(groupName) · \(title)", remaining: fraction * 100,
                                    resetsAt: date(bucket["resetTime"] ?? remaining["resetTime"]), resetDescription: bucket["description"] as? String))
            }
        }
        let status = root["userStatus"] as? [String: Any] ?? response["userStatus"] as? [String: Any] ?? response
        if quotas.isEmpty, let configs = status["cascadeModelConfigData"] as? [String: Any] {
            for (index, model) in ((configs["clientModelConfigs"] as? [[String: Any]]) ?? []).enumerated() {
                guard let info = model["quotaInfo"] as? [String: Any], let fraction = number(info["remainingFraction"]), (0...1).contains(fraction) else { continue }
                let title = model["label"] as? String ?? model["displayName"] as? String ?? "모델 \(index + 1)"
                quotas.append(Quota(id: "model-\(index)", title: title, remaining: fraction * 100, resetsAt: date(info["resetTime"])))
            }
        }
        return Snapshot(provider: .antigravity, quotas: quotas, source: "계정 한도 · 로컬 Antigravity", updatedAt: now,
                        issue: quotas.isEmpty ? "Antigravity가 측정 가능한 한도를 반환하지 않았어요." : nil, account: status["email"] as? String)
    }
}
