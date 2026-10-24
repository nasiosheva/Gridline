import SwiftUI

struct WorktreeBranchPickerView: View {
    let repo: Repo
    var replacingPaneID: UUID? = nil

    @EnvironmentObject private var appState: AppStateStore
    @Environment(\.dismiss) private var dismiss
    @State private var branches: [String] = []
    @State private var currentBranch: String?
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var openingBranch: String?
    @State private var errorMessage: String?

    private var availableBranches: [String] {
        branches.filter { $0 != currentBranch }
    }

    private var filteredBranches: [String] {
        guard !searchText.isEmpty else { return availableBranches }
        return availableBranches.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(replacingPaneID == nil ? L10n.Worktree.title : L10n.Worktree.chooseBranchAgain)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isLoading {
                ProgressView(L10n.Worktree.loadingBranches)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if availableBranches.isEmpty {
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
                        TextField(L10n.Common.searchBranches, text: $searchText)
                            .textFieldStyle(.plain)
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .help(L10n.Common.clearSearch)
                            .accessibilityLabel(L10n.Common.clearSearch)
                        }
                    }
                    if filteredBranches.isEmpty {
                        ContentUnavailableView(
                            String(localized: L10n.Common.noMatchingBranches),
                            systemImage: "magnifyingglass"
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(filteredBranches, id: \.self) { branch in
                            Button {
                                open(branch)
                            } label: {
                                HStack {
                                    Label(branch, systemImage: "arrow.triangle.branch")
                                    Spacer()
                                    if openingBranch == branch {
                                        ProgressView()
                                            .controlSize(.small)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(openingBranch != nil)
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
        .task {
            await loadBranches()
        }
        .onAppear {
            searchText = ""
        }
        .alert(String(localized: L10n.Worktree.alertTitle), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(L10n.Common.ok, role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func loadBranches() async {
        guard let choices = await GitWorktreeService.branchChoices(at: repo.path) else {
            isLoading = false
            errorMessage = String(localized: L10n.Worktree.loadFailed)
            return
        }
        branches = choices.branches
        currentBranch = choices.currentBranch
        isLoading = false
    }

    private func open(_ branch: String) {
        Task { @MainActor in
            openingBranch = branch
            defer { openingBranch = nil }
            do {
                let destination = try await GitWorktreeService.openOrCreateWorktree(
                    branch: branch,
                    from: repo,
                    canCreatePane: replacingPaneID != nil || appState.canAddRepositoryToPane
                )
                guard appState.openRepoInNewPane(
                    path: destination.path,
                    displayName: destination.displayName,
                    sourceRepoID: destination.sourceRepoID,
                    branch: destination.branch,
                    baseBranch: currentBranch,
                    replacingPaneID: replacingPaneID
                ) else {
                    errorMessage = String(localized: L10n.Worktree.paneLimitReached)
                    return
                }
                dismiss()
            } catch let error as GitWorktreeError {
                errorMessage = message(for: error)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func message(for error: GitWorktreeError) -> String {
        switch error {
        case .commandFailed(let detail):
            let detail = detail.isEmpty ? String(localized: L10n.Worktree.loadFailed) : detail
            return L10n.format(L10n.Worktree.operationFailed, detail)
        case .pathAlreadyExists:
            return String(localized: L10n.Worktree.pathAlreadyExists)
        case .paneLimitReached:
            return String(localized: L10n.Worktree.paneLimitReached)
        }
    }
}
