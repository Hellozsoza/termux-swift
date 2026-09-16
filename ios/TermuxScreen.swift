import UIKit

/// Recreation of Termux's GUI (TermuxActivity.java in the original app):
///
///   • top bar with session drawer toggle and title (Termux shows the active
///     session name; here we also show the active proot distro)
///   • multi-session terminals with the Termux session list in a left drawer
///     ("1: alpine", "2: alpine", ...), NEW SESSION button, swipe-to-close
///   • Termux's two-row extra-keys bar above the keyboard
///   • boots straight into the proot environment (TermuxShellSession)
///
/// When `proot-distro` swaps the distro, `rebootEnvironment()` tears down
/// every session and boots a fresh environment from the new config — the
/// app-level equivalent of Termux restarting after a distro switch.

public final class TermuxScreenController: UIViewController {

    private final class TermSession {
        let terminal = TerminalView(frame: .zero)
        let shell = TermuxShellSession()
    }

    private var sessions: [TermSession] = []
    private var activeIndex = 0
    private var ctrlActive = false

    private let manager = DistroManager.shared

    private let topBar = UIView()
    private let drawerButton = UIButton(type: .system)
    private let newSessionButton = UIButton(type: .system)
    private let titleLabel = UILabel()

    private let terminalContainer = UIView()
    private let extraKeys = ExtraKeysView(frame: .zero)
    private var extraKeysBottom: NSLayoutConstraint!

    private let scrim = UIControl()
    private let drawer = UIView()
    private let sessionTable = UITableView(frame: .zero, style: .plain)
    private let distroLabel = UILabel()
    private var drawerLeading: NSLayoutConstraint!
    private var drawerOpen = false

