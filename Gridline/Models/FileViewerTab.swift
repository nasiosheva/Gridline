//
//  FileViewerTab.swift
//  Gridline
//
//  Satu tab viewer file read-only. Isi dimuat ulang otomatis saat file
//  berubah di disk, dan tetap terbuka dengan pesan "tidak ditemukan" jika
//  file dihapus (bagian 7 apps-spec.md).
//

import Combine
import Foundation

@MainActor
final class FileViewerTab: Identifiable, ObservableObject {
    let id = UUID()
    let path: String

    @Published private(set) var content: FileContent = .loading
    @Published var pendingScrollLine: Int?

    private var watcher: RepoFileWatcher?

    var displayName: String {
        (path as NSString).lastPathComponent
    }

    init(path: String, scrollToLine: Int? = nil) {
        self.path = path
        self.pendingScrollLine = scrollToLine
        watchParentDirectory()
        Task { await reload() }
    }

    func reload() async {
        let path = self.path
        let loaded = await Task.detached(priority: .userInitiated) {
            FileLoader.load(path: path)
        }.value
        content = loaded
    }

    /// Meminta viewer scroll ke baris tertentu (dipakai Cmd+klik dari terminal di M2 langkah 7).
    func scrollToLine(_ line: Int) {
        pendingScrollLine = line
    }

    private func watchParentDirectory() {
        let parent = (path as NSString).deletingLastPathComponent
        guard !parent.isEmpty else { return }
        watcher = RepoFileWatcher(path: parent, debounceInterval: 0.3) { [weak self] in
            Task { await self?.reload() }
        }
    }
}
