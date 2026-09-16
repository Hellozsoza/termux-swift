import Foundation

/// The environment you land in when the app boots — Termux's proot-distro
/// Alpine session, re-created for iOS.
///
/// RIGHT NOW this is an in-process simulation: busybox-style commands running
/// against the app sandbox, so the whole GUI + distro-swap flow is testable
/// today. WHEN THE ENGINE LANDS (emulated rv32/x86 kernel), this class is
/// replaced by a `LinuxEngineSession` implementing the same TerminalSession
/// protocol — the GUI, DistroManager, extra keys and swap/reboot flow all
/// stay identical.
///
/// Commands implemented the Termux way: everything you'd expect in the
/// default environment (help, ls, cd, cat, echo, ps, uname, apk, ...) plus
/// `proot-distro`, which performs the swap-and-reboot you specified.

public final class TermuxShellSession: TerminalSession {

    public weak var delegate: TerminalSessionDelegate?

    /// Fired when `proot-distro` swapped the active distro and the
    /// environment should "reboot" (controller tears down all sessions and
    /// boots a fresh one — the app-level equivalent of restarting Termux).
    public var onDistroChanged: (() -> Void)?

    /// Fired when a CTRL-combination was consumed so the GUI can unlatch CTRL.
    public var onCtrlConsumed: (() -> Void)?

    /// Latched by the extra-keys row; applies to the next letter typed.
    public var ctrlActive = false

    private var inputLine = ""
    private var cwd: URL
    private let manager = DistroManager.shared

    private enum InputState { case normal, escape, csi }
    private var inputState: InputState = .normal

    public init() {
        cwd = FileManager.default.homeDirectoryForCurrentUser
    }

    // MARK: TerminalSession

    public func start() {
        bootBanner()
        prompt()
    }

    public func write(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        for ch in text {
            // Swallow arrow/function-key escape sequences: they're not line input.
            switch inputState {
            case .escape:
                inputState = (ch == "[") ? .csi : .normal
                continue
            case .csi:
                if ch.isLetter { inputState = .normal }
                continue
            case .normal:
                break
            }

            if ctrlActive, ch.isLetter {
                ctrlActive = false
                onCtrlConsumed?()
                let letter = ch.lowercased().unicodeScalars.first!.value
                handleControl(UInt8(letter & 0x1F))
                continue
            }

            switch ch {
            case "\r":
                out("\r\n")
                let line = inputLine
                inputLine = ""
                execute(line)
            case "\u{7F}":
                if !inputLine.isEmpty {
                    inputLine.removeLast()
                    out("\u{8} \u{8}")
                }
            case "\u{1B}":
                inputState = .escape
            default:
                if !ch.isNewline {
                    inputLine.append(ch)
                    out(String(ch))
                }
            }
        }
    }

    public func terminate() {
        delegate?.sessionDidExit(self)
    }

    // MARK: Control characters (CTRL row)

    private func handleControl(_ code: UInt8) {
        switch code {
        case 3: // ^C
            inputLine = ""
            out("^C\r\n")
            prompt()
        case 4: // ^D
            out("^D")
            delegate?.sessionDidExit(self)
        case 12: // ^L
            out("\u{1B}[2J\u{1B}[H")
        default:
            out("^" + String(UnicodeScalar(code + 64)))
        }
    }

    // MARK: Command execution

    private func execute(_ line: String) {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let name = parts.first, !name.isEmpty else {
            prompt()
            return
        }
        let args = Array(parts.dropFirst())

        switch name {
        case "help": out(helpText)
        case "clear": out("\u{1B}[2J\u{1B}[H")
        case "echo": out(args.joined(separator: " "))
        case "pwd": out(cwd.path)
        case "ls": listDirectory(args.first)
        case "cd": changeDirectory(args.first)
        case "cat": catFile(args.first)
        case "date": out(Date().description)
        case "uname": out("Linux localhost 6.6.31-termux-swift \(manager.config.activeDistro) GNU/Linux")
        case "whoami": out("root")
        case "ps": out(psText)
        case "pkg", "apt", "apt-get": apk(args)
        case "apk": apk(args)
        case "proot-distro", "proot_distro": prootDistro(args)
        case "exit", "logout":
            out("logout")
            delegate?.sessionDidExit(self)
            return
        default:
            out("\(name): command not found")
        }
        prompt()
    }

    // MARK: proot-distro

    private func prootDistro(_ args: [String]) {
        let sub = args.first ?? "help"
        let target = args.count > 1 ? args[1] : nil

        switch sub {
        case "help", "--help":
            out("""
            Usage: proot-distro [list]
                                [install <distro>]
                                [login <distro>]
                                [remove <distro>]
            Installing or logging into a distro swaps the active rootfs in
            the config and reboots the termux-swift environment.
            """)
        case "list":
            out("Supported distributions:")
            for (name, _) in manager.registry.sorted(by: { $0.key < $1.key }) {
                var status = ""
                if manager.config.activeDistro == name { status = " [running]" }
                else if manager.config.installedDistros.contains(name) { status = " [installed]" }
                out("  \(name)\(status)")
            }
        case "install":
            guard let name = target else {
                out("proot-distro install: distro name required")
                return
            }
            if manager.install(name, { line in out(line) }) {
                swapTo(name)
            }
        case "login":
            guard let name = target else {
                out("proot-distro login: distro name required")
                return
            }
            guard manager.config.installedDistros.contains(name) else {
                out("proot-distro login: '\(name)' is not installed.")
                out("Run 'proot-distro install \(name)' first.")
                return
            }
            swapTo(name)
        case "remove":
            guard let name = target else {
                out("proot-distro remove: distro name required")
                return
            }
            if let error = manager.remove(name) {
                out(error)
            } else {
                out("Removed '\(name)' rootfs.")
            }
        default:
            out("proot-distro: unknown command '\(sub)'")
        }
    }

