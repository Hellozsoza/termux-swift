# Termux Swift

**Termux Swift** is a fork of [Termux](https://github.com/termux/termux-app), the terminal emulator and Linux environment app for Android. It currently tracks upstream `master` and serves as a base for fork-specific work. The original upstream README is preserved in [`README.md.old`](README.md.old).

Termux gives you a complete Linux command-line environment on your phone or tablet — no rooting, no setup, and no ads:

- A full terminal emulator with a large on-screen keyboard and extra-keys row
- A package ecosystem via `pkg` / `apt` with bash, zsh, ssh, git, python, clang, rust, node and hundreds more
- The ability to run servers, editors, compilers and scripts right on the device, including via [proot-distro](https://github.com/termux/proot-distro) whole Linux distributions
- Remote access through SSH into your device

## Highlights

Recent features inherited from upstream include:

- **Inline terminal images** — support for Sixel (`DCS q`) and iTerm2 (`OSC 1337`) image protocols, so tools like `img2sixel` and `imgcat` can display images directly in the terminal
- A **64 KB read buffer** (up from 4 KB), which greatly reduces lag when scrolling in terminal multiplexers like `tmux`
- **External keyboard fixes**, including proper handling of the language-switch key
- **Security hardening** of `RunCommandService`, preventing result files from being written before `allow-external-app` is verified

## Installation

> **Important:** do **not** install the Termux app from the Google Play Store — it is outdated and no longer supported.

Supported installation sources for the upstream app:

- [F-Droid](https://f-droid.org/en/packages/com.termux/)
- [GitHub Releases](https://github.com/termux/termux-app/releases)

For this fork, build the APK yourself (see below) or grab CI artifacts if available.

## Building from source

Requirements:

- JDK 17 or newer
- Android SDK (with Build Tools; the NDK is needed for some components)
- Android 7.0+ device or emulator to run the result

```bash
git clone https://github.com/Hellozsoza/termux-swift.git
cd termux-swift
./gradlew assembleDebug
```

The debug APK will land in `app/build/outputs/apk/debug/`. For a signed release build, use `./gradlew assembleRelease` with your own signing config.

## Project layout

| Path | Description |
| --- | --- |
| `app/` | The main Termux application (activities, services, UI) |
| `terminal-emulator/` | Terminal emulation library (VT100/xterm escape-sequence handling) |
| `terminal-view/` | View library that renders the emulator to screen and handles input |
| `termux-shared/` | Shared library used by Termux and its add-on apps |
| `fastlane/` | Release/store metadata |
| `docs/` | Additional documentation |

## Documentation

- [Termux website](https://termux.dev)
- [Termux wiki](https://wiki.termux.com)
- [Termux packages](https://github.com/termux/termux-packages) — package bugs and requests belong there, **not** here
- [Upstream repository](https://github.com/termux/termux-app)

## Credits

Termux Swift is based on the work of the [Termux team](https://github.com/termux) — including Fredrik Fornwall, agnostic-apollo and many contributors — with the upstream commit history preserved in this fork.

## License

Released under the [GNU General Public License v3](LICENSE.md). The upstream project's copyright and license apply to all inherited code.