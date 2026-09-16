import UIKit

/// Port of Termux's ExtraKeysView: the two-row, user-configurable key bar
/// above the keyboard. Termux default layout (see ~/.termux/termux.properties
/// extra-keys in the original app) is used here.
///
/// The view is a dumb grid — the controller receives key labels and decides
/// what bytes to send to the session.

public protocol ExtraKeysDelegate: AnyObject {
    /// Called when a key is pressed. `key` is the label (e.g. "ESC", "CTRL",
    /// "/", "UP", ...). The controller maps it to escape sequences.
    func extraKeys(_ view: ExtraKeysView, didSend key: String)
}

public final class ExtraKeysView: UIView {

    public weak var delegate: ExtraKeysDelegate?

    /// Same format as Termux's extra-keys.json: an array of rows.
    public var keyLayout: [[String]] = [
        ["ESC", "/", "-", "HOME", "UP", "END", "PGUP"],
        ["TAB", "CTRL", "ALT", "LEFT", "DOWN", "RIGHT", "PGDN"],
    ]

    private var ctrlButton: UIButton?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0.05, alpha: 1)
        rebuild()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported — build the view in code")
    }

    /// Reflect the latched state of CTRL (set by the controller, which owns it).
    public func setCtrlActive(_ active: Bool) {
        ctrlButton?.backgroundColor = active
            ? .systemOrange
            : UIColor(white: 0.15, alpha: 1)
    }

    private func rebuild() {
        subviews.forEach { $0.removeFromSuperview() }
        ctrlButton = nil

        let stack = UIStackView()
        stack.axis = .vertical
        stack.distribution = .fillEqually
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
        ])

        for row in keyLayout {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.distribution = .fillEqually
            rowStack.spacing = 4
            for key in row {
                let button = UIButton(type: .system)
                button.setTitle(key, for: .normal)
                button.titleLabel?.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .medium)
                button.setTitleColor(.white, for: .normal)
                button.backgroundColor = UIColor(white: 0.15, alpha: 1)
                button.layer.cornerRadius = 4
                button.addTarget(self, action: #selector(pressed(_:)), for: .touchUpInside)
                rowStack.addArrangedSubview(button)
                if key == "CTRL" { ctrlButton = button }
            }
            stack.addArrangedSubview(rowStack)
        }
    }

    @objc private func pressed(_ sender: UIButton) {
        guard let key = sender.currentTitle else { return }
        delegate?.extraKeys(self, didSend: key)
    }
}
