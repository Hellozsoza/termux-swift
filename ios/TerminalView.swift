import UIKit

// termux-swift / iOS port
// Swift rewrite of the `terminal-view` Gradle module
// (originals: TerminalView.java, TerminalRenderer.java).
//
// Renders the emulator buffer with CoreText-style string drawing and feeds
// keyboard input back to the session. Replaces Android's custom View with a
// UIView implementing UIKeyInput (software keyboard) and presses (hardware
// keys), plus an accessory bar for the keys phones don't have.

// MARK: - Theme (port of TerminalColorScheme.java / TerminalColors.java)

public struct TerminalTheme {
    public var background = UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1)
    public var foreground = UIColor(white: 0.92, alpha: 1)
    public var cursor = UIColor(white: 1.0, alpha: 0.55)

    public var palette: [UIColor] = [
        UIColor(red: 0.00, green: 0.00, blue: 0.00, alpha: 1), // 0 black
        UIColor(red: 0.80, green: 0.00, blue: 0.00, alpha: 1), // 1 red
        UIColor(red: 0.00, green: 0.80, blue: 0.00, alpha: 1), // 2 green
        UIColor(red: 0.80, green: 0.80, blue: 0.00, alpha: 1), // 3 yellow
        UIColor(red: 0.00, green: 0.25, blue: 0.93, alpha: 1), // 4 blue
        UIColor(red: 0.80, green: 0.00, blue: 0.80, alpha: 1), // 5 magenta
        UIColor(red: 0.00, green: 0.80, blue: 0.80, alpha: 1), // 6 cyan
        UIColor(red: 0.90, green: 0.90, blue: 0.90, alpha: 1), // 7 white
        UIColor(red: 0.50, green: 0.50, blue: 0.50, alpha: 1), // 8 bright black
        UIColor(red: 1.00, green: 0.00, blue: 0.00, alpha: 1), // 9 bright red
        UIColor(red: 0.00, green: 1.00, blue: 0.00, alpha: 1), // 10 bright green
        UIColor(red: 1.00, green: 1.00, blue: 0.00, alpha: 1), // 11 bright yellow
        UIColor(red: 0.36, green: 0.36, blue: 1.00, alpha: 1), // 12 bright blue
        UIColor(red: 1.00, green: 0.00, blue: 1.00, alpha: 1), // 13 bright magenta
        UIColor(red: 0.00, green: 1.00, blue: 1.00, alpha: 1), // 14 bright cyan
        UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1), // 15 bright white
    ]

    public init() {}
}

// MARK: - Terminal view

public final class TerminalView: UIView, TerminalEmulatorDelegate, UIKeyInput {

    public let emulator = TerminalEmulator()
    public weak var session: TerminalSession?
    public var theme = TerminalTheme() {
        didSet { backgroundColor = theme.background; setNeedsDisplay() }
    }

    private let font: UIFont
    private let boldFont: UIFont
    private var charWidth: CGFloat = 0
    private var charHeight: CGFloat = 0
    private var ctrlActive = false

    public override var canBecomeFirstResponder: Bool { true }
    public var hasText: Bool { true }

    public override init(frame: CGRect) {
        font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        boldFont = UIFont.monospacedSystemFont(ofSize: 14, weight: .bold)
        super.init(frame: frame)

        isOpaque = true
        backgroundColor = theme.background
        emulator.delegate = self

        charWidth = ("MMMMM" as NSString).size(with: font).width / 5
        charHeight = font.lineHeight

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported — build the view in code")
    }

    // MARK: Public API

    /// Feed output bytes from the session into the emulator.
    public func feed(_ data: Data) {
        emulator.feed(data)
    }

    // MARK: Layout & drawing

    public override func layoutSubviews() {
        super.layoutSubviews()
        guard charWidth > 0, charHeight > 0, bounds.width > 10, bounds.height > 10 else { return }
        let cols = max(20, Int(bounds.width / charWidth))
        let rows = max(10, Int(bounds.height / charHeight))
        if cols != emulator.columns || rows != emulator.rows {
            emulator.resize(columns: cols, rows: rows)
        }
    }

    public override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        theme.background.setFill()
        ctx.fill(bounds)

        for row in 0..<emulator.rows {
            let y = CGFloat(row) * charHeight
            var col = 0
            while col < emulator.columns {
                let start = emulator.cell(col: col, row: row)
                var run = String()
                var c = col
                while c < emulator.columns {
                    let cell = emulator.cell(col: c, row: row)
                    if cell.fg != start.fg || cell.bg != start.bg || cell.bold != start.bold { break }
                    run.append(cell.char)
                    c += 1
                }
                NSAttributedString(string: run, attributes: attributes(for: start))
                    .draw(at: CGPoint(x: CGFloat(col) * charWidth, y: y))
                col = c
            }
        }

