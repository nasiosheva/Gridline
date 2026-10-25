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
    private enum Configuration {
        static let comparisonBranchCacheDuration: TimeInterval = 15
    }

    let repoPath: String

    @Published private(set) var staged: [DiffFileEntry] = []
    @Published private(set) var unstaged: [DiffFileEntry] = []
    @Published private(set) var untracked: [DiffFileEntry] = []
    @Published private(set) var headerStatus: RepoHeaderStatus?
    @Published var selectedFileID: DiffFileEntry.ID?
    @Published private(set) var selectedDiff: FileDiff?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isGitAvailable = GitProcess.isGitAvailable
    @Published var isFocusMode = false
    @Published private(set) var availableComparisonBranches: [String] = []
    @Published private(set) var comparisonEntries: [DiffFileEntry] = []
    @Published private(set) var comparisonBranch: String?
    @Published private(set) var comparisonBaseBranch: String?
    @Published private(set) var comparisonTargetBranch: String?
    @Published private(set) var hasLoadedInitialStatus = false

    private var watcher: RepoFileWatcher?
    private var headWatcher: GitHEADWatcher?
    private var diffLoadToken = UUID()
    private var comparisonBranchesLoadedAt: Date?
    private var refreshRequestedAgain = false
    /// Branch yang harus langsung dipakai sebagai perbandingan begitu daftar branch
    /// pertama kali termuat (lihat `Repo.worktreeBaseBranch`) — supaya pane worktree
    /// baru langsung menunjukkan diff branch tersebut, bukan "Local Changes" yang
    /// kosong. Dikonsumsi sekali saja, tidak menimpa pilihan manual pengguna setelahnya.
    private var initialComparisonBranch: String?
    private let hadSavedComparisonSelection: Bool
    /// Dipanggil tepat sekali setelah `initialComparisonBranch` dikonsumsi (berhasil
    /// diterapkan atau tidak) — pemanggil (lihat `RepoDiffStoreRegistry`) memakai ini
    /// untuk menghapus `Repo.worktreeBaseBranch` dari state tersimpan, supaya default
    /// ini cuma berlaku sekali saat pane worktree baru dibuat, bukan setiap kali app
    /// dibuka ulang (yang sebelumnya menimpa pilihan perbandingan manual pengguna).
    var onInitialComparisonBranchConsumed: (() -> Void)?
    var onComparisonSelectionChanged: ((DiffComparisonSelection) -> Void)?

    var allEntries: [DiffFileEntry] {
        staged + unstaged + untracked
    }

    var displayedEntries: [DiffFileEntry] {
        isComparingBranches || comparisonBranch != nil ? comparisonEntries : allEntries
    }

    var isComparingBranches: Bool {
        comparisonBaseBranch != nil && comparisonTargetBranch != nil
    }

    var totalChangedFileCount: Int {
        Set(allEntries.map(\.path)).count
    }

    init(
        repoPath: String,
        initialComparisonBranch: String? = nil,
        savedComparisonSelection: DiffComparisonSelection? = nil
    ) {
        self.repoPath = repoPath
        self.initialComparisonBranch = initialComparisonBranch
        self.hadSavedComparisonSelection = savedComparisonSelection != nil
        switch savedComparisonSelection {
        case .localChanges:
            break
        case .againstBranch(let branch):
            comparisonBranch = branch
        case .betweenBranches(let base, let target):
            comparisonBaseBranch = base
            comparisonTargetBranch = target
        case nil:
            break
        }
        guard isGitAvailable else {
            hasLoadedInitialStatus = true
            return
        }
    }

    func setWatching(_ shouldWatch: Bool) {
        guard isGitAvailable else { return }
        if shouldWatch {
            guard watcher == nil else { return }
            watcher = RepoFileWatcher(path: repoPath) { [weak self] in
                Task { await self?.refresh() }
            }
            headWatcher = GitHEADWatcher(repoPath: repoPath) { [weak self] in
                self?.refreshGitMetadata()
            }
            Task { await refresh() }
        } else {
            watcher?.stop()
            watcher = nil
            headWatcher?.stop()
            headWatcher = nil
        }
    }

    func refresh() async {
        guard isGitAvailable else { return }

        guard !isRefreshing else {
            refreshRequestedAgain = true
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        repeat {
            refreshRequestedAgain = false
            let shouldLoadBranches = shouldRefreshComparisonBranches
            let cachedBranches = availableComparisonBranches
            async let refreshedStatus = GitDiffService.statusSnapshot(at: repoPath)
            async let refreshedBranches = shouldLoadBranches
                ? GitDiffService.comparisonBranches(at: repoPath)
                : cachedBranches
            let (snapshot, branches) = await (refreshedStatus, refreshedBranches)
            staged = snapshot.entries.filter { $0.group == .staged }
            unstaged = snapshot.entries.filter { $0.group == .unstaged }
            untracked = snapshot.entries.filter { $0.group == .untracked }
            headerStatus = snapshot.headerStatus
            hasLoadedInitialStatus = true

            if shouldLoadBranches {
                availableComparisonBranches = branches
                comparisonBranchesLoadedAt = .now
            }

            if let pendingInitialBranch = initialComparisonBranch,
               !availableComparisonBranches.isEmpty {
                initialComparisonBranch = nil
                if !hadSavedComparisonSelection,
                   comparisonBranch == nil, comparisonBaseBranch == nil,
                   availableComparisonBranches.contains(pendingInitialBranch) {
                    comparisonBranch = pendingInitialBranch
                    onComparisonSelectionChanged?(.againstBranch(pendingInitialBranch))
                }
                onInitialComparisonBranchConsumed?()
            }

            if let comparisonBaseBranch, let comparisonTargetBranch {
                if availableComparisonBranches.contains(comparisonBaseBranch),
                   availableComparisonBranches.contains(comparisonTargetBranch) {
                    let entries = await GitDiffService.comparisonEntries(
                        at: repoPath,
                        from: comparisonBaseBranch,
                        to: comparisonTargetBranch
                    )
                    if self.comparisonBaseBranch == comparisonBaseBranch,
                       self.comparisonTargetBranch == comparisonTargetBranch {
                        comparisonEntries = entries
                    }
                } else if !availableComparisonBranches.isEmpty {
                    self.comparisonBaseBranch = nil
                    self.comparisonTargetBranch = nil
                    comparisonEntries = []
                    onComparisonSelectionChanged?(.localChanges)
                }
            } else if let comparisonBranch,
                      !availableComparisonBranches.isEmpty,
                      !availableComparisonBranches.contains(comparisonBranch) {
                self.comparisonBranch = nil
                comparisonEntries = []
                onComparisonSelectionChanged?(.localChanges)
            } else if let comparisonBranch {
                let entries = await GitDiffService.comparisonEntries(at: repoPath, against: comparisonBranch)
                if self.comparisonBranch == comparisonBranch, !isComparingBranches {
                    comparisonEntries = entries
                }
            }

            if let selectedFileID, displayedEntries.contains(where: { $0.id == selectedFileID }) {
                await loadDiffForSelection()
            } else {
                selectedFileID = displayedEntries.first?.id
                await loadDiffForSelection()
            }
        } while refreshRequestedAgain
    }

    private var shouldRefreshComparisonBranches: Bool {
        guard let comparisonBranchesLoadedAt else { return true }
        return Date.now.timeIntervalSince(comparisonBranchesLoadedAt) >= Configuration.comparisonBranchCacheDuration
    }

    /// Perubahan branch bisa hanya menyentuh `.git/`, yang dikecualikan dari
    /// FSEvents. Muat ulang status dan daftar branch saat picker atau jendela
    /// dibuka kembali, melewati cache branch 15 detik.
    func refreshGitMetadata() {
        comparisonBranchesLoadedAt = nil
        Task { await refresh() }
    }

    func selectComparisonBranch(_ branch: String?) {
        if initialComparisonBranch != nil {
            initialComparisonBranch = nil
            onInitialComparisonBranchConsumed?()
        }
        guard comparisonBranch != branch || comparisonBaseBranch != nil || comparisonTargetBranch != nil else {
            if branch == nil { onComparisonSelectionChanged?(.localChanges) }
            return
        }
        diffLoadToken = UUID()
        comparisonBranch = branch
        comparisonBaseBranch = nil
        comparisonTargetBranch = nil
        onComparisonSelectionChanged?(branch.map(DiffComparisonSelection.againstBranch) ?? .localChanges)
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

    func selectComparisonBranches(from baseBranch: String, to targetBranch: String) {
        guard baseBranch != targetBranch,
              availableComparisonBranches.contains(baseBranch),
              availableComparisonBranches.contains(targetBranch) else { return }
        if initialComparisonBranch != nil {
            initialComparisonBranch = nil
            onInitialComparisonBranchConsumed?()
        }
        diffLoadToken = UUID()
        comparisonBranch = nil
        comparisonBaseBranch = baseBranch
        comparisonTargetBranch = targetBranch
        onComparisonSelectionChanged?(.betweenBranches(base: baseBranch, target: targetBranch))
        selectedFileID = nil
        selectedDiff = nil
        comparisonEntries = []
        Task { await loadComparisonEntries(from: baseBranch, to: targetBranch) }
    }

    private func loadComparisonEntries(against branch: String) async {
        let entries = await GitDiffService.comparisonEntries(at: repoPath, against: branch)
        guard comparisonBranch == branch, !isComparingBranches else { return }
        comparisonEntries = entries
        selectedFileID = entries.first?.id
        await loadDiffForSelection()
    }

    private func loadComparisonEntries(from baseBranch: String, to targetBranch: String) async {
        let entries = await GitDiffService.comparisonEntries(at: repoPath, from: baseBranch, to: targetBranch)
        guard comparisonBaseBranch == baseBranch, comparisonTargetBranch == targetBranch else { return }
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
    func selectAdjacent(offset: Int, within entries: [DiffFileEntry]? = nil) {
        let ordered = entries ?? displayedEntries
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
        guard selectedDiff?.entry != entry else { return }
        let token = UUID()
        diffLoadToken = token
        let diff: FileDiff
        if let comparisonBaseBranch, let comparisonTargetBranch {
            diff = await GitDiffService.fileDiff(
                at: repoPath,
                from: comparisonBaseBranch,
                to: comparisonTargetBranch,
                for: entry
            )
        } else if let comparisonBranch {
            diff = await GitDiffService.fileDiff(at: repoPath, against: comparisonBranch, for: entry)
        } else {
            diff = await GitDiffService.fileDiff(at: repoPath, for: entry)
        }
        guard diffLoadToken == token else { return }
        selectedDiff = diff
    }
}
