import Foundation

// Small bounded terminal renderer: read the latest screen, not old digits from a TUI redraw.
public enum TerminalScreen {
    public static func render(_ raw: String, width: Int = 140, height: Int = 80) -> String {
        var rows = Array(repeating: Array(repeating: Character(" "), count: width), count: height)
        var row = 0, col = 0, saved = (0, 0)
        let chars = Array(raw); var index = 0
        func number(_ parts: [String], _ position: Int, _ fallback: Int) -> Int {
            guard parts.count > position, let value = Int(parts[position]), value != 0 else { return fallback }
            return value
        }
        while index < chars.count {
            let char = chars[index]; index += 1
            if char == "\u{001B}" {
                guard index < chars.count else { break }
                let kind = chars[index]; index += 1
                if kind == "[" {
                    var parameters = ""
                    while index < chars.count {
                        let next = chars[index]; index += 1
                        if let scalar = next.unicodeScalars.first, (0x40...0x7E).contains(scalar.value) {
                            let parts = parameters.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
                            let amount = number(parts, 0, 1)
                            switch next {
                            case "H", "f": row = min(height - 1, max(0, amount - 1)); col = min(width - 1, max(0, number(parts, 1, 1) - 1))
                            case "G": col = min(width - 1, max(0, amount - 1))
                            case "A": row = max(0, row - amount)
                            case "B": row = min(height - 1, row + amount)
                            case "C": col = min(width - 1, col + amount)
                            case "D": col = max(0, col - amount)
                            case "E": row = min(height - 1, row + amount); col = 0
                            case "F": row = max(0, row - amount); col = 0
                            case "J":
                                let mode = Int(parameters) ?? 0
                                if mode == 2 || mode == 3 { rows = Array(repeating: Array(repeating: " ", count: width), count: height) }
                                else if mode == 0 {
                                    for c in col..<width { rows[row][c] = " " }
                                    if row + 1 < height { for r in (row + 1)..<height { rows[r] = Array(repeating: " ", count: width) } }
                                }
                            case "K":
                                let mode = Int(parameters) ?? 0
                                let range = mode == 2 ? 0..<width : mode == 1 ? 0..<(col + 1) : col..<width
                                for c in range { rows[row][c] = " " }
                            case "s": saved = (row, col)
                            case "u": (row, col) = saved
                            default: break
                            }
                            break
                        } else { parameters.append(next) }
                    }
                } else if kind == "]" {
                    while index < chars.count {
                        let next = chars[index]; index += 1
                        if next == "\u{0007}" { break }
                        if next == "\u{001B}", index < chars.count, chars[index] == "\\" { index += 1; break }
                    }
                } else if kind == "7" { saved = (row, col) }
                else if kind == "8" { (row, col) = saved }
                else if kind == "(" || kind == ")" { index = min(index + 1, chars.count) }
                continue
            }
            if char == "\r" { col = 0; continue }
            if char == "\n" || char == "\r\n" {
                col = 0
                row += 1
                if row >= height { rows.removeFirst(); rows.append(Array(repeating: " ", count: width)); row = height - 1 }
                continue
            }
            if char == "\u{0008}" { col = max(0, col - 1); continue }
            if char == "\t" { col = min(width - 1, (col / 8 + 1) * 8); continue }
            if let scalar = char.unicodeScalars.first, scalar.value < 32 { continue }
            if col >= width { col = 0; row += 1 }
            if row >= height { rows.removeFirst(); rows.append(Array(repeating: " ", count: width)); row = height - 1 }
            rows[row][col] = char; col += 1
        }
        return rows.map { String($0).trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
    }
}
