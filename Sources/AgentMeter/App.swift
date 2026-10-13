import AppKit
import SwiftUI
import ServiceManagement
import MenuBarCore

// Select the property wrapper on SDKs that also export a State macro.
typealias ViewState<Value> = SwiftUI.State<Value>

enum BrandAssets {
    static func image(_ name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
}

struct ProviderLogo: View {
    let provider: Provider
    var body: some View {
        if let image = BrandAssets.image(provider == .claude ? "claude" : provider.rawValue + "-template") {
            Image(nsImage: image).renderingMode(.template).resizable().scaledToFit()
                .foregroundStyle(.primary).frame(width: 20, height: 20).accessibilityHidden(true)
        }
    }
}

struct VibrantBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover; view.blendingMode = .behindWindow; view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

@MainActor final class MeterModel: ObservableObject {
    @Published var snapshots = Provider.allCases.map { Snapshot(provider: $0) }
    @Published var loading: Set<Provider> = []
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var settingsMessage: String?
    var didChange: (() -> Void)?
    private var timer: Timer?
    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
    func refresh(_ provider: Provider? = nil, allowKeychainPrompt: Bool = false) {
        for item in provider.map({ [$0] }) ?? Provider.allCases where !loading.contains(item) {
            loading.insert(item)
            Task {
                let result = await Collectors.fetch(item, allowKeychainPrompt: allowKeychainPrompt && item == .claude)
                if let index = snapshots.firstIndex(where: { $0.provider == item }) { snapshots[index] = result }
                loading.remove(item); didChange?()
            }
        }
    }
    func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            settingsMessage = SMAppService.mainApp.status == .requiresApproval ? "시스템 설정 → 일반 → 로그인 항목에서 허용해 주세요." : nil
        } catch { settingsMessage = "자동 실행을 설정하지 못했어요. 앱을 Applications 폴더에 설치한 뒤 다시 시도해 주세요." }
    }
    func connectCLI(_ provider: Provider) {
        let panel = NSOpenPanel()
        panel.title = "\(provider.title) CLI 연결"
        panel.message = "이 도구에서 이미 로그인하고 신뢰한 작업 폴더를 선택해 주세요. 앱은 그 폴더에서 /usage만 조회합니다."
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let directory = panel.url {
            UserDefaults.standard.set(directory.path, forKey: provider.rawValue + "CLIWorkspace")
            refresh(provider)
        }
    }
}

struct MeterView: View {
    @ObservedObject var model: MeterModel
    var onShowMenu: (() -> Void)?
    @ViewState private var expanded = false
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("남은 사용 한도").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                if let onShowMenu {
                    Button(action: onShowMenu) { Image(systemName: "menubar.rectangle") }
                        .buttonStyle(.borderless).help("메뉴 막대에서 열기").accessibilityLabel("메뉴 막대에서 열기")
                }
            }.padding(.horizontal, 14).padding(.vertical, 10)
            ForEach(model.snapshots) { snapshot in
                ProviderSection(snapshot: snapshot, isLoading: model.loading.contains(snapshot.provider), showAll: expanded)
                Divider().padding(.horizontal, 12)
            }
            HStack(spacing: 12) {
                Text(model.loading.isEmpty ? "2분마다 자동 갱신" : "사용량 확인 중…").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button { expanded.toggle() } label: { Image(systemName: expanded ? "chevron.up" : "chevron.down") }.help("모델별 한도").accessibilityLabel("모델별 한도")
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }.help("새로고침").accessibilityLabel("새로고침")
                Menu {
                    Toggle("로그인할 때 자동 실행", isOn: Binding(get: { model.launchAtLogin }, set: { _ in model.toggleLogin() }))
                    Divider()
                    Button("Claude Code 연결…") { model.refresh(.claude, allowKeychainPrompt: true) }
                    Button("Claude CLI 작업 폴더…") { model.connectCLI(.claude) }
                    Button("Antigravity CLI 작업 폴더…") { model.connectCLI(.antigravity) }
                    Divider()
                    Button("종료") { NSApp.terminate(nil) }
                } label: { Image(systemName: "gearshape") }.menuStyle(.borderlessButton).fixedSize().help("설정").accessibilityLabel("설정")
            }.buttonStyle(.borderless).padding(.horizontal, 14).padding(.vertical, 10)
        }.frame(width: 320).background(VibrantBackground())
    }
}

