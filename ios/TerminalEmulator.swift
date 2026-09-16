import Foundation

// termux-swift / iOS port
// Swift rewrite of the `terminal-emulator` Gradle module
// (originals: TerminalEmulator.java, TerminalBuffer.java, TerminalRow.java, TextStyle.java)
//
// This is a VT100 / xterm *subset*, not a 1:1 port of Termux's ~175 KB
// TerminalEmulator.java. It implements the sequences interactive shells use
// most: cursor movement, erase, scrolling, SGR colors, OSC window title.

// MARK: - Cell (port of TerminalRow.java / TextStyle.java)

public struct TerminalCell: Equatable {
    public var char: Character = " "
    public var fg: Int = -1   // -1 = default, else ANSI 16-color palette index
    public var bg: Int = -1
    public var bold = false

    public init() {}
}

public protocol TerminalEmulatorDelegate: AnyObject {
    /// Called after a batch of input has been processed; the view should redraw.
    func terminalDidUpdate(_ emulator: TerminalEmulator)
}

// MARK: - Emulator (port of TerminalEmulator.java)

public final class TerminalEmulator {

    public private(set) var columns: Int
    public private(set) var rows: Int
    public private(set) var cursorX = 0
    public private(set) var cursorY = 0
    public private(set) var title = "termux-swift"

    public weak var delegate: TerminalEmulatorDelegate?

    private var grid: [[TerminalCell]]
    private var fg = -1
    private var bg = -1
    private var bold = false
    private var savedX = 0
    private var savedY = 0

    private enum State { case ground, escape, csi, osc, charset }
    private var state: State = .ground
    private var csiPrivate = false
    private var paramText = ""
    private var oscText = ""

    public init(columns: Int = 80, rows: Int = 24) {
        precondition(columns > 0 && rows > 0)
        self.columns = columns
        self.rows = rows
        grid = Array(repeating: Array(repeating: TerminalCell(), count: columns), count: rows)
    }

    // MARK: Buffer access (for the renderer)

    public func cell(col: Int, row: Int) -> TerminalCell {
        grid[row][col]
    }

    // MARK: Feeding data

    public func feed(_ data: Data) {
        var printable: [UInt8] = []

        func flushPrintable() {
            guard !printable.isEmpty else { return }
            let text = String(decoding: printable, as: UTF8.self)
            printable.removeAll(keepingCapacity: true)
            for ch in text { putChar(ch) }
        }

        for byte in data {
            switch state {
            case .ground:
                switch byte {
                case 0x1B: flushPrintable(); state = .escape
                case 0x0D: flushPrintable(); cursorX = 0
                case 0x0A, 0x0B, 0x0C: flushPrintable(); lineFeed()
                case 0x08: flushPrintable(); if cursorX > 0 { cursorX -= 1 }
                case 0x09: flushPrintable(); cursorX = min(columns - 1, ((cursorX / 8) + 1) * 8)
                case 0x00, 0x07: break // NUL, BEL
                default:
                    if byte >= 0x20 && byte != 0x7F { printable.append(byte) }
                }

            case .escape:
                switch byte {
                case 0x5B: state = .csi; csiPrivate = false; paramText = ""      // ESC [
                case 0x5D: state = .osc; oscText = ""                              // ESC ]
                case 0x28, 0x29, 0x2B, 0x2D: state = .charset                      // ESC ( etc.
                case 0x37: savedX = cursorX; savedY = cursorY; state = .ground     // ESC 7
                case 0x38: cursorX = savedX; cursorY = savedY; state = .ground     // ESC 8
                case 0x44: lineFeed(); state = .ground                             // ESC D
                case 0x4D: reverseLineFeed(); state = .ground                     // ESC M
                case 0x63: reset(); state = .ground                                // ESC c
                default: state = .ground
                }

            case .charset:
                // G0/G1 charset selection — we always render UTF-8, so just consume.
                state = .ground

            case .csi:
                if byte >= 0x40 && byte <= 0x7E {
                    dispatchCSI(final: byte, params: parseParams(paramText))
                    state = .ground
                } else if byte == 0x3F {
                    csiPrivate = true
                } else if (0x30...0x39).contains(byte) || byte == 0x3B {
                    paramText.append(Character(UnicodeScalar(byte)))
                } else if byte == 0x20 || (0x3A...0x3E).contains(byte) {
                    // intermediate bytes — ignore
                } else {
                    state = .ground
                }

            case .osc:
                if byte == 0x07 {
                    endOSC()
                    state = .ground
                } else if byte == 0x1B {
                    endOSC()
                    state = .escape
                } else {
                    oscText.append(Character(UnicodeScalar(byte)))
                }
            }
        }

        flushPrintable()
        delegate?.terminalDidUpdate(self)
    }

    // MARK: CSI dispatch