    public override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildTopBar()
        buildExtraKeys()
        buildTerminalArea()
        buildDrawer()
        observeKeyboard()
        newSession()
    }

    // MARK: Layout

    private func buildTopBar() {
        topBar.backgroundColor = UIColor(white: 0.08, alpha: 1)
        topBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBar)
        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 44),
        ])

        drawerButton.setImage(UIImage(systemName: "line.3.horizontal"), for: .normal)
        drawerButton.tintColor = .white
        drawerButton.addTarget(self, action: #selector(toggleDrawer), for: .touchUpInside)
        topBar.addSubview(drawerButton)
        drawerButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            drawerButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 12),
            drawerButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
        ])

        titleLabel.text = "termux-swift"
        titleLabel.textColor = .white
        titleLabel.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        topBar.addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
        ])

        newSessionButton.setImage(UIImage(systemName: "plus"), for: .normal)
        newSessionButton.tintColor = .white
        newSessionButton.addTarget(self, action: #selector(newSessionTapped), for: .touchUpInside)
        topBar.addSubview(newSessionButton)
        newSessionButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            newSessionButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -12),
            newSessionButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
        ])
    }

    private func buildExtraKeys() {
        extraKeys.delegate = self
        extraKeys.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(extraKeys)
        extraKeysBottom = extraKeys.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        NSLayoutConstraint.activate([
            extraKeys.heightAnchor.constraint(equalToConstant: 96),
            extraKeys.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            extraKeys.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            extraKeysBottom,
        ])
    }

    private func buildTerminalArea() {
        terminalContainer.backgroundColor = .black
        terminalContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(terminalContainer)
        NSLayoutConstraint.activate([
            terminalContainer.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            terminalContainer.bottomAnchor.constraint(equalTo: extraKeys.topAnchor),
            terminalContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            terminalContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func buildDrawer() {
        scrim.backgroundColor = UIColor(white: 0, alpha: 0.55)
        scrim.alpha = 0
        scrim.isHidden = true
        scrim.addTarget(self, action: #selector(toggleDrawer), for: .touchUpInside)
        scrim.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrim)
        NSLayoutConstraint.activate([
            scrim.topAnchor.constraint(equalTo: view.topAnchor),
            scrim.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrim.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        drawer.backgroundColor = UIColor(white: 0.10, alpha: 1)
        drawer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(drawer)
        drawerLeading = drawer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: -280)
        NSLayoutConstraint.activate([
            drawerLeading,
            drawer.topAnchor.constraint(equalTo: view.topAnchor),
            drawer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            drawer.widthAnchor.constraint(equalToConstant: 280),
        ])

        let header = UILabel()
        header.text = "SESSIONS"
        header.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
        header.textColor = UIColor(white: 0.6, alpha: 1)
        header.translatesAutoresizingMaskIntoConstraints = false
        drawer.addSubview(header)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: drawer.safeAreaLayoutGuide.topAnchor, constant: 16),
            header.leadingAnchor.constraint(equalTo: drawer.leadingAnchor, constant: 16),
        ])

        distroLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        distroLabel.textColor = UIColor(white: 0.55, alpha: 1)
        distroLabel.translatesAutoresizingMaskIntoConstraints = false
        drawer.addSubview(distroLabel)
        NSLayoutConstraint.activate([
            distroLabel.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            distroLabel.leadingAnchor.constraint(equalTo: drawer.leadingAnchor, constant: 16),
            distroLabel.trailingAnchor.constraint(equalTo: drawer.trailingAnchor, constant: -16),
        ])

        sessionTable.dataSource = self
        sessionTable.delegate = self
        sessionTable.backgroundColor = .clear
        sessionTable.rowHeight = 44
        sessionTable.separatorColor = UIColor(white: 0.2, alpha: 1)
        sessionTable.translatesAutoresizingMaskIntoConstraints = false
        drawer.addSubview(sessionTable)
        NSLayoutConstraint.activate([
            sessionTable.topAnchor.constraint(equalTo: distroLabel.bottomAnchor, constant: 12),
            sessionTable.leadingAnchor.constraint(equalTo: drawer.leadingAnchor),
            sessionTable.trailingAnchor.constraint(equalTo: drawer.trailingAnchor),
        ])

        let newButton = UIButton(type: .system)
        newButton.setTitle("NEW SESSION", for: .normal)
        newButton.titleLabel?.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        newButton.setTitleColor(.systemGreen, for: .normal)
        newButton.addTarget(self, action: #selector(newSessionTapped), for: .touchUpInside)
        newButton.translatesAutoresizingMaskIntoConstraints = false
        drawer.addSubview(newButton)
        NSLayoutConstraint.activate([
            newButton.topAnchor.constraint(equalTo: sessionTable.bottomAnchor, constant: 12),
            newButton.leadingAnchor.constraint(equalTo: drawer.leadingAnchor, constant: 16),
        ])
    }

    // MARK: Sessions

    private func newSession() {
        let s = TermSession()
        s.terminal.session = s.shell
        s.shell.delegate = self
        s.shell.onDistroChanged = { [weak self] in self?.rebootEnvironment() }
        s.shell.onCtrlConsumed = { [weak self] in
            self?.ctrlActive = false
            self?.extraKeys.setCtrlActive(false)
        }
        sessions.append(s)
        switchTo(sessions.count - 1)
        s.shell.start()
    }

    @objc private func newSessionTapped() {
        newSession()
    }

    private func switchTo(_ index: Int) {
        guard sessions.indices.contains(index) else { return }
        activeIndex = index
        terminalContainer.subviews.forEach { $0.removeFromSuperview() }
        let terminal = sessions[index].terminal
        terminal.translatesAutoresizingMaskIntoConstraints = false
        terminalContainer.addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.topAnchor.constraint(equalTo: terminalContainer.topAnchor),
            terminal.bottomAnchor.constraint(equalTo: terminalContainer.bottomAnchor),
            terminal.leadingAnchor.constraint(equalTo: terminalContainer.leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: terminalContainer.trailingAnchor),
        ])
        terminal.becomeFirstResponder()
        updateChrome()
        setDrawer(open: false)
    }

    private func closeSession(_ index: Int) {
        guard sessions.indices.contains(index) else { return }
        sessions.remove(at: index)
        if sessions.isEmpty {
            newSession() // Termux always keeps at least one session alive
            return
        }
        switchTo(min(activeIndex, sessions.count - 1))
    }

    /// proot-distro swap → "reboot": every session is torn down and a fresh
    /// environment boots from the new config. Same observable behavior as
    /// Termux restarting after a distro switch, without killing the app.
    private func rebootEnvironment() {
        sessions.forEach { $0.terminal.resignFirstResponder() }
        sessions.forEach { $0.terminal.removeFromSuperview() }
        sessions.removeAll()
        activeIndex = 0
        newSession()
        updateChrome()
    }

    private func updateChrome() {
        titleLabel.text = "termux-swift [\(manager.config.activeDistro)]"
        distroLabel.text = "proot: \(manager.config.activeDistro) • \(sessions.count) session\(sessions.count == 1 ? "" : "s")"
        sessionTable.reloadData()
    }

    // MARK: Drawer

    @objc private func toggleDrawer() {
        setDrawer(open: !drawerOpen)
    }

    private func setDrawer(open: Bool) {
        drawerOpen = open
        drawerLeading.constant = open ? 0 : -280
        scrim.isHidden = false
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut]) {
            self.view.layoutIfNeeded()
            self.scrim.alpha = open ? 1 : 0
        } completion: { _ in
            self.scrim.isHidden = !open
        }
    }

    // MARK: Keyboard

    private func observeKeyboard() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardChanged(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }

    @objc private func keyboardChanged(_ notification: Notification) {
        guard let info = notification.userInfo,
              let frame = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let overlap = max(0, view.bounds.maxY - frame.minY)
        extraKeysBottom.constant = -overlap
        UIView.animate(withDuration: 0.25) {
            self.view.layoutIfNeeded()
        }
    }
}

