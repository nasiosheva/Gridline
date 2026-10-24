//
//  RepoOpener.swift
//  Gridline
//
//  Dialog pemilihan folder (NSOpenPanel) dan validasi bahwa folder yang
//  dipilih adalah repo Git. Tanpa App Sandbox (D16/D17): path disimpan apa
//  adanya, tidak perlu security-scoped bookmark.
//

import AppKit

enum RepoOpenError: LocalizedError {
    case notAGitRepo(path: String)

    var errorDescription: String? {
        switch self {
        case .notAGitRepo(let path):
            return L10n.format(L10n.Repository.invalidRepositoryMessage, path)
        }
    }
}

enum RepoOpener {
    /// Menampilkan NSOpenPanel untuk memilih folder repo. Mengembalikan `nil`
    /// jika pengguna membatalkan dialog.
    @MainActor
    static func choosePanelRepoPath() -> Result<String, RepoOpenError>? {
        let panel = NSOpenPanel()
        panel.title = String(localized: L10n.Repository.openTitle)
        panel.message = String(localized: L10n.Repository.openPrompt)
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        let path = url.path
        let gitPath = url.appendingPathComponent(".git").path
        guard FileManager.default.fileExists(atPath: gitPath) else {
            return .failure(.notAGitRepo(path: path))
        }
        return .success(path)
    }
}
