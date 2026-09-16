import Foundation

// termux-swift / iOS port
// Swift rewrite of the session layer (originals: TerminalSession.java,
// TerminalSessionClient.java, JNI.java).
//
// IMPORTANT PLATFORM DIFFERENCE
// -----------------------------
// On Android, Termux opens a real pseudoterminal (fork/pty) and execs
// /system/bin/sh. On iOS this is impossible: a sandboxed app cannot spawn
// child processes — fork()/posix_spawn() fail with "Operation not permitted".
// Real iOS terminal apps solve this one of two ways:
//
//   1. Remote session (SSH) — the shell runs on another machine.
//      Libraries: SwiftSH, NMSSH, Citadel.
//   2. Local, in-process "shell" — either commands compiled into the app
//      (a-Shell's approach) or a CPU emulator running an Alpine rootfs
//      (iSH's approach).
//
// Below: the session protocol both strategies plug into, plus a working
// DemoShellSession so the app is usable in the simulator on day one.

public protocol TerminalSession: AnyObject {
    var delegate: TerminalSessionDelegate? { get set }
    func start()
    /// Bytes typed by the user (what would go to the pty master on Android).
    func write(_ data: Data)
    func terminate()
}

public protocol TerminalSessionDelegate: AnyObject {
    /// Bytes produced by the session (what would come from the pty master).
    func session(_ session: TerminalSession, didOutput data: Data)
    func sessionDidExit(_ session: TerminalSession)
}

// MARK: - Demo shell (in-process, sandboxed)

public final class DemoShellSession: TerminalSession {

    public weak var delegate: TerminalSessionDelegate?

    private var inputLine = ""
    private var cwd: URL

    public init() {
        // On iOS this is the app sandbox, not a real home directory.
        cwd = FileManager.default.homeDirectoryForCurrentUser
    }

    public func start() {
        out("termux-swift — Swift rewrite of the Termux terminal app (iOS)")
        out("")
        out("Note: iOS apps cannot spawn real child processes, so this is an")
        out("in-process demo shell, not /bin/sh. Type 'help' for commands.")
        out("")
        prompt()
    }

    public func write(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        for ch in text {
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

    // MARK: Command execution

    private func execute(_ line: String) {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard let name = parts.first.map(String.init) else {
            prompt()
            return
        }
        let args = parts.dropFirst().map(String.init)

        switch name {
        case "help":
            out(helpText)
        case "clear":
            out("\u{1B}[2J\u{1B}[H")
        case "echo":
            out(args.joined(separator: " "))
        case "pwd":
            out(cwd.path)
        case "ls":
            listDirectory(args.first)
        case "cd":
            changeDirectory(args.first)
        case "cat":
            catFile(args.first)
        case "date":
            out(Date().description)
        case "uname":
            out("iOS termux-swift 1.0 arm64")
        case "whoami":
            out("mobile")
        case "exit":
            out("logout")
            delegate?.sessionDidExit(self)
            return
        default:
            out("\(name): command not found (try 'help')")
        }
        prompt()
    }

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
        let url = resolve(path)
        do {
            let data = try Data(contentsOf: url)
            if data.count > 8192 {
                out("(file is \(data.count) bytes, showing first 8 KB)")
            }
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

    private func prompt() {
        out("termux@ios:\(cwd.lastPathComponent.isEmpty ? "/" : cwd.lastPathComponent)$ ", newline: false)
    }

    private var helpText: String {
        """
        Built-in commands:
          help          show this text
          clear         clear the screen
          echo <text>   print text
          pwd           print working directory (app sandbox)
          ls [path]     list directory contents
          cd <path>     change directory
          cat <file>    print a file (max 8 KB)
          date          current date and time
          uname         system info
          whoami        current user
          exit          close the session
        """
    }

    private func out(_ text: String, newline: Bool = true) {
        let s = newline ? text + "\r\n" : text
        delegate?.session(self, didOutput: Data(s.utf8))
    }
}
