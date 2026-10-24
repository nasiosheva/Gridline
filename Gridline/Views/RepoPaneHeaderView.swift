//
//  RepoPaneHeaderView.swift
//  Gridline
//
//  Header pane: identitas/status repo dan menu tindakan pane.
//

import SwiftUI

struct RepoPaneHeaderView: View {
    let repo: Repo
    let availableRepos: [Repo]
    @ObservedObject var diffStore: RepoDiffStore
    let attention: RepoAttentionStatus?
    let workStatus: RepoWorkStatus
    let isMaximized: Bool
    let isTerminalOnly: Bool
    var onSelectRepo: (UUID) -> Void
    var onManageRepositories: () -> Void
    var onClose: () -> Void
    var canClosePane: Bool
    var onClosePane: () -> Void
    var onToggleMaximize: () -> Void
    var onToggleTerminalOnly: () -> Void
    @State private var showsWorktreePicker = false

    var body: some View {
        let status = diffStore.headerStatus
        HStack(spacing: 8) {
            Circle()
                .fill(RepoIdentityColor.color(for: repo))
                .frame(width: 8, height: 8)
                .accessibilityLabel(L10n.format(L10n.Repository.identityColor, repo.name))

            Menu {
                ForEach(availableRepos) { candidate in
                    Button {
                        onSelectRepo(candidate.id)
                    } label: {
                        Label(
                            candidate.name,
                            systemImage: candidate.id == repo.id ? "checkmark" : "folder"
                        )
                    }
                }
                Divider()
                Button(L10n.Menu.manageRepositories, action: onManageRepositories)
            } label: {
                HStack(spacing: 4) {
                    Text(repo.name)
                        .font(.headline)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .help(L10n.Pane.selectRepository)
            .accessibilityLabel(L10n.Pane.selectRepository)

            Label(workStatus.title, systemImage: workStatus.systemImage)
                .font(.caption)
                .foregroundStyle(workStatus == .needsAttention ? .red : .secondary)
                .help(L10n.Repository.workStatusHelp)

            if !diffStore.hasLoadedInitialStatus || diffStore.isRefreshing {
                HStack(spacing: 5) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.Worktree.openingBranch)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }

            if let status {
                branchLabel(status)
                if status.changedFileCount > 0 {
                    Text("\(status.changedFileCount)")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.2), in: Capsule())
                }
            }

            if let attention {
                Label(attention.accessibilityLabel, systemImage: attention == .completed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(attention == .completed ? .yellow : .red)
                    .font(.caption)
                    .accessibilityLabel(attention.accessibilityLabel)
            }

            Spacer()

            PaneActionsMenu {
                Button(action: onToggleMaximize) {
                    Label(
                        isMaximized ? L10n.Pane.restoreGrid : L10n.Pane.maximize,
                        systemImage: isMaximized ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
                    )
                }

                Button(action: onToggleTerminalOnly) {
                    Label(
                        isTerminalOnly ? L10n.Pane.showTopArea : L10n.Pane.terminalOnly,
                        systemImage: isTerminalOnly ? "rectangle.bottomhalf.inset.filled" : "rectangle.bottomhalf.inset"
                    )
                }

                Button {
                    showsWorktreePicker = true
                } label: {
                    Label(L10n.Worktree.openBranchInNewPane, systemImage: "arrow.triangle.branch")
                }

                Divider()

                Button(role: .destructive, action: onClose) {
                    Label(L10n.Repository.closeAction, systemImage: "xmark")
                }
            }
            PaneCloseButton(canClosePane: canClosePane, action: onClosePane)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(.bar)
        .sheet(isPresented: $showsWorktreePicker) {
            WorktreeBranchPickerView(repo: repo)
        }
    }

    @ViewBuilder
    private func branchLabel(_ status: RepoHeaderStatus) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.branch")
            if status.isDetached {
                Text(L10n.Repository.detachedHead)
            } else {
                Text(status.branch ?? "—")
            }
            if status.ahead > 0 {
                Label(L10n.format(L10n.Repository.ahead, Int64(status.ahead)), systemImage: "arrow.up")
            }
            if status.behind > 0 {
                Label(L10n.format(L10n.Repository.behind, Int64(status.behind)), systemImage: "arrow.down")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
    }
}

struct PaneActionsMenu<Actions: View>: View {
    let actions: Actions

    init(@ViewBuilder actions: () -> Actions) {
        self.actions = actions()
    }

    var body: some View {
        Menu {
            actions
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n.Pane.actions)
        .accessibilityLabel(L10n.Pane.actions)
    }
}

struct PaneCloseButton: View {
    let canClosePane: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .background(
                    isHovering ? Color.secondary.opacity(0.18) : .clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
        }
        .buttonStyle(.plain)
        .disabled(!canClosePane)
        .opacity(canClosePane ? 1 : 0.45)
        .onHover { isHovering = $0 }
        .help(L10n.Pane.close)
        .accessibilityLabel(L10n.Pane.close)
    }
}
