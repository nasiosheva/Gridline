import SwiftUI

struct RepositoryManagerView: View {
    let repos: [Repo]
    let onRemoveRepositories: ([Repo]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var pendingRemoval: PendingRemoval?

    private var unavailableRepos: [Repo] {
        repos.filter { !$0.existsOnDisk }
    }

    private var filteredRepos: [Repo] {
        guard !searchText.isEmpty else { return repos }
        return repos.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.path.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var removalTitle: String {
        guard let pendingRemoval else { return "" }
        if pendingRemoval.isBulk {
            return L10n.format(
                L10n.Workspace.clearUnavailableRepositoriesTitle,
                Int64(pendingRemoval.repos.count)
            )
        }
        return String(localized: L10n.Workspace.removeSavedRepositoryTitle)
    }

    private var removalMessage: String {
        guard let pendingRemoval else { return "" }
        if pendingRemoval.isBulk {
            return String(localized: L10n.Workspace.clearUnavailableRepositoriesMessage)
        }
        return L10n.format(
            L10n.Workspace.removeSavedRepositoryMessage,
            pendingRemoval.repos.first?.name ?? ""
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(L10n.Workspace.repositoryManagerTitle)
                    .font(.headline)
                Spacer()
                Button(L10n.Common.done) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(L10n.Workspace.searchSavedRepositories, text: $searchText)
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
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            if !unavailableRepos.isEmpty {
                Button {
                    pendingRemoval = PendingRemoval(repos: unavailableRepos, isBulk: true)
                } label: {
                    Label(
                        L10n.format(L10n.Workspace.clearUnavailableRepositories, Int64(unavailableRepos.count)),
                        systemImage: "trash"
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if filteredRepos.isEmpty {
                ContentUnavailableView(
                    String(localized: L10n.Workspace.noSavedRepositories),
                    systemImage: "folder"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredRepos) { repo in
                    HStack(spacing: 10) {
                        Image(systemName: repo.existsOnDisk ? "folder" : "folder.badge.questionmark")
                            .foregroundStyle(repo.existsOnDisk ? Color.secondary : Color.orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(repo.name)
                                .lineLimit(1)
                            Text(repo.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if !repo.existsOnDisk {
                                Text(L10n.Workspace.unavailableRepository)
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Spacer(minLength: 4)
                        Button(role: .destructive) {
                            pendingRemoval = PendingRemoval(repos: [repo], isBulk: false)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help(L10n.Workspace.removeFromGridline)
                        .accessibilityLabel(L10n.format(L10n.Workspace.removeSavedRepositoryMessage, repo.name))
                    }
                    .padding(.vertical, 3)
                }
                .listStyle(.inset)
            }

        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 420)
        .confirmationDialog(
            removalTitle,
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.Workspace.removeFromGridline, role: .destructive) {
                guard let pendingRemoval else { return }
                self.pendingRemoval = nil
                onRemoveRepositories(pendingRemoval.repos)
            }
            Button(L10n.Common.cancel, role: .cancel) {}
        } message: {
            Text(removalMessage)
        }
    }
}

private struct PendingRemoval {
    let repos: [Repo]
    let isBulk: Bool
}
