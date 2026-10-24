//
//  FileViewerTab.swift
//  Gridline
//
//  Satu tab viewer file read-only. Isi dimuat ulang otomatis saat file
//  berubah di disk; event sibling yang tidak mengubah fingerprint dilewati.
//  Tab tetap terbuka dengan pesan "tidak ditemukan" jika file dihapus.
//

import Combine
import Foundation

@MainActor
final class FileViewerTab: Identifiable, ObservableObject {
    let id = UUID()
    let path: String

    @Published private(set) var loadedFile: FileLoadResult?
    @Published var pendingScrollLine: Int?

    var content: FileContent {
        loadedFile?.content ?? .loading
    }

    var lineStartOffsets: [UInt32] {
        loadedFile?.lineStartOffsets ?? [0]
    }

    private var watcher: RepoFileWatcher?
    private var isWatching: Bool
    private var lastFingerprint: FileFingerprint?
    private var hasLoaded = false
    private var isReloading = false
    private var reloadRequested = false

    var displayName: String {
        (path as NSString).lastPathComponent
    }

    init(path: String, scrollToLine: Int? = nil, isWatching: Bool = true) {
        self.path = path
        self.pendingScrollLine = scrollToLine
        self.isWatching = isWatching
        if isWatching {
            watchParentDirectory()
        }
        Task { await reload() }
    }

    func setWatching(_ shouldWatch: Bool) {
        guard isWatching != shouldWatch else { return }
        isWatching = shouldWatch
        if shouldWatch {
            watchParentDirectory()
            Task { await reload() }
        } else {
            watcher?.stop()
            watcher = nil
        }
    }

    func reload() async {
        guard !isReloading else {
            reloadRequested = true
            return
        }

        isReloading = true
        repeat {
            reloadRequested = false
            let path = self.path
            let previousFingerprint = lastFingerprint
            let wasLoaded = hasLoaded
            let currentFingerprint = await Task.detached(priority: .utility) {
                FileLoader.fingerprint(path: path)
            }.value
            guard !wasLoaded || currentFingerprint != previousFingerprint else { continue }

            let loaded = await Task.detached(priority: .userInitiated) {
                FileLoader.load(path: path)
            }.value
            loadedFile = loaded
            lastFingerprint = loaded.fingerprint
            hasLoaded = true
        } while reloadRequested
        isReloading = false
    }

    /// Meminta viewer scroll ke baris tertentu (dipakai Cmd+klik dari terminal di M2 langkah 7).
    func scrollToLine(_ line: Int) {
        pendingScrollLine = line
    }

    private func watchParentDirectory() {
        guard watcher == nil else { return }
        let parent = (path as NSString).deletingLastPathComponent
        guard !parent.isEmpty else { return }
        watcher = RepoFileWatcher(path: parent, latency: 0.3) { [weak self] in
            Task { await self?.reload() }
        }
    }
}