// MARK: - TerminalSessionDelegate

extension TermuxScreenController: TerminalSessionDelegate {
    public func session(_ session: TerminalSession, didOutput data: Data) {
        guard let s = sessions.first(where: { $0.shell === session }) else { return }
        s.terminal.feed(data)
    }

    public func sessionDidExit(_ session: TerminalSession) {
        guard let s = sessions.first(where: { $0.shell === session }) else { return }
        s.terminal.feed(Data("\r\n[session exited — swipe CLOSE in the drawer]\r\n".utf8))
    }
}

// MARK: - ExtraKeysDelegate

extension TermuxScreenController: ExtraKeysDelegate {
    public func extraKeys(_ view: ExtraKeysView, didSend key: String) {
        guard sessions.indices.contains(activeIndex) else { return }
        let shell = sessions[activeIndex].shell
        switch key {
        case "CTRL":
            ctrlActive.toggle()
            shell.ctrlActive = ctrlActive
            view.setCtrlActive(ctrlActive)
        case "ALT":
            break // meta-prefix reserved for the real engine
        case "ESC": shell.write(Data("\u{1B}".utf8))
        case "TAB": shell.write(Data("\t".utf8))
        case "UP": shell.write(Data("\u{1B}[A".utf8))
        case "DOWN": shell.write(Data("\u{1B}[B".utf8))
        case "RIGHT": shell.write(Data("\u{1B}[C".utf8))
        case "LEFT": shell.write(Data("\u{1B}[D".utf8))
        case "HOME": shell.write(Data("\u{1B}[H".utf8))
        case "END": shell.write(Data("\u{1B}[F".utf8))
        case "PGUP": shell.write(Data("\u{1B}[5~".utf8))
        case "PGDN": shell.write(Data("\u{1B}[6~".utf8))
        default: shell.write(Data(key.utf8))
        }
    }
}

// MARK: - Session list

extension TermuxScreenController: UITableViewDataSource, UITableViewDelegate {
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sessions.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "session")
            ?? UITableViewCell(style: .default, reuseIdentifier: "session")
        let running = indexPath.row == activeIndex
        cell.textLabel?.text = "\(indexPath.row + 1): \(manager.config.activeDistro)\(running ? "  ▶" : "")"
        cell.textLabel?.textColor = running ? .systemGreen : .white
        cell.textLabel?.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        cell.backgroundColor = UIColor(white: 0.12, alpha: 1)
        cell.selectionStyle = .none
        return cell
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switchTo(indexPath.row)
    }

    public func tableView(_ tableView: UITableView,
                          trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
                          -> UISwipeActionsConfiguration {
        let close = UIContextualAction(style: .destructive, title: "CLOSE") { [weak self] _, _, done in
            self?.closeSession(indexPath.row)
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [close])
    }
}
