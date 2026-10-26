import Foundation

enum GitPullResult: Equatable {
    case succeeded
    case failed
}

enum GitPullService {
    /// Pulls configured upstream changes only when Git can fast-forward safely.
    /// This is the only direct Git mutation exposed by the repository status UI.
    static func pull(at path: String) async -> GitPullResult {
        let output = await GitProcess.run(
            ["pull", "--ff-only"],
            at: path,
            environment: ["GIT_TERMINAL_PROMPT": "0"]
        )
        guard output.exitCode == 0 else {
            DiagnosticLog.shared.record(.gitPullFailed(output.exitCode))
            return .failed
        }
        return .succeeded
    }
}
