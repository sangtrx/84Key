import Foundation

/// Lightweight settings store for SangKey.
///
/// This deliberately avoids Combine/ObservableObject. Settings changes are rare,
/// so each property persists only its own value and pushes only that option to
/// the C++ engine. The hot input path never touches this class.
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard
    private weak var controller: InputController?

    var onChange: (() -> Void)?

    static let registeredDefaults: [String: Any] = [
        "vLanguage": 1,
        "vInputType": 0,
        "vCodeTable": 0,
        "vFreeMark": 0,
        "vCheckSpelling": 1,
        "vUseModernOrthography": 1,
        "vQuickTelex": 0,
        "vRestoreIfWrongSpelling": 0,
        "vFixRecommendBrowser": 0,
        "vFixWebContentEditor": 1,
        "vUseMacro": 0,
        "vUseSmartSwitchKey": 1,
        "vUpperCaseFirstChar": 0,
        "vAllowConsonantZFWJ": 0,
        "vQuickStartConsonant": 0,
        "vQuickEndConsonant": 0,
        "vAutoDetectEnglish": 1,
        "vOtherLanguage": 0,
        "vFixSpotlight": 1,
        "vSendKeyStepByStep": 0,
        "vFixChromiumBrowser": 0,
        "vPerformLayoutCompat": 0,
        "vSwitchKeyStatus": 0x531,
        "runOnStartup": 0,
    ]

    var language: Int { didSet { commit("vLanguage", language) } }
    var inputType: Int { didSet { commit("vInputType", inputType) } }
    var codeTable: Int { didSet { commit("vCodeTable", codeTable) } }
    var freeMark: Bool { didSet { commit("vFreeMark", freeMark) } }
    var checkSpelling: Bool { didSet { commit("vCheckSpelling", checkSpelling) } }
    var modernOrthography: Bool { didSet { commit("vUseModernOrthography", modernOrthography) } }
    var quickTelex: Bool { didSet { commit("vQuickTelex", quickTelex) } }
    var restoreIfWrongSpelling: Bool { didSet { commit("vRestoreIfWrongSpelling", restoreIfWrongSpelling) } }
    var fixRecommendBrowser: Bool { didSet { commit("vFixRecommendBrowser", fixRecommendBrowser) } }
    var fixWebContentEditor: Bool { didSet { commit("vFixWebContentEditor", fixWebContentEditor) } }
    var useMacro: Bool { didSet { commit("vUseMacro", useMacro) } }
    var smartSwitchKey: Bool { didSet { commit("vUseSmartSwitchKey", smartSwitchKey) } }
    var upperCaseFirstChar: Bool { didSet { commit("vUpperCaseFirstChar", upperCaseFirstChar) } }
    var allowZFWJ: Bool { didSet { commit("vAllowConsonantZFWJ", allowZFWJ) } }
    var quickStartConsonant: Bool { didSet { commit("vQuickStartConsonant", quickStartConsonant) } }
    var quickEndConsonant: Bool { didSet { commit("vQuickEndConsonant", quickEndConsonant) } }
    var autoDetectEnglish: Bool { didSet { commit("vAutoDetectEnglish", autoDetectEnglish) } }
    var otherLanguage: Bool { didSet { commit("vOtherLanguage", otherLanguage) } }
    var fixSpotlight: Bool { didSet { commit("vFixSpotlight", fixSpotlight) } }
    var switchKey: Int { didSet { commit("vSwitchKeyStatus", switchKey) } }
    private(set) var runOnStartup: Bool

    private init() {
        defaults.register(defaults: Self.registeredDefaults)
        language = defaults.integer(forKey: "vLanguage")
        inputType = defaults.integer(forKey: "vInputType")
        codeTable = defaults.integer(forKey: "vCodeTable")
        freeMark = defaults.bool(forKey: "vFreeMark")
        checkSpelling = defaults.bool(forKey: "vCheckSpelling")
        modernOrthography = defaults.bool(forKey: "vUseModernOrthography")
        quickTelex = defaults.bool(forKey: "vQuickTelex")
        restoreIfWrongSpelling = defaults.bool(forKey: "vRestoreIfWrongSpelling")
        fixRecommendBrowser = defaults.bool(forKey: "vFixRecommendBrowser")
        fixWebContentEditor = defaults.bool(forKey: "vFixWebContentEditor")
        useMacro = defaults.bool(forKey: "vUseMacro")
        smartSwitchKey = defaults.bool(forKey: "vUseSmartSwitchKey")
        upperCaseFirstChar = defaults.bool(forKey: "vUpperCaseFirstChar")
        allowZFWJ = defaults.bool(forKey: "vAllowConsonantZFWJ")
        quickStartConsonant = defaults.bool(forKey: "vQuickStartConsonant")
        quickEndConsonant = defaults.bool(forKey: "vQuickEndConsonant")
        autoDetectEnglish = defaults.bool(forKey: "vAutoDetectEnglish")
        otherLanguage = defaults.bool(forKey: "vOtherLanguage")
        fixSpotlight = defaults.bool(forKey: "vFixSpotlight")
        switchKey = defaults.integer(forKey: "vSwitchKeyStatus")
        runOnStartup = defaults.bool(forKey: "runOnStartup")
    }

    func attach(_ controller: InputController) {
        self.controller = controller
        controller.applyEngineOptions(engineValues.mapValues { NSNumber(value: $0) })
    }

    /// Ask ServiceManagement for the requested state and store the effective
    /// result. This avoids a toggle that says ON when macOS rejected the request.
    @discardableResult
    func setRunOnStartup(_ requested: Bool) -> Bool {
        let effective = LoginItemManager.sync(enabled: requested)
        runOnStartup = effective
        defaults.set(effective, forKey: "runOnStartup")
        onChange?()
        return effective
    }

    /// Reconcile a persisted value with the current ServiceManagement state at
    /// launch without creating a Combine subscription that lives forever.
    func reconcileRunOnStartup() {
        _ = setRunOnStartup(runOnStartup)
    }

    private func commit(_ key: String, _ value: Int) {
        defaults.set(value, forKey: key)
        controller?.applyEngineOptions([key: NSNumber(value: value)])
        onChange?()
    }

    private func commit(_ key: String, _ value: Bool) {
        commit(key, value ? 1 : 0)
    }

    private var engineValues: [String: Int] {
        [
            "vLanguage": language,
            "vInputType": inputType,
            "vCodeTable": codeTable,
            "vFreeMark": freeMark ? 1 : 0,
            "vCheckSpelling": checkSpelling ? 1 : 0,
            "vUseModernOrthography": modernOrthography ? 1 : 0,
            "vQuickTelex": quickTelex ? 1 : 0,
            "vRestoreIfWrongSpelling": restoreIfWrongSpelling ? 1 : 0,
            "vFixRecommendBrowser": fixRecommendBrowser ? 1 : 0,
            "vFixWebContentEditor": fixWebContentEditor ? 1 : 0,
            "vUseMacro": useMacro ? 1 : 0,
            "vUseSmartSwitchKey": smartSwitchKey ? 1 : 0,
            "vUpperCaseFirstChar": upperCaseFirstChar ? 1 : 0,
            "vAllowConsonantZFWJ": allowZFWJ ? 1 : 0,
            "vQuickStartConsonant": quickStartConsonant ? 1 : 0,
            "vQuickEndConsonant": quickEndConsonant ? 1 : 0,
            "vAutoDetectEnglish": autoDetectEnglish ? 1 : 0,
            "vOtherLanguage": otherLanguage ? 1 : 0,
            "vFixSpotlight": fixSpotlight ? 1 : 0,
            "vSwitchKeyStatus": switchKey,
        ]
    }
}
