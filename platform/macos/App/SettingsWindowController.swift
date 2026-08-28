import AppKit

/// Lazily-created AppKit settings window. The object exists after first use, but
/// no SwiftUI/Combine graph is loaded into the process at startup or idle.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let settings = AppSettings.shared

    private let inputType = NSPopUpButton(frame: .zero, pullsDown: false)
    private let autoDetect = NSButton(checkboxWithTitle: "Tự động nhận diện tiếng Anh", target: nil, action: nil)
    private let spelling = NSButton(checkboxWithTitle: "Kiểm tra chính tả", target: nil, action: nil)
    private let modern = NSButton(checkboxWithTitle: "Chính tả hiện đại", target: nil, action: nil)
    private let spotlight = NSButton(checkboxWithTitle: "Ổn định khi gõ Spotlight", target: nil, action: nil)
    private let webEditor = NSButton(checkboxWithTitle: "Ổn định trình duyệt / Google Docs", target: nil, action: nil)
    private let startup = NSButton(checkboxWithTitle: "Khởi động khi đăng nhập", target: nil, action: nil)
    private let shortcut = NSPopUpButton(frame: .zero, pullsDown: false)

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 470),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        window.title = "SangKey — Cài đặt"
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
        window.delegate = self
        buildUI()
        syncFromSettings()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let title = NSTextField(labelWithString: "SangKey")
        title.font = .systemFont(ofSize: 24, weight: .bold)

        let subtitle = NSTextField(wrappingLabelWithString: "Bộ gõ tiếng Việt native cho macOS — ưu tiên nhẹ, riêng tư và phản hồi tức thì.")
        subtitle.textColor = .secondaryLabelColor

        inputType.addItems(withTitles: ["Telex", "VNI", "Simple Telex 1", "Simple Telex 2"])
        inputType.target = self
        inputType.action = #selector(inputTypeChanged)

        let inputRow = row(label: "Kiểu gõ", control: inputType)

        for button in [autoDetect, spelling, modern, spotlight, webEditor, startup] {
            button.target = self
            button.action = #selector(toggleChanged(_:))
        }

        shortcut.addItems(withTitles: ["⌃⌘Space", "⌃Space", "⇧⌘", "Không dùng"])
        shortcut.target = self
        shortcut.action = #selector(shortcutChanged)
        let shortcutRow = row(label: "Chuyển VI/EN", control: shortcut)

        let privacy = NSTextField(wrappingLabelWithString: "Không telemetry · Không network nền · Không auto-updater · Xử lý bàn phím hoàn toàn trên máy.")
        privacy.textColor = .secondaryLabelColor
        privacy.font = .systemFont(ofSize: 11)

        let permission = NSButton(title: "Mở quyền Trợ năng…", target: self, action: #selector(openAccessibility))
        let restart = NSButton(title: "Khởi động lại SangKey", target: self, action: #selector(relaunch))
        let actions = NSStackView(views: [permission, restart])
        actions.orientation = .horizontal
        actions.spacing = 8
        actions.alignment = .centerY

        let stack = NSStackView(views: [
            title,
            subtitle,
            separator(),
            inputRow,
            autoDetect,
            spelling,
            modern,
            separator(),
            spotlight,
            webEditor,
            separator(),
            startup,
            shortcutRow,
            separator(),
            privacy,
            actions,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setHuggingPriority(.defaultLow, for: .horizontal)

        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -22),
            subtitle.widthAnchor.constraint(equalTo: stack.widthAnchor),
            privacy.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func row(label: String, control: NSView) -> NSStackView {
        let text = NSTextField(labelWithString: label)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [text, spacer, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func syncFromSettings() {
        inputType.selectItem(at: max(0, min(3, settings.inputType)))
        autoDetect.state = settings.autoDetectEnglish ? .on : .off
        spelling.state = settings.checkSpelling ? .on : .off
        modern.state = settings.modernOrthography ? .on : .off
        spotlight.state = settings.fixSpotlight ? .on : .off
        webEditor.state = settings.fixWebContentEditor ? .on : .off
        startup.state = settings.runOnStartup ? .on : .off

        let shortcutIndex: Int
        switch settings.switchKey {
        case 0x531: shortcutIndex = 0       // control + command + space
        case 0x131: shortcutIndex = 1       // control + space
        case 0xCFF: shortcutIndex = 2       // shift + command, modifier-only
        case 0: shortcutIndex = 3
        default: shortcutIndex = 0
        }
        shortcut.selectItem(at: shortcutIndex)
    }

    @objc private func inputTypeChanged() {
        settings.inputType = inputType.indexOfSelectedItem
    }

    @objc private func toggleChanged(_ sender: NSButton) {
        let on = sender.state == .on
        switch sender {
        case autoDetect: settings.autoDetectEnglish = on
        case spelling: settings.checkSpelling = on
        case modern: settings.modernOrthography = on
        case spotlight: settings.fixSpotlight = on
        case webEditor: settings.fixWebContentEditor = on
        case startup:
            let effective = settings.setRunOnStartup(on)
            startup.state = effective ? .on : .off
        default: break
        }
    }

    @objc private func shortcutChanged() {
        switch shortcut.indexOfSelectedItem {
        case 0: settings.switchKey = 0x531
        case 1: settings.switchKey = 0x131
        case 2: settings.switchKey = 0xCFF
        default: settings.switchKey = 0
        }
    }

    @objc private func openAccessibility() {
        AppController.shared.openAccessibilitySettings()
    }

    @objc private func relaunch() {
        AppController.shared.relaunch()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        syncFromSettings()
    }
}
