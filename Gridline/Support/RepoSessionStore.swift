//
//  RepoSessionStore.swift
//  Gridline
//
//  Menyimpan satu RepoSession per repo, lepas dari pane mana pun yang
//  menampilkannya. Pane hanya meminjam referensi dari sini — menutup pane
//  atau mengganti repo aktif tidak boleh menghentikan sesi (D6).
//

import Combine
import Foundation

@MainActor
final class RepoSessionStore: ObservableObject {
    @Published private(set) var attentionRevision = 0
    private var sessions: [UUID: RepoSession] = [:]
    private var attentionObservers: [UUID: AnyCancellable] = [:]

    var runningProcessCount: Int {
        sessions.values.reduce(0) { $0 + $1.runningProcessCount }
    }

    func session(for repo: Repo) -> RepoSession {
        if let existing = sessions[repo.id] {
            return existing
        }
        let session = RepoSession(repoPath: repo.path)
        sessions[repo.id] = session
        attentionObservers[repo.id] = session.objectWillChange.sink { [weak self] _ in
            self?.attentionRevision &+= 1
        }
        return session
    }

    func existingSession(for repo: Repo) -> RepoSession? {
        sessions[repo.id]
    }

    func terminateAllProcesses() {
        sessions.values.forEach { session in
            session.tabs.forEach { $0.terminate() }
        }
    }
}
