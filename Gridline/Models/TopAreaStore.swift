//
//  TopAreaStore.swift
//  Gridline
//
//  Sesi area atas satu repo: tab "Diff" (tidak bisa ditutup) + tab viewer
//  file yang dibuka dari terminal/diff (bagian 4 & 7 apps-spec.md). Hidup
//  lepas dari pane, sama seperti RepoSession dan RepoDiffStore.
//

import Combine
import Foundation

enum TopTabSelection: Hashable {
    case diff
    case file(UUID)
}

@MainActor
final class TopAreaStore: ObservableObject {
    @Published private(set) var openFiles: [FileViewerTab] = []
    @Published var selection: TopTabSelection = .diff

    /// Membuka file di viewer. Jika sudah terbuka, tab yang ada dipilih —
    /// tidak dibuat duplikat (bagian 7 & 9 apps-spec.md).
    @discardableResult
    func openFile(path: String, scrollToLine: Int? = nil) -> FileViewerTab {
        if let existing = openFiles.first(where: { $0.path == path }) {
            selection = .file(existing.id)
            if let scrollToLine {
                existing.scrollToLine(scrollToLine)
            }
            return existing
        }
        let tab = FileViewerTab(path: path, scrollToLine: scrollToLine)
        openFiles.append(tab)
        selection = .file(tab.id)
        return tab
    }

    func closeFile(id: UUID) {
        openFiles.removeAll { $0.id == id }
        if case .file(let selectedID) = selection, selectedID == id {
            selection = .diff
        }
    }
}
