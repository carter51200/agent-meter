import AppKit
import Foundation

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = destination.appendingPathComponent("AgentMeter.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = points * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let transform = AffineTransform(scale: CGFloat(size) / 1024)
        (transform as NSAffineTransform).concat()
        let base = NSBezierPath(roundedRect: NSRect(x: 70, y: 70, width: 884, height: 884), xRadius: 196, yRadius: 196)
        NSGradient(starting: NSColor(calibratedRed: 0.12, green: 0.65, blue: 1, alpha: 1), ending: NSColor(calibratedRed: 0.12, green: 0.28, blue: 0.88, alpha: 1))!.draw(in: base, angle: -90)
        NSColor.white.withAlphaComponent(0.95).setStroke()
        let dial = NSBezierPath()
        dial.appendArc(withCenter: NSPoint(x: 512, y: 480), radius: 265, startAngle: 225, endAngle: -45, clockwise: true)
        dial.lineWidth = 44; dial.lineCapStyle = .round; dial.stroke()
        for angle in [45.0, 90.0, 135.0, 180.0] {
            let radians = angle * .pi / 180
            let center = NSPoint(x: 512 + cos(radians) * 198, y: 480 + sin(radians) * 198)
            NSColor.white.withAlphaComponent(0.6).setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - 10, y: center.y - 10, width: 20, height: 20)).fill()
        }
        NSColor.white.setStroke()
        let needle = NSBezierPath(); needle.move(to: NSPoint(x: 512, y: 480)); needle.line(to: NSPoint(x: 653, y: 621))
        needle.lineWidth = 40; needle.lineCapStyle = .round; needle.stroke()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: 474, y: 442, width: 76, height: 76)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(points)x\(points)" + (scale == 2 ? "@2x" : "") + ".png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