    private func dispatchCSI(final f: UInt8, params p: [Int]) {
        let one = { p.isEmpty ? 1 : max(p[0], 1) }

        switch f {
        // CUU / CUD / CUF / CUB — cursor movement
        case 0x41: cursorY = max(0, cursorY - one())
        case 0x42: cursorY = min(rows - 1, cursorY + one())
        case 0x43: cursorX = min(columns - 1, cursorX + one())
        case 0x44: cursorX = max(0, cursorX - one())
        // CNL / CPL — next / previous line
        case 0x45: cursorY = min(rows - 1, cursorY + one()); cursorX = 0
        case 0x46: cursorY = max(0, cursorY - one()); cursorX = 0
        // CHA — cursor horizontal absolute
        case 0x47: cursorX = clampCol((p.isEmpty ? 1 : p[0]) - 1)
        // CUP / HVP — cursor position
        case 0x48, 0x66:
            cursorY = clampRow((p.count > 1 ? p[1] : 1) - 1)
            cursorX = clampCol((p.first ?? 1) - 1)
        // ED — erase in display
        case 0x4A: eraseDisplay(p.first ?? 0)
        // EL — erase in line
        case 0x4B: eraseLine(p.first ?? 0)
        // SU / SD — scroll
        case 0x53: scrollUp(one())
        case 0x54: scrollDown(one())
        // VPA — vertical position absolute
        case 0x64: cursorY = clampRow(one() - 1)
        // SGR — select graphic rendition
        case 0x6D: selectGraphicRendition(p.isEmpty ? [0] : p)
        // DECSET / DECRST (private modes like cursor visibility, alt screen) — accepted, ignored
        case 0x68, 0x6C:
            if !csiPrivate { selectCharsetMode(f == 0x68) }
        // DECSTBM scroll region — not implemented yet (TODO: full port)
        case 0x72: break
        default: break
        }
    }

    private func selectCharsetMode(_ enable: Bool) {
        // placeholder for future LNM / line-mode handling
        _ = enable
    }

    private func selectGraphicRendition(_ p: [Int]) {
        for n in p {
            switch n {
            case 0: fg = -1; bg = -1; bold = false
            case 1: bold = true
            case 22: bold = false
            case 30...37: fg = n - 30
            case 38, 48: break // 256-color / RGB — TODO
            case 39: fg = -1
            case 40...47: bg = n - 40
            case 49: bg = -1
            case 90...97: fg = n - 90 + 8
            case 100...107: bg = n - 100 + 8
            default: break
            }
        }
    }

    // MARK: OSC (window title)

    private func endOSC() {
        let parts = oscText.split(separator: ";", maxSplits: 1)
        if let code = parts.first, code == "0" || code == "2", parts.count > 1 {
            title = String(parts[1])
        }
    }

    // MARK: Character / line operations

    private func putChar(_ ch: Character) {
        grid[cursorY][cursorX] = TerminalCell(char: ch, fg: fg, bg: bg, bold: bold)
        cursorX += 1
        if cursorX >= columns { // autowrap
            cursorX = 0
            lineFeed()
        }
    }

    private func lineFeed() {
        if cursorY >= rows - 1 {
            scrollUp(1)
        } else {
            cursorY += 1
        }
    }

    private func reverseLineFeed() {
        if cursorY == 0 {
            scrollDown(1)
        } else {
            cursorY -= 1
        }
    }

    private func scrollUp(_ n: Int) {
        for _ in 0..<max(1, n) {
            grid.removeFirst()
            grid.append(Array(repeating: TerminalCell(), count: columns))
        }
    }

    private func scrollDown(_ n: Int) {
        for _ in 0..<max(1, n) {
            grid.removeLast()
            grid.insert(Array(repeating: TerminalCell(), count: columns), at: 0)
        }
    }

    private func eraseDisplay(_ mode: Int) {
        switch mode {
        case 0:
            eraseLine(0)
            for row in (cursorY + 1)..<rows {
                grid[row] = Array(repeating: TerminalCell(), count: columns)
            }
        case 1:
            eraseLine(1)
            for row in 0..<cursorY {
                grid[row] = Array(repeating: TerminalCell(), count: columns)
            }
        case 2, 3:
            for row in 0..<rows {
                grid[row] = Array(repeating: TerminalCell(), count: columns)
            }
        default: break
        }
    }

    private func eraseLine(_ mode: Int) {
        let blank = TerminalCell()
        switch mode {
        case 0:
            for c in cursorX..<columns { grid[cursorY][c] = blank }
        case 1:
            for c in 0...min(cursorX, columns - 1) { grid[cursorY][c] = blank }
        case 2:
            grid[cursorY] = Array(repeating: blank, count: columns)
        default: break
        }
    }

    public func reset() {
        grid = Array(repeating: Array(repeating: TerminalCell(), count: columns), count: rows)
        cursorX = 0
        cursorY = 0
        fg = -1
        bg = -1
        bold = false
    }

    // MARK: Resize

    public func resize(columns newCols: Int, rows newRows: Int) {
        guard newCols > 0, newRows > 0, newCols != columns || newRows != rows else { return }
        var newGrid = Array(repeating: Array(repeating: TerminalCell(), count: newCols), count: newRows)
        for r in 0..<min(rows, newRows) {
            for c in 0..<min(columns, newCols) {
                newGrid[r][c] = grid[r][c]
            }
        }
        grid = newGrid
        columns = newCols
        rows = newRows
        cursorX = min(cursorX, newCols - 1)
        cursorY = min(cursorY, newRows - 1)
        delegate?.terminalDidUpdate(self)
    }

    // MARK: Helpers

    private func parseParams(_ text: String) -> [Int] {
        text.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
    }

    private func clampCol(_ v: Int) -> Int { min(max(v, 0), columns - 1) }
    private func clampRow(_ v: Int) -> Int { min(max(v, 0), rows - 1) }
}
