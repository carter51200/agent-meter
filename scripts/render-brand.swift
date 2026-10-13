import AppKit
import Foundation
let source = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
let expression = try NSRegularExpression(pattern: #"<path[^>]* d="([^"]+)""#)
let number = try NSRegularExpression(pattern: #"[A-Za-z]|[-+]?(?:\d*\.\d+|\d+)(?:[eE][-+]?\d+)?"#)
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 128, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let transform = NSAffineTransform(); transform.translateX(by: 0, yBy: 128); transform.scaleX(by: 1.28, yBy: -1.28); transform.concat()
NSColor.black.setFill()
for match in expression.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
    let d = String(source[Range(match.range(at: 1), in: source)!])
    let tokens = number.matches(in: d, range: NSRange(d.startIndex..., in: d)).map { String(d[Range($0.range, in: d)!]) }
    var index = 0; var command = ""; var point = NSPoint.zero
    let path = NSBezierPath(); path.windingRule = .evenOdd
    func scalar() -> CGFloat { defer { index += 1 }; return CGFloat(Double(tokens[index])!) }
    func nextPoint() -> NSPoint { NSPoint(x: scalar(), y: scalar()) }
    while index < tokens.count {
        if tokens[index].first!.isLetter { command = tokens[index]; index += 1 }
        switch command {
        case "M": point = nextPoint(); path.move(to: point); command = "L"
        case "L": point = nextPoint(); path.line(to: point)
        case "H": point.x = scalar(); path.line(to: point)
        case "V": point.y = scalar(); path.line(to: point)
        case "C": let first = nextPoint(); let second = nextPoint(); point = nextPoint(); path.curve(to: point, controlPoint1: first, controlPoint2: second)
        case "Z", "z": path.close(); command = ""
        default: fatalError("Unsupported SVG path command: \(command)")
        }
    }
    path.fill()
}
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
