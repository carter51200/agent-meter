import Foundation
import MenuBarCore

struct UsageTests {
    func parse(_ json: String) throws -> [String: Any] { try UsageParser.object(Data(json.utf8)) }
    func testCodexWeeklyPrimaryIsNotMislabeledAsFiveHour() throws {
        let root = try parse(#"{"rate_limit":{"primary_window":{"used_percent":25,"limit_window_seconds":604800,"reset_at":1792300946},"secondary_window":null}}"#)
        let snapshot = UsageParser.codex(root)
        expect(snapshot.quotas.count == 1)
        expect(snapshot.quotas[0].title == "주간")
        expect(snapshot.minimum == 75)
        expect(snapshot.quotas[0].resetsAt == Date(timeIntervalSince1970: 1792300946))
    }
    func testCodexIndependentWindowsAndAdditionalModel() throws {
        let root = try parse(#"{"rate_limit":{"primary_window":{"used_percent":100,"limit_window_seconds":18000,"reset_after_seconds":60},"secondary_window":{"used_percent":20,"limit_window_seconds":604800}},"additional_rate_limits":[{"limit_name":"Spark","rate_limit":{"primary_window":{"used_percent":5,"limit_window_seconds":18000}}}]}"#)
        let now = Date(timeIntervalSince1970: 1000)
        let snapshot = UsageParser.codex(root, now: now)
        expect(snapshot.quotas.map(\.remaining) == [0, 80, 95])
        expect(snapshot.quotas.map(\.title) == ["5시간", "주간", "Spark · 5시간"])
        expect(snapshot.quotas[0].resetsAt == now.addingTimeInterval(60))
        expect(snapshot.minimum == 0)
    }
    func testUnknownAndInvalidValuesNeverBecomeZeroOrFull() throws {
        for value in ["null", "true", "-1", "101", "\"unknown\""] {
            let root = try parse("{\"rate_limit\":{\"primary_window\":{\"used_percent\":\(value)}}}")
            expect(UsageParser.codex(root).minimum == nil)
            expect(UsageParser.codex(root).issue != nil)
        }
        expect(UsageParser.claude([:]).minimum == nil)
        expect(UsageParser.antigravity([:]).minimum == nil)
    }
    func testClaudeNullSessionKeepsMeasuredWeekly() throws {
        let root = try parse(#"{"five_hour":null,"seven_day":{"utilization":42.5,"resets_at":"2026-10-18T12:30:00.000Z"},"seven_day_opus":{"utilization":0,"resets_at":null}}"#)
        let snapshot = UsageParser.claude(root)
        expect(snapshot.quotas.map(\.remaining) == [57.5, 100])
        expect(snapshot.quotas[0].title == "주간")
        expect(snapshot.quotas[0].resetsAt != nil)
        expect(snapshot.quotas[1].resetsAt == nil)
    }
    func testAntigravityGroupedQuotas() throws {
        let root = try parse(#"{"response":{"groups":[{"displayName":"Gemini","buckets":[{"displayName":"Weekly","remaining":{"remainingFraction":0.35},"description":"Resets on Friday"},{"displayName":"Session","remaining":{"remainingFraction":0.8}}]}]}}"#)
        let snapshot = UsageParser.antigravity(root)
        expect(snapshot.quotas.map(\.remaining) == [35, 80])
        expect(snapshot.quotas[0].title == "Gemini · Weekly")
        expect(snapshot.quotas[0].resetDescription == "Resets on Friday")
        expect(snapshot.minimum == 35)
    }
    func testAntigravityLegacyMissingFractionIsUnknown() throws {
        let root = try parse(#"{"userStatus":{"cascadeModelConfigData":{"clientModelConfigs":[{"label":"Gemini Pro","quotaInfo":{"remainingFraction":0,"resetTime":"2026-10-13T00:00:00Z"}},{"label":"Claude","quotaInfo":{"resetTime":"2026-10-13T00:00:00Z"}},{"label":"Invalid","quotaInfo":{"remainingFraction":1.5}}]}}}"#)
        let snapshot = UsageParser.antigravity(root)
        expect(snapshot.quotas.count == 1)
        expect(snapshot.minimum == 0)
        expect(snapshot.quotas[0].resetsAt != nil)
    }
    func testAvailabilityIsNotMeasuredQuota() throws {
        let root = try parse(#"{"models":{"gemini-pro":{"available":true,"remainingFraction":1}}}"#)
        expect(UsageParser.antigravity(root).quotas.isEmpty)
    }
    func testDateParsesBothISOFormatsAndEpoch() {
        expect(UsageParser.date("2026-10-13T00:00:00.123Z") != nil)
        expect(UsageParser.date("2026-10-13T00:00:00Z") != nil)
        expect(UsageParser.date(1792300946) != nil)
        expect(UsageParser.date("unknown") == nil)
    }
    func testAntigravityTerminalGroupsWithANSI() {
        let raw = "\u{001B}[2JModels & Quota\r\nGEMINI MODELS\r\nWeekly Limit Remaining\r\n[████░] 96.19%\r\nRefreshes in 144h 50m\r\nFive Hour Limit Remaining\r\n[████░] 98.69%\r\nRefreshes in 1h 13m\r\nCLAUDE AND GPT MODELS\r\nWeekly Limit Remaining\r\n[█████] 100.00%\r\nQuota available\r\nFive Hour Limit Remaining\r\n[█████] 100.00%\r\nQuota available\r\n"
        let now = Date(timeIntervalSince1970: 1000)
        let snapshot = UsageParser.antigravityTerminal(raw, now: now)
        expect(snapshot.quotas.count == 4)
        expect(snapshot.minimum == 96.19)
        expect(snapshot.quotas[0].title == "Gemini · 주간")
        expect(snapshot.quotas[2].title == "Claude + GPT · 주간")
        expect(snapshot.quotas[0].resetsAt == now.addingTimeInterval(144 * 3600 + 50 * 60))
        expect(snapshot.quotas[2].resetDescription == "현재 사용 가능")
    }
    func testTerminalFallbackUsesOnlyQuotaScreens() {
        let raw = "Current session\n[bar] 13% used\nResets 3pm (Asia/Seoul)\nCurrent week (all models)\n[bar] 72% used\nCurrent week (Opus)\n[bar] 100% used"
        let snapshot = UsageParser.claudeTerminal(raw)
        expect(snapshot.quotas.map(\.remaining) == [87, 28, 0])
        expect(snapshot.quotas[0].resetDescription == "Resets 3pm (Asia/Seoul)")
        expect(UsageParser.antigravityTerminal("Welcome. Usage estimate 30%").minimum == nil)
        expect(UsageParser.claudeTerminal("Token usage 15%\nContext 20% remaining").minimum == nil)
    }
    func testTerminalRedrawUsesLatestDigitsAndNamedModel() {
        let raw = "\u{001B}[2J\u{001B}[1;1HCurrent\u{001B}[12Gsession\u{001B}[2;1H████\u{001B}[55G11%\u{001B}[59Gused\u{001B}[3;1HResets\u{001B}[11G3pm\u{001B}[4;1HCurrent week (Fable)\u{001B}[5;55H19% used\u{001B}[2;56H2"
        let result = UsageParser.claudeTerminal(raw)
        expect(result.quotas.map(\.remaining) == [88, 81])
        expect(result.quotas[1].title == "Fable · 주간")
    }
}

func expect(_ condition: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    guard condition() else { fatalError("Check failed", file: (file), line: line) }
}

@main struct ParserChecks {
    static func main() throws {
        let tests = UsageTests()
        try tests.testCodexWeeklyPrimaryIsNotMislabeledAsFiveHour()
        try tests.testCodexIndependentWindowsAndAdditionalModel()
        try tests.testUnknownAndInvalidValuesNeverBecomeZeroOrFull()
        try tests.testClaudeNullSessionKeepsMeasuredWeekly()
        try tests.testAntigravityGroupedQuotas()
        try tests.testAntigravityLegacyMissingFractionIsUnknown()
        try tests.testAvailabilityIsNotMeasuredQuota()
        tests.testDateParsesBothISOFormatsAndEpoch()
        tests.testAntigravityTerminalGroupsWithANSI()
        tests.testTerminalFallbackUsesOnlyQuotaScreens()
        tests.testTerminalRedrawUsesLatestDigitsAndNamedModel()
        print("PASS: 11 quota parser checks (period labels, unknown values, exhaustion, grouped quotas, reset dates, terminal redraws)")
    }
}
