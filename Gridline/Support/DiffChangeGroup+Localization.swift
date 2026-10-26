import Foundation

extension DiffChangeGroup {
    var label: LocalizedStringResource {
        switch self {
        case .staged: L10n.Diff.staged
        case .unstaged: L10n.Diff.unstaged
        case .untracked: L10n.Diff.untracked
        case .ignored: L10n.Diff.ignored
        }
    }
}
