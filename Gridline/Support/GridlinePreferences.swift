import AppKit

enum GridlinePreferences {
    static let diffFontSizeKey = "gridline.diff.fontSize"
    static let defaultDiffFontSize = 11
    static let minimumDiffFontSize = 9
    static let maximumDiffFontSize = 20

    static let terminalFontSizeKey = "gridline.terminal.fontSize"
    static let terminalFontSizeChanged = Notification.Name("gridlineTerminalFontSizeChanged")
    static let defaultTerminalFontSize = Int(NSFont.systemFontSize)
    static let minimumTerminalFontSize = 9
    static let maximumTerminalFontSize = 24

    static let scrollbackLimitKey = "gridline.terminal.scrollbackLimit"
    static let scrollbackLimitChanged = Notification.Name("gridlineScrollbackLimitChanged")
    static let scrollbackLimitUserInfoKey = "scrollbackLimit"
    static let defaultScrollbackLimit = 10_000
    static let scrollbackLimitOptions = [1_000, 5_000, 10_000, 25_000]

    static func scrollbackLimit(from defaults: UserDefaults = .standard) -> Int {
        let savedLimit = defaults.integer(forKey: scrollbackLimitKey)
        return scrollbackLimitOptions.contains(savedLimit) ? savedLimit : defaultScrollbackLimit
    }

    static func terminalFontSize(from defaults: UserDefaults = .standard) -> Int {
        let savedSize = defaults.integer(forKey: terminalFontSizeKey)
        return (minimumTerminalFontSize...maximumTerminalFontSize).contains(savedSize)
            ? savedSize
            : defaultTerminalFontSize
    }

    static func adjustTerminalFontSize(by amount: Int, defaults: UserDefaults = .standard) {
        let currentSize = terminalFontSize(from: defaults)
        let newSize = adjustedFontSize(currentSize, by: amount, minimum: minimumTerminalFontSize, maximum: maximumTerminalFontSize)
        guard newSize != currentSize else { return }
        defaults.set(newSize, forKey: terminalFontSizeKey)
        NotificationCenter.default.post(name: terminalFontSizeChanged, object: nil)
    }

    static func diffFontSize(from defaults: UserDefaults = .standard) -> Int {
        let savedSize = defaults.integer(forKey: diffFontSizeKey)
        return (minimumDiffFontSize...maximumDiffFontSize).contains(savedSize)
            ? savedSize
            : defaultDiffFontSize
    }

    static func adjustDiffFontSize(by amount: Int, defaults: UserDefaults = .standard) {
        let currentSize = diffFontSize(from: defaults)
        let newSize = adjustedFontSize(currentSize, by: amount, minimum: minimumDiffFontSize, maximum: maximumDiffFontSize)
        guard newSize != currentSize else { return }
        defaults.set(newSize, forKey: diffFontSizeKey)
    }

    static func resetDiffFontSize(defaults: UserDefaults = .standard) {
        defaults.set(defaultDiffFontSize, forKey: diffFontSizeKey)
    }

    private static func adjustedFontSize(_ current: Int, by amount: Int, minimum: Int, maximum: Int) -> Int {
        BoundedValue.clamp(current + amount, to: minimum...maximum)
    }
}
