import Foundation
import OSLog

enum DiagnosticEvent {
    case appLaunched
    case terminalStartFailed
    case terminalExited(Int32?)
    case gitStatusFailed(Int32)
    case gitPullFailed(Int32)
    case appStatePersistenceFailed(Int)
    case logExportRequested
    case logExported
    case logExportFailed

    var message: String {
        switch self {
        case .appLaunched:
            return "app.launched"
        case .terminalStartFailed:
            return "terminal.start_failed"
        case .terminalExited(let exitCode):
            return "terminal.exited exit_code=\(exitCode.map(String.init) ?? "unknown")"
        case .gitStatusFailed(let exitCode):
            return "git.status_failed exit_code=\(exitCode)"
        case .gitPullFailed(let exitCode):
            return "git.pull_failed exit_code=\(exitCode)"
        case .appStatePersistenceFailed(let errorCode):
            return "app_state.persistence_failed error_code=\(errorCode)"
        case .logExportRequested:
            return "diagnostics.export_requested"
        case .logExported:
            return "diagnostics.exported"
        case .logExportFailed:
            return "diagnostics.export_failed"
        }
    }
}

final class DiagnosticLog {
    static let shared = DiagnosticLog()

    private static let maximumEventCount = 500
    private let lock = NSLock()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Gridline", category: "diagnostics")
    private var events: [String] = []

    private init() {}

    func record(_ event: DiagnosticEvent) {
        let timestamp = ISO8601DateFormatter().string(from: .now)
        let entry = "\(timestamp) \(event.message)"

        lock.lock()
        events.append(entry)
        if events.count > Self.maximumEventCount {
            events.removeFirst(events.count - Self.maximumEventCount)
        }
        lock.unlock()

        logger.info("\(event.message, privacy: .public)")
    }

    func report(gitVersion: String) -> String {
        lock.lock()
        let eventSnapshot = events
        lock.unlock()

        let info = Bundle.main.infoDictionary ?? [:]
        let appVersion = info["CFBundleShortVersionString"] as? String ?? String(localized: L10n.Diagnostics.unknown)
        let buildVersion = info["CFBundleVersion"] as? String ?? String(localized: L10n.Diagnostics.unknown)
        let generatedAt = ISO8601DateFormatter().string(from: .now)

        return [
            String(localized: L10n.Diagnostics.reportTitle),
            L10n.format(L10n.Diagnostics.generated, generatedAt),
            L10n.format(L10n.Diagnostics.appVersion, appVersion, buildVersion),
            L10n.format(L10n.Diagnostics.macOSVersion, ProcessInfo.processInfo.operatingSystemVersionString),
            L10n.format(L10n.Diagnostics.gitVersion, gitVersion),
            "",
            String(localized: L10n.Diagnostics.events),
            eventSnapshot.joined(separator: "\n"),
            "",
        ].joined(separator: "\n")
    }
}
