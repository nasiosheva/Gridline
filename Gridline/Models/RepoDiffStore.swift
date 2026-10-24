//
//  RepoDiffStore.swift
//  Gridline
//
//  Sesi runtime panel diff satu repo: daftar file berubah, file yang dipilih,
//  dan isi diffnya. Hidup lepas dari pane (sama seperti RepoSession untuk
//  terminal) supaya status tidak hilang saat berpindah pane/repo aktif, dan
//  diperbarui otomatis lewat FSEvents + debounce.
//

import Combine
import Foundation

@MainActor
final class RepoDiffStore: ObservableObject {
    let repoPath: String

    @Published private(set) var staged: [DiffFileEntry] = []
    @Published private(set) var unstaged: [DiffFileEntry] = []
    @Published private(set) var untracked: [DiffFileEntry] = []
    @Published var selectedFileID: DiffFileEntry.ID?
    @Published private(set) var selectedDiff: FileDiff?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isGitAvailable = GitProcess.isGitAvailable
    @Published var isFocusMode = false
    @Published private(set) var availableComparisonBranches: [String] = []
    @Published private(set) var comparisonEntries: [DiffFileEntry] = []
    @Published private(set) var comparisonBranch: String?

    private var watcher: RepoFileWatcher?
    private var diffLoadToken = UUID()

    var allEntries: [DiffFileEntry] {
        staged + unstaged + untracked
    }

    var displayedEntries: [DiffFileEntry] {
        comparisonBranch == nil ? allEntries : comparisonEntries
    }

    var totalChangedFileCount: Int {
        Set(allEntries.map(\.path)).count
    }

    init(repoPath: String) {
        self.repoPath = repoPath
        guard isGitAvailable else { return }
        watcher = RepoFileWatcher(path: repoPath) { [weak self] in
            Task { await self?.refresh() }
        }
        Task { await refresh() }
    }

    func refresh() async {
        guard isGitAvailable else { return }
        isRefreshing = true
        let entries = await GitDiffService.statusEntries(at: repoPath)
        let branches = await GitDiffService.comparisonBranches(at: repoPath)
        staged = entries.filter { $0.group == .staged }
        unstaged = entries.filter { $0.group == .unstaged }
        untracked = entries.filter { $0.group == .untracked }
        availableComparisonBranches = branches
        if let comparisonBranch, !branches.contains(comparisonBranch) {
            self.comparisonBranch = nil
            comparisonEntries = []
        } else if let comparisonBranch {
            comparisonEntries = await GitDiffService.comparisonEntries(at: repoPath, against: comparisonBranch)
        }
        isRefreshing = false

        if let selectedFileID, displayedEntries.contains(where: { $0.id == selectedFileID }) {
            await loadDiffForSelection()
        } else {
            selectedFileID = displayedEntries.first?.id
            await loadDiffForSelection()
        }
    }

    func selectComparisonBranch(_ branch: String?) {
        guard comparisonBranch != branch else { return }
        diffLoadToken = UUID()
        comparisonBranch = branch
        selectedFileID = nil
        selectedDiff = nil
        guard let branch else {
            comparisonEntries = []
            selectedFileID = allEntries.first?.id
            Task { await loadDiffForSelection() }
            return
        }
        Task { await loadComparisonEntries(against: branch) }
    }

    private func loadComparisonEntries(against branch: String) async {
        let entries = await GitDiffService.comparisonEntries(at: repoPath, against: branch)
        guard comparisonBranch == branch else { return }
        comparisonEntries = entries
        selectedFileID = entries.first?.id
        await loadDiffForSelection()
    }

    func select(_ entry: DiffFileEntry) {
        guard selectedFileID != entry.id else { return }
        selectedFileID = entry.id
        Task { await loadDiffForSelection() }
    }

    /// Pilih file sebelumnya/berikutnya dalam urutan staged → unstaged → untracked (↑/↓ bagian 6).
    func selectAdjacent(offset: Int) {
        let ordered = displayedEntries
        guard !ordered.isEmpty else { return }
        guard let currentIndex = ordered.firstIndex(where: { $0.id == selectedFileID }) else {
            select(ordered[0])
            return
        }
        let newIndex = max(0, min(ordered.count - 1, currentIndex + offset))
        select(ordered[newIndex])
    }

    private func loadDiffForSelection() async {
        guard let selectedFileID, let entry = displayedEntries.first(where: { $0.id == selectedFileID }) else {
            selectedDiff = nil
            return
        }
        let token = UUID()
        diffLoadToken = token
        let diff: FileDiff
        if let comparisonBranch {
            diff = await GitDiffService.fileDiff(at: repoPath, against: comparisonBranch, for: entry)
        } else {
            diff = await GitDiffService.fileDiff(at: repoPath, for: entry)
        }
        guard diffLoadToken == token else { return }
        selectedDiff = diff
    }
}
