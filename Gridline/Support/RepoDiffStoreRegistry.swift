//
//  RepoDiffStoreRegistry.swift
//  Gridline
//
//  Menyimpan satu RepoDiffStore per repo, dengan pola yang sama seperti
//  RepoSessionStore: pane hanya meminjam, tidak memiliki, sesi diff repo.
//

import Combine
import Foundation

@MainActor
final class RepoDiffStoreRegistry: ObservableObject {
    private var stores: [UUID: RepoDiffStore] = [:]
    private var visibleRepoIDs = Set<UUID>()

    /// Dipanggil setelah default perbandingan awal sebuah pane worktree dikonsumsi,
    /// dengan repo ID yang bersangkutan — pemanggil (lihat `GridlineApp`) memakai ini
    /// untuk membersihkan `Repo.worktreeBaseBranch` di state tersimpan.
    var onWorktreeBaseBranchConsumed: ((UUID) -> Void)?
    var onComparisonSelectionChanged: ((UUID, DiffComparisonSelection) -> Void)?

    func store(for repo: Repo) -> RepoDiffStore {
        if let existing = stores[repo.id] {
            return existing
        }
        let store = RepoDiffStore(
            repoPath: repo.path,
            initialComparisonBranch: repo.worktreeBaseBranch,
            savedComparisonSelection: repo.diffComparisonSelection
        )
        stores[repo.id] = store
        store.onInitialComparisonBranchConsumed = { [weak self] in
            self?.onWorktreeBaseBranchConsumed?(repo.id)
        }
        store.onComparisonSelectionChanged = { [weak self] selection in
            self?.onComparisonSelectionChanged?(repo.id, selection)
        }
        store.setWatching(visibleRepoIDs.contains(repo.id))
        return store
    }

    func setVisibleRepoIDs(_ repoIDs: Set<UUID>, refreshExisting: Bool = false) {
        guard visibleRepoIDs != repoIDs || refreshExisting else { return }
        let previouslyVisibleRepoIDs = visibleRepoIDs
        visibleRepoIDs = repoIDs
        stores.forEach { repoID, store in
            let shouldWatch = repoIDs.contains(repoID)
            store.setWatching(shouldWatch)
            if refreshExisting && shouldWatch && previouslyVisibleRepoIDs.contains(repoID) {
                store.refreshGitMetadata()
            }
        }
    }

    /// Dipanggil saat aplikasi kembali aktif (lihat `GridlineAppDelegate`).
    /// Polling `.git/HEAD` milik `GitMetadataWatcher` bisa tertahan App Nap
    /// saat Gridline di background, jadi branch yang diubah dari IDE/terminal
    /// lain bisa telat terdeteksi — refresh paksa di sini menyamakannya lagi
    /// begitu pengguna kembali melihat jendela, tanpa menambah polling baru.
    func refreshVisibleGitMetadata() {
        stores.forEach { repoID, store in
            guard visibleRepoIDs.contains(repoID) else { return }
            store.refreshGitMetadata()
        }
    }
}
