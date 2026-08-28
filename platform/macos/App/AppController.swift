import AppKit
import Darwin

/// Minimal lifecycle coordinator for SangKey.
///
/// Steady state is event-driven: once the CGEvent tap is alive there is no
/// polling timer. UI listeners are plain closures / NotificationCenter tokens,
/// avoiding Combine and SwiftUI runtime machinery entirely.
@MainActor
final class AppController {
    static let shared = AppController()

    let input = InputController()

    private(set) var isRunning = false
    private(set) var hasPermission = false
    var onStateChange: (() -> Void)?

    private var pollTimer: Timer?
    private var langObserver: NSObjectProtocol?

    private init() {}

    func startup() {
        unsetenv("KEY84_TRACE")

        let settings = AppSettings.shared
        settings.attach(input)
        settings.reconcileRunOnStartup()

        let dictsLoaded = input.loadDictionaries()
        NSLog("SangKey dictionaries loaded = %@", dictsLoaded ? "YES" : "NO")

        langObserver = NotificationCenter.default.addObserver(
            forName: Key84LanguageDidToggleNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let lang = note.userInfo?["language"] as? Int else { return }
            MainActor.assumeIsolated {
                if AppSettings.shared.language != lang {
                    AppSettings.shared.language = lang
                }
                AppController.shared.onStateChange?()
            }
        }

        _ = refresh()
        if !isRunning {
            presentPermissionAlert()
            startPolling()
        }
    }

    func shutdown() {
        pollTimer?.invalidate()
        pollTimer = nil
        if let langObserver {
            NotificationCenter.default.removeObserver(langObserver)
            self.langObserver = nil
        }
        input.stop()
    }

    @discardableResult
    func refresh() -> Bool {
        let oldRunning = isRunning
        let oldPermission = hasPermission

        if !input.isRunning() {
            _ = input.start()
        }
        let running = input.isRunning()
        isRunning = running
        hasPermission = running || input.hasAccessibilityPermission()

        if running {
            stopPolling()
        }
        if oldRunning != isRunning || oldPermission != hasPermission {
            onStateChange?()
        }
        return running
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in _ = self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func openAccessibilitySettings() {
        _ = input.requestAccessibilityPermission()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        startPolling()
    }

    func presentPermissionAlert() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Cho phép SangKey xử lý bàn phím"
        alert.informativeText = "SangKey cần quyền Trợ năng (Accessibility) để gõ tiếng Việt trên toàn hệ thống. Không có dữ liệu gõ nào được gửi ra mạng."
        alert.addButton(withTitle: "Mở Cài đặt Trợ năng")
        alert.addButton(withTitle: "Để sau")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    func relaunch() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
