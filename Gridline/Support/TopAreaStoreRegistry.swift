//
//  TopAreaStoreRegistry.swift
//  Gridline
//
//  Satu TopAreaStore per repo, pola yang sama dengan RepoSessionStore dan
//  RepoDiffStoreRegistry: pane hanya meminjam, tidak memiliki.
//

import Combine
import Foundation

@MainActor
final class TopAreaStoreRegistry: ObservableObject {
    private var stores: [UUID: TopAreaStore] = [:]

    func store(for repo: Repo) -> TopAreaStore {
        if let existing = stores[repo.id] {
            return existing
        }
        let store = TopAreaStore()
        stores[repo.id] = store
        return store
    }

    func openFiles(for repos: [Repo]) -> [QuickSwitcherFile] {
        repos.flatMap { repo in
            stores[repo.id]?.openFiles.map { tab in
                QuickSwitcherFile(repoID: repo.id, repoName: repo.name, path: tab.path)
            } ?? []
        }
    }

    func selectFile(path: String, in repo: Repo) {
        store(for: repo).openFile(path: path)
    }
}
