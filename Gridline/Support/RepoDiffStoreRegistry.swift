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

    func store(for repo: Repo) -> RepoDiffStore {
        if let existing = stores[repo.id] {
            return existing
        }
        let store = RepoDiffStore(repoPath: repo.path)
        stores[repo.id] = store
        store.setWatching(visibleRepoIDs.contains(repo.id))
        return store
    }

    func setVisibleRepoIDs(_ repoIDs: Set<UUID>) {
        guard visibleRepoIDs != repoIDs else { return }
        visibleRepoIDs = repoIDs
        stores.forEach { repoID, store in
            store.setWatching(repoIDs.contains(repoID))
        }
    }
}
