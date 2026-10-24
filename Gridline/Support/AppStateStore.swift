//
//  AppStateStore.swift
//  Gridline
//
//  Persistensi state aplikasi sebagai JSON di
//  ~/Library/Application Support/Gridline/state.json, ditulis atomik
//  (tulis ke file sementara lalu ganti) sesuai bagian 12 apps-spec.md.
//

import Combine
import Foundation

struct AppState: Codable {
    static let recentRepositoryLimit = 3

    var formatVersion: Int = 3
    var savedRepos: [Repo] = []
    var recentRepoIDs: [UUID] = []
    var paneLayout = PaneLayout()

    init() {}

    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case savedRepos
        case recentRepoIDs
        case paneLayout
        // Kunci M1 untuk migrasi state yang sudah tersimpan.
        case activeRepoID
        case paneSplitTopFraction
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        savedRepos = try container.decodeIfPresent([Repo].self, forKey: .savedRepos) ?? []
        let decodedRecentRepoIDs = try container.decodeIfPresent([UUID].self, forKey: .recentRepoIDs)
            ?? Array(savedRepos.suffix(AppState.recentRepositoryLimit).map(\.id))
        var seenRecentRepoIDs = Set<UUID>()
        recentRepoIDs = decodedRecentRepoIDs.filter { id in
            savedRepos.contains(where: { $0.id == id }) && seenRecentRepoIDs.insert(id).inserted
        }
        if let decodedLayout = try container.decodeIfPresent(PaneLayout.self, forKey: .paneLayout) {
            paneLayout = decodedLayout
        } else {
            let activeRepoID = try container.decodeIfPresent(UUID.self, forKey: .activeRepoID)
            let topFraction = try container.decodeIfPresent(Double.self, forKey: .paneSplitTopFraction) ?? 0.6
            paneLayout = .migrated(activeRepoID: activeRepoID, topFraction: topFraction)
        }
        formatVersion = 3
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(savedRepos, forKey: .savedRepos)
        try container.encode(recentRepoIDs, forKey: .recentRepoIDs)
        try container.encode(paneLayout, forKey: .paneLayout)
    }
}

@MainActor
final class AppStateStore: ObservableObject {
    @Published private(set) var state: AppState

    private let fileURL: URL
    private var deferredPersistTask: Task<Void, Never>?

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.state = Self.load(from: self.fileURL) ?? AppState()
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Gridline", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }

