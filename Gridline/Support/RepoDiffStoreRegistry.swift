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

    func store(for repo: Repo) -> RepoDiffStore {
        if let existing = stores[repo.id] {
            return existing
        }
        let store = RepoDiffStore(repoPath: repo.path)
        stores[repo.id] = store
        return store
    }
}
