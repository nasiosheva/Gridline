//
//  RepoPaneHeaderView.swift
//  Gridline
//
//  Header pane: identitas/status repo dan menu tindakan pane.
//

import SwiftUI

struct RepoPaneHeaderView: View {
    let repo: Repo
    let status: RepoHeaderStatus?
    let attention: RepoAttentionStatus?
    let workStatus: RepoWorkStatus
    let isMaximized: Bool
    let isTerminalOnly: Bool
    var onClose: () -> Void
    var canClosePane: Bool
    var onClosePane: () -> Void
    var onToggleMaximize: () -> Void
    var onToggleTerminalOnly: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(RepoIdentityColor.color(for: repo))
                .frame(width: 8, height: 8)
                .accessibilityLabel(L10n.format(L10n.Repository.identityColor, repo.name))

            Text(repo.name)
                .font(.headline)
                .lineLimit(1)

            Label(workStatus.title, systemImage: workStatus.systemImage)
                .font(.caption)
                .foregroundStyle(workStatus == .needsAttention ? .red : .secondary)
                .help(L10n.Repository.workStatusHelp)

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

            PaneActionsMenu(canClosePane: canClosePane, onClosePane: onClosePane) {
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

                Divider()

                Button(role: .destructive, action: onClose) {
                    Label(L10n.Repository.closeAction, systemImage: "xmark")
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(.bar)
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
    let canClosePane: Bool
    let onClosePane: () -> Void
    let separatesClosePaneAction: Bool
    let actions: Actions

    init(
        canClosePane: Bool,
        onClosePane: @escaping () -> Void,
        separatesClosePaneAction: Bool = true,
        @ViewBuilder actions: () -> Actions
    ) {
        self.canClosePane = canClosePane
        self.onClosePane = onClosePane
        self.separatesClosePaneAction = separatesClosePaneAction
        self.actions = actions()
    }

    var body: some View {
        Menu {
            actions
            if separatesClosePaneAction {
                Divider()
            }
            Button(L10n.Pane.close, systemImage: "xmark.rectangle", action: onClosePane)
                .disabled(!canClosePane)
        } label: {
            Image(systemName: "ellipsis")
        }
        .buttonStyle(.plain)
        .help(L10n.Pane.actions)
        .accessibilityLabel(L10n.Pane.actions)
    }
}