        if isFirstResponder {
            let caret = CGRect(x: CGFloat(emulator.cursorX) * charWidth,
                               y: CGFloat(emulator.cursorY) * charHeight,
                               width: charWidth,
                               height: charHeight)
            theme.cursor.setFill()
            ctx.fill(caret)
        }
    }

    private func attributes(for cell: TerminalCell) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: cell.bold ? boldFont : font,
            .foregroundColor: color(for: cell.fg, default: theme.foreground),
        ]
        if cell.bg >= 0 {
            attrs[.backgroundColor] = color(for: cell.bg, default: theme.background)
        }
        return attrs
    }

    private func color(for index: Int, default def: UIColor) -> UIColor {
        guard index >= 0, index < theme.palette.count else { return def }
        return theme.palette[index]
    }

    // MARK: Keyboard input (UIKeyInput)

    public func insertText(_ text: String) {
        if text == "\n" {
            send("\r")
            return
        }
        if ctrlActive {
            ctrlActive = false
            refreshCtrlButton()
            for scalar in text.unicodeScalars {
                if let c = controlCode(for: scalar) {
                    send(Data([c]))
                }
            }
            return
        }
        send(text)
    }

    public func deleteBackward() {
        send(Data([0x7F]))
    }

    // Hardware keyboard: arrows / escape arrive as key presses, not insertText.
    public override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            guard let key = press.key else { continue }
            let seq: String?
            switch key.keyCode {
            case .keyboardUpArrow: seq = "\u{1B}[A"
            case .keyboardDownArrow: seq = "\u{1B}[B"
            case .keyboardRightArrow: seq = "\u{1B}[C"
            case .keyboardLeftArrow: seq = "\u{1B}[D"
            case .keyboardEscape: seq = "\u{1B}"
            default: seq = nil
            }
            if let s = seq {
                send(s)
                handled = true
            }
        }
        if !handled {
            super.pressesBegan(presses, with: event)
        }
    }

    // MARK: Accessory key bar

    private lazy var ctrlButton = UIBarButtonItem(
        title: "CTRL", style: .plain, target: self, action: #selector(toggleCtrl))

    private func buildAccessory() -> UIToolbar {
        let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 0, height: 44))
        let mk: (String, Selector) -> UIBarButtonItem = { title, action in
            UIBarButtonItem(title: title, style: .plain, target: self, action: action)
        }
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        bar.items = [
            mk("ESC", #selector(sendEsc)),
            mk("TAB", #selector(sendTab)),
            ctrlButton,
            flex,
            mk("←", #selector(sendLeft)),
            mk("↑", #selector(sendUp)),
            mk("↓", #selector(sendDown)),
            mk("→", #selector(sendRight)),
            flex,
            mk("⌄", #selector(dismissKeyboard)),
        ]
        bar.sizeToFit()
        return bar
    }

    @objc private func handleTap() { becomeFirstResponder() }
    @objc private func sendEsc() { send("\u{1B}") }
    @objc private func sendTab() { send("\t") }
    @objc private func sendLeft() { send("\u{1B}[D") }
    @objc private func sendRight() { send("\u{1B}[C") }
    @objc private func sendUp() { send("\u{1B}[A") }
    @objc private func sendDown() { send("\u{1B}[B") }
    @objc private func dismissKeyboard() { resignFirstResponder() }

    @objc private func toggleCtrl() {
        ctrlActive.toggle()
        refreshCtrlButton()
    }

    private func refreshCtrlButton() {
        ctrlButton.tintColor = ctrlActive ? .systemOrange : nil
    }

    private func send(_ string: String) {
        send(Data(string.utf8))
    }

    private func send(_ data: Data) {
        session?.write(data)
    }

    private func controlCode(for scalar: Unicode.Scalar) -> UInt8? {
        let v = scalar.value
        if v == 64 { return 0 }              // @ -> NUL
        if (65...90).contains(v) { return UInt8(v - 64) }   // A-Z -> ^A..^Z
        if (97...122).contains(v) { return UInt8(v - 96) }  // a-z -> ^A..^Z
        if (91...95).contains(v) { return UInt8(v - 64) }    // [ \ ] ^ _
        return nil
    }

    // MARK: TerminalEmulatorDelegate

    public func terminalDidUpdate(_ emulator: TerminalEmulator) {
        setNeedsDisplay()
    }
}
