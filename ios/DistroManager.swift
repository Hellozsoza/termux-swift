import Foundation

/// App-level reimplementation of proot-distro's data model.
///
/// On Android, proot-distro downloads a rootfs tarball, extracts it to
/// $PREFIX/var/lib/proot-distro/installed-rootfs/<name>, and boots it with
/// proot. On iOS the proot *engine* is impossible (ptrace + native exec are
/// both blocked), but the distro lifecycle is just files + config, and that
/// part ports directly:
///
///   Documents/termux-swift/
///     config.json              ← active distro + installed list
///     distros/<name>/          ← extracted rootfs (when the engine lands)
///
/// `proot-distro install/login` mutates the config and the environment is
/// rebooted — same observable behavior as the Termux flow you described.

public final class DistroManager {

    public static let shared = DistroManager()

    public struct Config: Codable {
        public var activeDistro: String = "alpine"
        public var installedDistros: [String] = ["alpine"]
    }

    public private(set) var config: Config {
        didSet { save() }
    }

    /// distro name → rootfs archive URL.
    /// Placeholders for now; swap for real URLs when the emulated engine
    /// lands (Alpine minirootfs, termux/proot-distro release rootfs, etc).
    public let registry: [String: String] = [
        "alpine": "https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/alpine-minirootfs-latest-x86_64.tar.gz",
        "debian": "https://github.com/termux/proot-distro/releases/",
        "ubuntu": "https://github.com/termux/proot-distro/releases/",
    ]

    private let fileURL: URL

    public init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("termux-swift", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("config.json")

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Config.self, from: data) {
            config = decoded
        } else {
            config = Config()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Simulated install for now (real download+extraction slots in here when
    /// the engine exists — URLSession download, tar extraction to distros/<name>).
    /// Returns false when the install could not proceed.
    @discardableResult
    public func install(_ name: String, _ onLine: (String) -> Void) -> Bool {
        guard registry[name] != nil else {
            onLine("proot-distro: unknown distro '\(name)' — see 'proot-distro list'")
            return false
        }
        guard !config.installedDistros.contains(name) else {
            onLine("proot-distro: '\(name)' is already installed.")
            return true
        }
        onLine("Fetching rootfs archive for '\(name)' ...")
        onLine("Extracting rootfs to distros/\(name) ...")
        onLine("Configuring guest environment ...")
        config.installedDistros.append(name)
        return true
    }

    /// Removes an installed distro. The running distro cannot be removed —
    /// exactly like proot-distro refusing to delete the rootfs in use.
    @discardableResult
    public func remove(_ name: String) -> String? {
        guard config.installedDistros.contains(name) else {
            return "proot-distro: '\(name)' is not installed."
        }
        guard config.activeDistro != name else {
            return "proot-distro: cannot remove the running distro '\(name)'."
        }
        config.installedDistros.removeAll { $0 == name }
        return nil
    }

    /// Points the app at a different rootfs; the next environment boot uses it.
    public func setActive(_ name: String) {
        guard config.installedDistros.contains(name) else { return }
        config.activeDistro = name
    }
}
