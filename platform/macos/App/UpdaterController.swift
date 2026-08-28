import AppKit
import Combine

/// Manual release checker for the hardened distribution.
///
/// Deliberately does not embed an auto-update framework, run a background
/// network client, download code, or install anything. The menu action only
/// opens this fork's GitHub Releases page in the user's default browser; normal
/// macOS/browser security policy handles the request from there.
@MainActor
final class UpdaterController: ObservableObject {
    static let shared = UpdaterController()

    @Published private(set) var canCheckForUpdates = true

    private init() {}

    func checkForUpdates() {
        guard let url = URL(string: "https://github.com/sangtrx/84Key/releases/latest") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
