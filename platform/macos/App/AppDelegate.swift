import AppKit

/// AppKit entry point. SangKey intentionally avoids SwiftUI so idle runtime is
/// just one LSUIElement process, one NSStatusItem and the CGEvent tap.
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusMenu: StatusMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusMenu = StatusMenuController()
        AppController.shared.startup()
        statusMenu?.refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppController.shared.shutdown()
    }
}
