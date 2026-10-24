import Foundation

enum GridlinePreferences {
    static let scrollbackLimitKey = "gridline.terminal.scrollbackLimit"
    static let scrollbackLimitChanged = Notification.Name("gridlineScrollbackLimitChanged")
    static let scrollbackLimitUserInfoKey = "scrollbackLimit"
    static let defaultScrollbackLimit = 10_000
    static let scrollbackLimitOptions = [1_000, 5_000, 10_000, 25_000]

    static func scrollbackLimit(from defaults: UserDefaults = .standard) -> Int {
        let savedLimit = defaults.integer(forKey: scrollbackLimitKey)
        return scrollbackLimitOptions.contains(savedLimit) ? savedLimit : defaultScrollbackLimit
    }
}
