import Combine
import SwiftUI

struct WorktreeBranchPickerView: View {
    let repo: Repo
    let replacingPaneID: UUID?

    @EnvironmentObject private var appState: AppStateStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: WorktreeBranchPickerModel

    init(repo: Repo, replacingPaneID: UUID? = nil) {
        self.init(repo: repo, replacingPaneID: replacingPaneID, model: WorktreeBranchPickerModel())
    }

    init(repo: Repo, replacingPaneID: UUID?, model: WorktreeBranchPickerModel) {
        self.repo = repo
        self.replacingPaneID = replacingPaneID
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(replacingPaneID == nil ? L10n.Worktree.title : L10n.Worktree.chooseBranchAgain)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            if model.isLoading {
                ProgressView(L10n.Worktree.loadingBranches)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.availableBranches.isEmpty {
                ContentUnavailableView(
                    String(localized: L10n.Worktree.noOtherBranches),
                    systemImage: "arrow.triangle.branch"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField(L10n.Common.searchBranches, text: $model.searchText)
                            .textFieldStyle(.plain)
                        if !model.searchText.isEmpty {
                            Button {
                                model.searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .help(L10n.Common.clearSearch)
                            .accessibilityLabel(L10n.Common.clearSearch)
                        }
                    }
                    if model.filteredBranches(searchText: model.searchText).isEmpty {
                        ContentUnavailableView(
                            String(localized: L10n.Common.noMatchingBranches),
                            systemImage: "magnifyingglass"
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(model.filteredBranches(searchText: model.searchText), id: \.self) { branch in
                            Button {
                                Task {
                                    if await model.open(
                                        branch: branch,
                                        from: repo,
                                        appState: appState,
                                        replacingPaneID: replacingPaneID
                                    ) {
                                        dismiss()
                                    }
                                }
                            } label: {
                                HStack {
                                    Label(branch, systemImage: "arrow.triangle.branch")
                                    Spacer()
                                    if model.openingBranch == branch {
                                        ProgressView()
                                            .controlSize(.small)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(model.openingBranch != nil)
                        }
                        .listStyle(.inset)
                    }
                }
            }

            HStack {
                Spacer()
                Button(L10n.Common.cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 420, height: 380)
        .task { await model.loadBranches(at: repo.path) }
        .onAppear {
            model.searchText = ""
        }
        .alert(String(localized: L10n.Worktree.alertTitle), isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.clearError() } }
        )) {
            Button(L10n.Common.ok, role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

@MainActor
final class WorktreeBranchPickerModel: ObservableObject {
    @Published private(set) var branches: [String] = []
    @Published private(set) var currentBranch: String?
    @Published private(set) var isLoading = true
    @Published private(set) var openingBranch: String?
    @Published private(set) var errorMessage: String?
    @Published var searchText = ""

    var availableBranches: [String] {
        branches.filter { $0 != currentBranch }
    }

    func filteredBranches(searchText: String) -> [String] {
        guard !searchText.isEmpty else { return availableBranches }
        return availableBranches.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    func loadBranches(at repoPath: String) async {
        guard let choices = await GitWorktreeService.branchChoices(at: repoPath) else {
            isLoading = false
            errorMessage = String(localized: L10n.Worktree.loadFailed)
            return
        }
        branches = choices.branches
        currentBranch = choices.currentBranch
        isLoading = false
    }

    func open(
        branch: String,
        from repo: Repo,
        appState: AppStateStore,
        replacingPaneID: UUID? = nil
    ) async -> Bool {
        openingBranch = branch
        defer { openingBranch = nil }
        do {
            let destination = try await GitWorktreeService.openOrCreateWorktree(
                branch: branch,
                from: repo
            )
            guard appState.openRepoInNewPane(
                path: destination.path,
                displayName: destination.displayName,
                sourceRepoID: destination.sourceRepoID,
                branch: destination.branch,
                baseBranch: currentBranch,
                replacingPaneID: replacingPaneID
            ) else {
                errorMessage = String(localized: L10n.Worktree.paneUnavailable)
                return false
            }
            return true
        } catch let error as GitWorktreeError {
            errorMessage = Self.message(for: error)
        } catch {
            errorMessage = error.localizedDescription
        }
        return false
    }

    func clearError() {
        errorMessage = nil
    }

    static func message(for error: GitWorktreeError) -> String {
        switch error {
        case .commandFailed(let detail):
            let detail = detail.isEmpty ? String(localized: L10n.Worktree.loadFailed) : detail
            return L10n.format(L10n.Worktree.operationFailed, detail)
        case .pathAlreadyExists:
            return String(localized: L10n.Worktree.pathAlreadyExists)
        }
    }
}
