//
//  Repo.swift
//  Gridline
//
//  Model repo: identitas dan path. Lihat bagian "Model data" di apps-spec.md —
//  sesi terminal TIDAK disimpan di sini sebagai value, melainkan akan dikelola
//  oleh RepoSession (class, identity-based) agar tidak ikut hilang saat repo
//  ditutup dari pane (D6).
//

import Foundation

enum DiffComparisonSelection: Codable, Hashable {
    case localChanges
    case againstBranch(String)
    case betweenBranches(base: String, target: String)
}

struct Repo: Identifiable, Codable, Hashable {
    let id: UUID
    var path: String
    var displayName: String?
    var worktreeSourceRepoID: UUID?
    var worktreeBranch: String?
    var diffComparisonSelection: DiffComparisonSelection?
    /// Branch yang sedang aktif di repo asal saat worktree ini dibuka (bagian "Buka
    /// branch di pane baru"). Dipakai sebagai perbandingan awal di panel diff supaya
    /// pane baru langsung menunjukkan apa yang berbeda dari branch tersebut, bukan
    /// "Local Changes" yang kosong untuk worktree yang baru dibuat.
    var worktreeBaseBranch: String?

    init(
        id: UUID = UUID(),
        path: String,
        displayName: String? = nil,
        worktreeSourceRepoID: UUID? = nil,
        worktreeBranch: String? = nil,
        diffComparisonSelection: DiffComparisonSelection? = nil,
        worktreeBaseBranch: String? = nil
    ) {
        self.id = id
        self.path = path
        self.displayName = displayName
        self.worktreeSourceRepoID = worktreeSourceRepoID
        self.worktreeBranch = worktreeBranch
        self.diffComparisonSelection = diffComparisonSelection
        self.worktreeBaseBranch = worktreeBaseBranch
    }

    var url: URL {
        URL(fileURLWithPath: path)
    }

    var name: String {
        displayName ?? url.lastPathComponent
    }
}