struct ProviderSection: View {
    let snapshot: Snapshot
    let isLoading: Bool
    var showAll = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProviderLogo(provider: snapshot.provider)
                Text(snapshot.provider.title).font(.system(size: 13, weight: .semibold))
                Spacer()
                if let remaining = snapshot.minimum {
                    Text("\(Int(remaining.rounded()))%").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(remaining < 15 ? .orange : .primary)
                } else if isLoading { ProgressView().controlSize(.mini) }
                else { Text("—").foregroundStyle(.secondary) }
            }.help(snapshot.source + " · 조회된 한도 중 최소 잔여 비율")
            if let issue = snapshot.issue {
                Text(issue).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.leading, 28)
            } else if snapshot.quotas.isEmpty {
                Text(isLoading ? "사용량 확인 중…" : "연결을 확인해 주세요.").font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 28)
            } else {
                VStack(spacing: 9) {
                    ForEach(showAll ? snapshot.quotas : Array(snapshot.quotas.prefix(2))) { quota in
                        QuotaView(quota: quota)
                    }
                }.padding(.leading, 28)
            }
        }.padding(.horizontal, 14).padding(.vertical, 10)
    }
}

struct LiveProviderSection: View {
    @ObservedObject var model: MeterModel
    let provider: Provider
    var body: some View {
        ProviderSection(snapshot: model.snapshots.first { $0.provider == provider } ?? Snapshot(provider: provider),
                        isLoading: model.loading.contains(provider)).frame(width: 300)
    }
}

