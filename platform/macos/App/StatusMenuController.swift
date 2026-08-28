import AppKit

/// Tiny AppKit status-menu surface. No SwiftUI scene graph is kept alive while
/// SangKey sits in the menu bar.
@MainActor
final class StatusMenuController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private lazy var settingsWindow = SettingsWindowController()

    override init() {
        super.init()
        statusItem.menu = menu
        AppSettings.shared.onChange = { [weak self] in self?.refresh() }
        AppController.shared.onStateChange = { [weak self] in self?.refresh() }
        refresh()
    }

    func refresh() {
        let settings = AppSettings.shared
        let app = AppController.shared

        if let button = statusItem.button {
            button.title = app.isRunning ? (settings.language == 1 ? "V" : "E") : "!"
            button.toolTip = app.isRunning ? "SangKey" : "SangKey cần quyền Trợ năng"
        }

        menu.removeAllItems()

        if !app.isRunning {
            let warning = NSMenuItem(title: "Cần quyền Trợ năng", action: #selector(openAccessibility), keyEquivalent: "")
            warning.target = self
            menu.addItem(warning)
            menu.addItem(.separator())
        }

        let vi = NSMenuItem(title: "Tiếng Việt", action: #selector(useVietnamese), keyEquivalent: "")
        vi.target = self
        vi.state = settings.language == 1 ? .on : .off
        menu.addItem(vi)

        let en = NSMenuItem(title: "English", action: #selector(useEnglish), keyEquivalent: "")
        en.target = self
        en.state = settings.language == 0 ? .on : .off
        menu.addItem(en)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Cài đặt…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let update = NSMenuItem(title: "Kiểm tra cập nhật…", action: #selector(checkUpdates), keyEquivalent: "")
        update.target = self
        menu.addItem(update)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Thoát SangKey", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func useVietnamese() {
        AppSettings.shared.language = 1
    }

    @objc private func useEnglish() {
        AppSettings.shared.language = 0
    }

    @objc private func openAccessibility() {
        AppController.shared.openAccessibilitySettings()
    }

    @objc private func openSettings() {
        settingsWindow.showWindow(nil)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        settingsWindow.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func checkUpdates() {
        UpdaterController.shared.checkForUpdates()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
