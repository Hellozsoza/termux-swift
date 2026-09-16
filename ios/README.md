# termux-swift (iOS)

A Swift rewrite of the Termux Android terminal app for iOS, mirroring the
original repo's Gradle module structure.

## Module mapping

| Android (original repo)                | iOS / Swift port                  |
| -------------------------------------- | --------------------------------- |
| `terminal-emulator` (Java, ~175 KB core)| `TerminalEmulator.swift`          |
| `terminal-view` (Android custom View)   | `TerminalView.swift` (UIKit)      |
| `TerminalSession.java` + JNI + fork/pty | `TerminalSession.swift` protocol |
| `app` (TermuxActivity, Gradle)          | `TermuxSwiftApp.swift` (SwiftUI)  |
| `termux-shared`                         | folded into the files above       |
| `build.gradle` / Gradle modules         | single Xcode app target           |

## Files

- `TerminalEmulator.swift` — VT100/xterm subset: CSI cursor movement
  (CUU/CUD/CUF/CUB/CUP/CHA/VPA), erase (ED/EL), scroll (SU/SD), SGR colors
  (16-color), OSC title, ESC 7/8 save/restore, autowrap, resize.
- `TerminalSession.swift` — session abstraction + `DemoShellSession`, an
  in-process shell (`help`, `clear`, `echo`, `pwd`, `ls`, `cd`, `cat`,
  `date`, `uname`, `exit`) operating on the app sandbox.
- `TerminalView.swift` — UIKit view: run-length text rendering, software
  keyboard via `UIKeyInput`, hardware arrows/esc via `presses`, accessory
  key bar (ESC / TAB / CTRL / arrows), themes with the xterm 16-color palette.
- `TermuxSwiftApp.swift` — SwiftUI app entry point and view controller wiring.

## Build

1. Xcode → File → New → Project → iOS App. Name it `TermuxSwift`.
2. Delete the generated `ContentView.swift` and the `App` file.
3. Add the four `.swift` files above to the target.
4. Run on the iPhone simulator or a device. Type `help` in the terminal.

## The big platform difference

Termux on Android opens a pseudoterminal and execs `/system/bin/sh`.
**iOS does not allow a sandboxed app to spawn child processes** —
`fork()` / `posix_spawn()` fail with "Operation not permitted" — so there is
no local `/bin/sh` on a stock iPhone. Every real iOS terminal picks one of
these strategies:

1. **Remote session (SSH/Mosh)** — the shell runs on a machine you control
   (Mac, Linux box, VPS, Raspberry Pi). Add an `SSHSession` conforming to
   `TerminalSession` using SwiftSH, NMSSH, or Citadel.
2. **In-process commands** — compile tools into the app (a-Shell's approach).
   The `DemoShellSession` is a minimal version of this.
3. **User-mode CPU emulation** — run an Alpine rootfs inside the app
   (iSH's approach). A very large project of its own.

## Roadmap

- [ ] DECSTBM scroll regions, DECSET private modes, alt screen buffer
- [ ] 256-color and RGB SGR (38/48 with `;5;n` and `;2;r;g;b`)
- [ ] `SSHSession` with key storage in the Secure Enclave
- [ ] Termux-style extra-keys row and gestures
- [ ] Pasteboard support, text selection
- [ ] If full xterm fidelity is needed, consider building on
  [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm), which already
  implements the complete VT100/xterm spec (Sixel, mouse, etc.) with an
  iOS UIKit front end — then keep this repo's UI/session layer on top.

## License

Keep the original repository's license terms in mind when porting code.