struct QuotaView: View {
    let quota: Quota
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(quota.title).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(quota.remaining.rounded()))% 남음").monospacedDigit()
            }.font(.system(size: 11))
            ProgressView(value: quota.remaining, total: 100)
                .progressViewStyle(.linear).tint(quota.remaining < 15 ? .orange : .accentColor).controlSize(.small)
                .accessibilityLabel(quota.title + " 잔여 한도")
            if let reset = quota.resetsAt {
                TimelineView(.periodic(from: .now, by: 60)) { timeline in
                    Text(resetText(reset, now: timeline.date)).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .help(reset.formatted(date: .abbreviated, time: .shortened))
            } else if let description = quota.resetDescription, !description.isEmpty {
                Text(description).font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                Text("초기화 시간 정보 없음").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
    func resetText(_ date: Date, now: Date) -> String {
        let minutes = Int(ceil(date.timeIntervalSince(now) / 60))
        if minutes <= 0 { return "초기화 예정 · 새로고침으로 확인" }
        if minutes >= 1440 { return "\(minutes / 1440)일 \((minutes % 1440) / 60)시간 후 초기화" }
        if minutes >= 60 { return "\(minutes / 60)시간 \(minutes % 60)분 후 초기화" }
        return "\(minutes)분 후 초기화"
    }
}

@MainActor func showInstructions(_ message: String) {
    let alert = NSAlert(); alert.messageText = "Agent Meter 연결 안내"; alert.informativeText = message
    alert.addButton(withTitle: "확인"); NSApp.activate(ignoringOtherApps: true); alert.runModal()
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let model = MeterModel()
    var statusItem: NSStatusItem!
    var window: NSWindow?
    var trackingMenu: NSMenu?
    var providerViews: [Provider: NSHostingView<LiveProviderSection>] = [:]
    var menuFooter: NSMenuItem?
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "AgentMeter.OrderedGroup"
        if let button = statusItem.button {
            button.toolTip = "Codex → Claude Code → Antigravity · 계정 잔여 한도"
        }
        let menu = NSMenu(); menu.delegate = self; menu.autoenablesItems = false
        statusItem.menu = menu
        if CommandLine.arguments.contains("--light") { NSApp.appearance = NSAppearance(named: .aqua) }
        if CommandLine.arguments.contains("--dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
        model.didChange = { [weak self] in self?.updateTitle() }
        updateTitle(); model.start()
        if CommandLine.arguments.contains("--preview") {
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 430), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window?.title = "Agent Meter"
            window?.isReleasedWhenClosed = false
            window?.isOpaque = false; window?.backgroundColor = .clear; window?.titlebarAppearsTransparent = true
            window?.contentViewController = NSHostingController(rootView: MeterView(model: model, onShowMenu: { [weak self] in self?.showMenu(nil) }))
            window?.center(); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        }
        if CommandLine.arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.showMenu(nil) }
        }
    }
    func updateTitle() {
        // One template image guarantees left-to-right order and system appearance tinting.
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.black]
        let entries = Provider.allCases.map { provider -> (NSImage?, NSString, CGFloat) in
            let snapshot = model.snapshots.first { $0.provider == provider }
            let value = (snapshot?.minimum.map { "\(Int($0.rounded()))%" } ?? "—") as NSString
            let name = provider == .claude ? "claude" : provider.rawValue + "-template"
            return (BrandAssets.image(name), value, ceil(value.size(withAttributes: attributes).width))
        }
        let width = entries.reduce(CGFloat(0)) { $0 + 16 + 4 + $1.2 } + 22
        let image = NSImage(size: NSSize(width: width, height: 22), flipped: false) { rect in
            var x: CGFloat = 0
            for (index, entry) in entries.enumerated() {
                entry.0?.draw(in: NSRect(x: x, y: 3, width: 16, height: 16))
                entry.1.draw(at: NSPoint(x: x + 20, y: 4), withAttributes: attributes)
                x += 20 + entry.2 + (index == entries.count - 1 ? 0 : 11)
            }
            return true
        }
        image.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.title = ""
        statusItem.button?.setAccessibilityLabel("Agent Meter: " + Provider.allCases.map { p in
            p.title + " " + (model.snapshots.first { $0.provider == p }?.minimum.map { "\(Int($0.rounded()))%" } ?? "정보 없음")
        }.joined(separator: ", "))
        if let hosting = window?.contentViewController {
            let size = hosting.view.fittingSize
            if size.height > 0 { window?.setContentSize(NSSize(width: 320, height: min(740, size.height))) }
        }
        if let menu = trackingMenu {
            for view in providerViews.values { view.setFrameSize(view.fittingSize) }
            menuFooter?.title = footerTitle
            menu.update()
        }
    }
    var footerTitle: String {
        let time = model.snapshots.compactMap(\.updatedAt).min()?.formatted(date: .omitted, time: .shortened)
        return model.loading.isEmpty ? (time.map { $0 + " 확인 · 2분마다 갱신" } ?? "2분마다 자동 갱신") : "사용량 확인 중…"
    }
    @objc func showMenu(_ sender: NSStatusBarButton?) { statusItem.button?.performClick(nil) }
    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems(); menu.minimumWidth = 300
        trackingMenu = menu
        let heading = NSMenuItem(title: "남은 사용 한도", action: nil, keyEquivalent: "")
        heading.isEnabled = false; menu.addItem(heading)
        for provider in Provider.allCases {
            guard let snapshot = model.snapshots.first(where: { $0.provider == provider }) else { continue }
            let item = NSMenuItem()
            let view = NSHostingView(rootView: LiveProviderSection(model: model, provider: provider))
            providerViews[provider] = view
            view.setFrameSize(view.fittingSize); item.view = view; menu.addItem(item)
            if snapshot.quotas.count > 2 {
                let detail = NSMenuItem(title: "\(provider.title) 모델별 한도", action: nil, keyEquivalent: "")
                let submenu = NSMenu(); submenu.autoenablesItems = false
                for quota in snapshot.quotas {
                    let item = NSMenuItem()
                    let view = NSHostingView(rootView: QuotaView(quota: quota).padding(12).frame(width: 280))
                    view.setFrameSize(view.fittingSize); item.view = view; submenu.addItem(item)
                }
                detail.submenu = submenu; menu.addItem(detail)
            }
            menu.addItem(.separator())
        }
        let updated = NSMenuItem(title: footerTitle, action: nil, keyEquivalent: "")
        menuFooter = updated
        updated.isEnabled = false; menu.addItem(updated)
        addAction("새로고침", #selector(refresh), to: menu, key: "r")
        let settings = NSMenuItem(title: "설정", action: nil, keyEquivalent: "")
        let submenu = NSMenu(); submenu.autoenablesItems = false
        let login = addAction("로그인할 때 자동 실행", #selector(toggleLogin), to: submenu)
        login.state = model.launchAtLogin ? .on : .off
        submenu.addItem(.separator())
        addAction("Codex 로그인 안내…", #selector(connectCodex), to: submenu)
        addAction("Claude Code 연결…", #selector(connectClaude), to: submenu)
        addAction("Claude CLI 작업 폴더…", #selector(connectClaudeCLI), to: submenu)
        addAction("Antigravity CLI 작업 폴더…", #selector(connectAntigravityCLI), to: submenu)
        settings.submenu = submenu; menu.addItem(settings)
        menu.addItem(.separator())
        addAction("Agent Meter 종료", #selector(quit), to: menu, key: "q")
    }
    func menuDidClose(_ menu: NSMenu) {
        trackingMenu = nil; providerViews.removeAll(); menuFooter = nil
    }
    @discardableResult func addAction(_ title: String, _ action: Selector, to menu: NSMenu, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self; menu.addItem(item); return item
    }
    @objc func refresh() { model.refresh() }
    @objc func toggleLogin() { model.toggleLogin(); if let message = model.settingsMessage { showInstructions(message) } }
    @objc func connectClaude() { model.refresh(.claude, allowKeychainPrompt: true) }
    @objc func connectCodex() { showInstructions("터미널에서 codex login을 실행하고 ChatGPT 계정으로 로그인한 뒤 새로고침해 주세요.") }
    @objc func connectClaudeCLI() { model.connectCLI(.claude) }
    @objc func connectAntigravityCLI() { model.connectCLI(.antigravity) }
    @objc func quit() { NSApp.terminate(nil) }
}

@main struct AgentMeterMain {
    @MainActor static func main() {
        if let index = CommandLine.arguments.firstIndex(of: "--workspace"), CommandLine.arguments.count > index + 1 {
            let path = CommandLine.arguments[index + 1]
            var isDirectory: ObjCBool = false
            if path.hasPrefix("/"), FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                for provider in [Provider.claude, .antigravity] { UserDefaults.standard.set(path, forKey: provider.rawValue + "CLIWorkspace") }
            }
        }
        if CommandLine.arguments.contains("--check") {
            let allow = CommandLine.arguments.contains("--connect-claude")
            let forceCLI = CommandLine.arguments.contains("--force-cli")
            let finished = DispatchSemaphore(value: 0)
            Task.detached {
            let results = await withTaskGroup(of: Snapshot.self, returning: [Snapshot].self) { group in
                for provider in Provider.allCases { group.addTask { await Collectors.fetch(provider, allowKeychainPrompt: allow, forceCLI: forceCLI) } }
                var results: [Snapshot] = []
                for await result in group { results.append(result) }
                return Provider.allCases.compactMap { p in results.first { $0.provider == p } }
            }
            // Diagnostics include only quota values and human-readable status; omit account identity.
            let sanitized = results.map { item -> Snapshot in var copy = item; copy.account = nil; return copy }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(sanitized) { print(String(decoding: data, as: UTF8.self)) }
            finished.signal()
            }
            finished.wait()
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.setActivationPolicy(.accessory); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