    private static func load(from url: URL) -> AppState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AppState.self, from: data)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        let dir = fileURL.deletingLastPathComponent()
        let tempURL = dir.appendingPathComponent(".\(fileURL.lastPathComponent).tmp-\(UUID().uuidString)")
        do {
            try data.write(to: tempURL, options: .atomic)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL)
            } else {
                try FileManager.default.moveItem(at: tempURL, to: fileURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
        }
    }

    private func persistAfterDividerSettles() {
        deferredPersistTask?.cancel()
        deferredPersistTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.persist()
        }
    }

    // MARK: - Daftar repo tersimpan

    var recentRepositories: [Repo] {
        state.recentRepoIDs.reversed().compactMap { id in
            state.savedRepos.first(where: { $0.id == id })
        }
    }

    var canAddRepositoryToPane: Bool {
        state.paneLayout.slots.count < PaneLayout.maximumPaneCount
            || state.paneLayout.slots.contains(where: { $0.repoID == nil })
    }

    func clearRecentRepositories() {
        guard !state.recentRepoIDs.isEmpty else { return }
        state.recentRepoIDs.removeAll()
        persist()
    }

    private func markRepoRecent(_ id: UUID) {
        state.recentRepoIDs.removeAll { $0 == id }
        state.recentRepoIDs.append(id)
        if state.recentRepoIDs.count > AppState.recentRepositoryLimit {
            state.recentRepoIDs.removeFirst(state.recentRepoIDs.count - AppState.recentRepositoryLimit)
        }
    }

    func addRepo(path: String) -> Repo {
        let repo: Repo
        if let existing = state.savedRepos.first(where: { $0.path == path }) {
            repo = existing
        } else {
            repo = Repo(path: path)
            state.savedRepos.append(repo)
        }
        markRepoRecent(repo.id)
        state.paneLayout.assign(repoID: repo.id)
        persist()
        return repo
    }

    @discardableResult
    func openRepoInNewPane(
        path: String,
        displayName: String,
        sourceRepoID: UUID? = nil,
        branch: String? = nil,
        replacingPaneID: UUID? = nil
    ) -> Bool {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        guard replacingPaneID == nil || state.paneLayout.slots.contains(where: { $0.id == replacingPaneID }) else {
            return false
        }
        if let existingIndex = state.savedRepos.firstIndex(where: {
            URL(fileURLWithPath: $0.path).standardizedFileURL.path == normalizedPath
        }) {
            let repoID = state.savedRepos[existingIndex].id
            let existingPane = state.paneLayout.slots.first(where: { $0.repoID == repoID })
            guard existingPane != nil || replacingPaneID != nil || canAddRepositoryToPane else { return false }
            state.savedRepos[existingIndex].displayName = displayName
            state.savedRepos[existingIndex].worktreeSourceRepoID = sourceRepoID
            state.savedRepos[existingIndex].worktreeBranch = branch
            if let existingPane {
                state.paneLayout.activePaneID = existingPane.id
                markRepoRecent(repoID)
                persist()
                return true
            }
            markRepoRecent(repoID)
            if let replacingPaneID,
               let paneIndex = state.paneLayout.slots.firstIndex(where: { $0.id == replacingPaneID }) {
                state.paneLayout.slots[paneIndex].repoID = repoID
                state.paneLayout.activePaneID = replacingPaneID
            } else {
                state.paneLayout.assign(repoID: repoID)
            }
            persist()
            return true
        }

        guard replacingPaneID != nil || canAddRepositoryToPane else { return false }
        let repo = Repo(
            path: normalizedPath,
            displayName: displayName,
            worktreeSourceRepoID: sourceRepoID,
            worktreeBranch: branch
        )
        state.savedRepos.append(repo)
        markRepoRecent(repo.id)
        if let replacingPaneID,
           let paneIndex = state.paneLayout.slots.firstIndex(where: { $0.id == replacingPaneID }) {
            state.paneLayout.slots[paneIndex].repoID = repo.id
            state.paneLayout.activePaneID = replacingPaneID
        } else {
            state.paneLayout.assign(repoID: repo.id)
        }
        persist()
        return true
    }

    func removeRepo(id: UUID) {
        state.savedRepos.removeAll { $0.id == id }
        state.recentRepoIDs.removeAll { $0 == id }
        state.paneLayout.removeRepoReference(id)
        persist()
    }

    func openRepo(id: UUID, inNewPane: Bool = false) {
        guard state.savedRepos.contains(where: { $0.id == id }) else { return }
        markRepoRecent(id)
        state.paneLayout.assign(repoID: id, preferNewPane: inNewPane)
        persist()
    }

    func openRepo(id: UUID, in paneID: UUID) {
        guard state.savedRepos.contains(where: { $0.id == id }) else { return }
        markRepoRecent(id)
        state.paneLayout.restoreRepo(id, in: paneID)
        persist()
    }

    func clearRepo(in paneID: UUID) {
        state.paneLayout.clearRepo(in: paneID)
        persist()
    }

    func restoreRepo(id: UUID, in paneID: UUID) {
        guard state.savedRepos.contains(where: { $0.id == id }) else { return }
        markRepoRecent(id)
        state.paneLayout.restoreRepo(id, in: paneID)
        persist()
    }

    func addPane() {
        guard state.paneLayout.addPane() != nil else { return }
        persist()
    }

    func removePane(id: UUID) {
        guard state.paneLayout.removePane(id) else { return }
        persist()
    }

    func setLayoutPreset(_ preset: PaneLayoutPreset) {
        state.paneLayout.setPreset(preset)
        persist()
    }

    func focusPane(id: UUID) {
        guard state.paneLayout.slots.contains(where: { $0.id == id }),
              state.paneLayout.activePaneID != id else { return }
        state.paneLayout.activePaneID = id
        persist()
    }

    func focusPane(at index: Int) {
        let previous = state.paneLayout.activePaneID
        state.paneLayout.focusPane(at: index)
        guard state.paneLayout.activePaneID != previous else { return }
        persist()
    }

    func focusPane(_ direction: PaneFocusDirection) {
        let previous = state.paneLayout.activePaneID
        state.paneLayout.focus(direction)
        guard state.paneLayout.activePaneID != previous else { return }
        persist()
    }

    func toggleMaximizedActivePane() {
        toggleMaximizedPane(id: state.paneLayout.activePaneID)
    }

    func toggleMaximizedPane(id: UUID) {
        state.paneLayout.toggleMaximizedPane(id)
        persist()
    }

    func toggleTerminalOnlyActivePane() {
        toggleTerminalOnlyPane(id: state.paneLayout.activePaneID)
    }

    func toggleTerminalOnlyPane(id: UUID) {
        state.paneLayout.toggleTerminalOnlyPane(id)
        persist()
    }

    // MARK: - Posisi pembagi

    func setPaneSplitTopFraction(_ fraction: Double, paneID: UUID) {
        guard let current = state.paneLayout.slots.first(where: { $0.id == paneID })?.topFraction,
              abs(current - fraction) > 0.001 else { return }
        state.paneLayout.setTopFraction(fraction, for: paneID)
        persist()
    }

    func setViewerAsSidePanel(_ isEnabled: Bool, paneID: UUID) {
        guard state.paneLayout.slots.first(where: { $0.id == paneID })?.viewerAsSidePanel != isEnabled else { return }
        state.paneLayout.setViewerAsSidePanel(isEnabled, for: paneID)
        persist()
    }

    func setGridDividerFraction(_ fraction: Double, role: PaneDividerRole) {
        let clamped = min(max(fraction, 0.1), 0.9)
        switch role {
        case .topColumn:
            guard abs(state.paneLayout.topColumnFraction - clamped) > 0.001 else { return }
            state.paneLayout.topColumnFraction = clamped
        case .bottomColumn:
            guard abs(state.paneLayout.bottomColumnFraction - clamped) > 0.001 else { return }
            state.paneLayout.bottomColumnFraction = clamped
        case .row:
            guard abs(state.paneLayout.rowFraction - clamped) > 0.001 else { return }
            state.paneLayout.rowFraction = clamped
        }
        persistAfterDividerSettles()
    }
}
