import AppKit

/// User-initiated browser navigation only. No background updater, network client,
/// installer helper or Combine object lives inside the keyboard process.
final class UpdaterController {
    static let shared = UpdaterController()
    private init() {}

    func checkForUpdates() {
        guard let url = URL(string: "https://github.com/sangtrx/SangKey/releases/latest") else { return }
        NSWorkspace.shared.open(url)
    }
}