    /// The behavior you specified: swap the config to the new distro, then
    /// reboot the environment. (The app itself stays running — iOS apps can't
    /// relaunch themselves, and restarting the engine achieves the same thing
    /// without killing the UI.)
    private func swapTo(_ name: String) {
        out("")
        out("Setting default distro: \(manager.config.activeDistro) -> \(name)")
        out("Rebooting termux-swift environment ...")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            self.manager.setActive(name)
            self.onDistroChanged?()
        }
    }

    // MARK: apk (Alpine package manager, as you'd find in the proot)

    private func apk(_ args: [String]) {
        guard let sub = args.first else {
            out("apk-tools 2.14.0, compiled for aarch64")
            return
        }
        switch sub {
        case "add", "install":
            let pkgs = args.dropFirst()
            if pkgs.isEmpty {
                out("ERROR: unsatisfiable constraints:")
                return
            }
            for pkg in pkgs {
                out("fetch \(pkg)-1.0 ...")
            }
            out("(\(pkgs.count)/\(pkgs.count)) Installing \(pkgs.joined(separator: " "))")
            out("OK: \(20 + pkgs.count * 4) MiB in \(32 + pkgs.count) packages")
        case "list", "info":
            out("busybox-1.36.1-r0, bash-5.2.15-r5, coreutils-9.4-r1, apk-tools-2.14.0-r0")
        default:
            out("apk: unrecognized operation '\(sub)'")
        }
    }

    // MARK: File commands (operate on the real app sandbox for now)

    private func listDirectory(_ path: String?) {
        let url = resolve(path ?? ".")
        do {
            let entries = try FileManager.default.contentsOfDirectory(atPath: url.path)
            out(entries.map { entry -> String in
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: url.appendingPathComponent(entry).path, isDirectory: &isDir)
                return isDir.boolValue ? "\(entry)/" : entry
            }.sorted().joined(separator: "  "))
        } catch {
            out("ls: \(path ?? "."): \(error.localizedDescription)")
        }
    }

    private func changeDirectory(_ path: String?) {
        let target = resolve(path ?? FileManager.default.homeDirectoryForCurrentUser.path)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir), isDir.boolValue {
            cwd = target
        } else {
            out("cd: \(path ?? ""): not a directory")
        }
    }

    private func catFile(_ path: String?) {
        guard let path else {
            out("usage: cat <file>")
            return
        }
        do {
            let data = try Data(contentsOf: resolve(path))
            out(String(decoding: data.prefix(8192), as: UTF8.self))
        } catch {
            out("cat: \(path): \(error.localizedDescription)")
        }
    }

    private func resolve(_ path: String) -> URL {
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        if path == "." { return cwd }
        if path == ".." { return cwd.deletingLastPathComponent() }
        return cwd.appendingPathComponent(path)
    }

    // MARK: Presentation

    private var promptString: String {
        switch manager.config.activeDistro {
        case "alpine": return "localhost:~# "
        case "ubuntu", "debian": return "root@localhost:~# "
        default: return "\(manager.config.activeDistro):~# "
        }
    }

    private func prompt() {
        out(promptString, newline: false)
    }

    private func bootBanner() {
        out("termux-swift 1.0 — proot environment: \(manager.config.activeDistro)")
        out("")
        out("[  OK  ] translated / -> Documents/termux-swift/distros/\(manager.config.activeDistro)")
        out("[  OK  ] mounted /proc /sys /dev (virtual)")
        out("[  OK  ] started busybox userland (simulated)")
        out("")
        out("The shell is simulated until the CPU-emulation engine lands.")
        out("Type 'help' for commands, 'proot-distro list' for distros.")
        out("")
    }

    private var psText: String {
        """
        PID   USER  TIME  COMMAND
          1   root  0:00  /sbin/init
         42   root  0:00  busybox sh
         57   root  0:00  ps
        """
    }

    private var helpText: String {
        """
        Termux-style commands available in this environment:
          help, clear, echo, pwd, ls, cd, cat, date, whoami, uname, ps
          apk add <pkg> ...        Alpine package manager (simulated)
          proot-distro list        list available distros
          proot-distro install <d> install + swap + reboot environment
          proot-distro login <d>   swap to an installed distro + reboot
          proot-distro remove <d>  remove an installed distro
          exit                     close this session
        """
    }

    private func out(_ text: String, newline: Bool = true) {
        let s = newline ? text + "\r\n" : text
        delegate?.session(self, didOutput: Data(s.utf8))
    }
}
