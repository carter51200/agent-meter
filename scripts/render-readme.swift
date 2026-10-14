import AppKit
import Foundation

// Documentation artwork only. Values are fixed examples, never account data.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = root.appendingPathComponent("docs/images")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let ink = NSColor(calibratedWhite: 0.11, alpha: 1)
let muted = NSColor(calibratedWhite: 0.43, alpha: 1)
let providers = ["Codex", "Claude Code", "Antigravity"]
let marks = ["codex-template.png", "claude.png", "antigravity-template.png"].map {
    NSImage(contentsOf: root.appendingPathComponent("Assets/" + $0))!
}

func text(_ value: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat,
          color: NSColor = ink, weight: NSFont.Weight = .regular, width: CGFloat = 900) {
    let style = NSMutableParagraphStyle(); style.lineSpacing = 3
    (value as NSString).draw(in: NSRect(x: x, y: y, width: width, height: 180), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style
    ])
}
func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat, _ color: NSColor) {
    color.setFill(); NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: radius, yRadius: radius).fill()
}
func line(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ color: NSColor) { box(x, y, w, 1, 0, color) }
func mark(_ index: Int, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ color: NSColor) {
    let tinted = NSImage(size: NSSize(width: size, height: size))
    tinted.lockFocusFlipped(true)
    marks[index].draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    color.setFill(); NSRect(x: 0, y: 0, width: size, height: size).fill(using: .sourceAtop)
    tinted.unlockFocus()
    tinted.draw(in: NSRect(x: x, y: y, width: size, height: size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
}
func symbol(_ name: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ color: NSColor) {
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
    let tinted = NSImage(size: NSSize(width: size, height: size)); tinted.lockFocusFlipped(true)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    color.setFill(); NSRect(x: 0, y: 0, width: size, height: size).fill(using: .sourceAtop); tinted.unlockFocus()
    tinted.draw(in: NSRect(x: x, y: y, width: size, height: size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
}
func menuBar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, dark: Bool = false) {
    let fg = dark ? NSColor.white : ink
    box(x, y, w, 36, 12, dark ? NSColor(calibratedWhite: 0.22, alpha: 1) : NSColor(calibratedWhite: 0.99, alpha: 1))
    symbol("apple.logo", x + 17, y + 9, 17, fg)
    for i in 0..<3 {
        let offset = x + w - 236 + CGFloat(i) * 76
        mark(i, offset, y + 9, 18, fg)
        text(["74%", "62%", "91%"][i], offset + 24, y + 9, 12, color: fg, weight: .medium, width: 44)
    }
}
func panel(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, dark: Bool = false) {
    let fg = dark ? NSColor(calibratedWhite: 0.96, alpha: 1) : ink
    let secondary = dark ? NSColor(calibratedWhite: 0.65, alpha: 1) : muted
    let bg = dark ? NSColor(calibratedWhite: 0.18, alpha: 1) : NSColor(calibratedWhite: 0.98, alpha: 1)
    let divider = dark ? NSColor(calibratedWhite: 0.29, alpha: 1) : NSColor(calibratedWhite: 0.87, alpha: 1)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.13)
    shadow.shadowBlurRadius = 24; shadow.shadowOffset = NSSize(width: 0, height: -8); shadow.set()
    box(x, y, w, 486, 12, bg)
    NSGraphicsContext.restoreGraphicsState()
    let periods = [[("주간", 74)], [("5시간", 86), ("주간", 62)], [("Gemini · 주간", 91), ("Gemini · 5시간", 98)]]
    var top = y + 20
    for i in 0..<3 {
        mark(i, x + 16, top + 2, 22, fg)
        text(providers[i], x + 47, top, 15, color: fg, weight: .semibold, width: w - 108)
        text(["74%", "62%", "91%"][i], x + w - 54, top, 15, color: fg, weight: .semibold, width: 50)
        top += 34
        for (period, value) in periods[i] {
            text(period, x + 47, top, 12, color: secondary, weight: .medium, width: w - 142)
            text("\(value)% 남음", x + w - 91, top, 12, color: secondary, width: 78)
            box(x + 47, top + 24, w - 63, 4, 2, divider)
            box(x + 47, top + 24, (w - 63) * CGFloat(value) / 100, 4, 2, dark ? .white : NSColor(calibratedWhite: 0.44, alpha: 1))
            text(period.contains("5시간") ? "2시간 후 초기화" : "3일 후 초기화", x + 47, top + 36, 11, color: secondary, width: w - 63)
            top += 55
        }
        if i < 2 { line(x + 12, top + 1, w - 24, divider); top += 14 }
    }
    line(x + 12, y + 450, w - 24, divider)
    text("2분마다 자동 갱신", x + 16, y + 464, 10, color: secondary, width: 180)
    symbol("chevron.down", x + w - 88, y + 463, 13, secondary)
    symbol("arrow.clockwise", x + w - 62, y + 461, 17, secondary)
    symbol("gearshape", x + w - 34, y + 461, 17, secondary)
}
func render(_ name: String, size: NSSize, draw: () -> Void) throws {
    let canvas = NSImage(size: size); canvas.lockFocusFlipped(true)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(); canvas.unlockFocus()
    let bitmap = NSBitmapImageRep(data: canvas.tiffRepresentation!)!
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
}

try render("hero.png", size: NSSize(width: 1280, height: 650)) {
    box(0, 0, 1280, 650, 0, NSColor(calibratedWhite: 0.965, alpha: 1))
    let icon = NSImage(contentsOf: output.appendingPathComponent("app-icon.png"))!
    icon.draw(in: NSRect(x: 62, y: 72, width: 84, height: 84), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    text("Agent Meter", 162, 91, 25, weight: .semibold, width: 440)
    text("Your AI limits.\nOne quiet menu.", 72, 194, 57, weight: .semibold, width: 660)
    text("Codex, Claude Code, and Antigravity.\nA native macOS companion for your remaining limits.", 76, 370, 20, color: muted, width: 640)
    line(76, 467, 543, NSColor(calibratedWhite: 0.86, alpha: 1))
    text("macOS 14+   /   Apple Silicon + Intel", 76, 492, 15, color: muted, weight: .medium, width: 580)
    menuBar(754, 62, 448)
    panel(830, 114, 372)
    text("Illustrative preview · Demo values · Korean app UI", 76, 607, 12, color: muted, width: 760)
}
try render("appearance.png", size: NSSize(width: 1280, height: 740)) {
    box(0, 0, 1280, 740, 0, NSColor(calibratedWhite: 0.965, alpha: 1))
    text("Made for the menu bar.", 68, 40, 34, weight: .semibold, width: 1080)
    text("Monochrome marks. System typography. Clear remaining limits.", 70, 92, 17, color: muted, width: 1100)
    text("LIGHT", 243, 148, 11, color: muted, weight: .semibold, width: 360)
    text("DARK", 680, 148, 11, color: muted, weight: .semibold, width: 360)
    menuBar(202, 173, 386); panel(216, 221, 372)
    menuBar(652, 173, 386, dark: true); panel(666, 221, 372, dark: true)
    text("Illustrative previews · Demo values · App interface is currently Korean", 70, 714, 12, color: muted, width: 1100)
}
print("Created docs/images/hero.png and docs/images/appearance.png")
