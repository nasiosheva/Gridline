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
    /// Satu state linear untuk alur pull (confirm → result), bukan beberapa
    /// Bool independen yang bisa merepresentasikan kombinasi tidak valid
    /// (mis. alert hasil tampil dengan `pullSucceeded` sisa dari pull sebelumnya).
    @State private var pullFlow: PullFlow = .idle

    private enum PullFlow: Equatable {
        case idle
        case confirming
        case succeeded
        case failed
        /// `pullFromUpstream()` menolak jalan karena kondisi berubah di antara
        /// dialog konfirmasi dibuka dan pengguna menekan Pull (mis. branch
        /// sudah up to date lagi) — pengguna tetap diberi tahu, bukan dibiarkan
        /// tanpa umpan balik sama sekali.
        case skipped
    }

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
                        .font(.headline.weight(.bold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.primary)
                }
                .foregroundColor(RepoIdentityColor.color(for: repo))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RepoIdentityColor.color(for: repo).opacity(0.18),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .tint(RepoIdentityColor.color(for: repo))
            .help(L10n.Pane.selectRepository)
            .accessibilityLabel(L10n.Pane.selectRepository)

            Label(workStatus.title, systemImage: workStatus.systemImage)
                .font(.caption)
                .foregroundStyle(workStatus == .needsAttention ? .red : .secondary)
                .help(L10n.Repository.workStatusHelp)

            if !diffStore.hasLoadedInitialStatus || (diffStore.isRefreshing && !diffStore.isPulling) {
                StatusSpinnerLabel(text: L10n.Worktree.openingBranch)
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
        .confirmationDialog(
            String(localized: L10n.Repository.pullConfirmationTitle),
            isPresented: Binding(
                get: { pullFlow == .confirming },
                set: { if !$0 { pullFlow = .idle } }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.Repository.pullAction) {
                Task { await performPull() }
            }
            Button(L10n.Common.cancel, role: .cancel) { pullFlow = .idle }
        } message: {
            Text(pullConfirmationMessage)
        }
        .alert(
            Text(pullResultTitle),
            isPresented: Binding(
                get: { pullFlow == .succeeded || pullFlow == .failed || pullFlow == .skipped },
                set: { if !$0 { pullFlow = .idle } }
            )
        ) {
            Button(L10n.Common.ok, role: .cancel) { pullFlow = .idle }
        } message: {
            Text(pullResultMessage)
        }
    }

    private var pullResultTitle: LocalizedStringResource {
        switch pullFlow {
        case .succeeded: L10n.Repository.pullSucceededTitle
        case .skipped: L10n.Repository.pullSkippedTitle
        default: L10n.Repository.pullFailedTitle
        }
    }

    private var pullResultMessage: LocalizedStringResource {
        switch pullFlow {
        case .succeeded: L10n.Repository.pullSucceededMessage
        case .skipped: L10n.Repository.pullSkippedMessage
        default: L10n.Repository.pullFailedMessage
        }
    }

    @ViewBuilder
    private func pullButton(for status: RepoHeaderStatus) -> some View {
        if diffStore.isPulling {
            StatusSpinnerLabel(text: L10n.Repository.pullInProgress)
        } else if let upstream = status.upstream,
                  let branch = status.branch,
                  !status.isDetached {
            Button {
                pullFlow = .confirming
            } label: {
                Label(L10n.format(L10n.Repository.behind, Int64(status.behind)), systemImage: "arrow.down")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.borderless)
            .help(L10n.format(L10n.Repository.pullHelp, upstream, branch))
            .accessibilityLabel(L10n.format(L10n.Repository.pullHelp, upstream, branch))
        } else {
            Label(L10n.format(L10n.Repository.behind, Int64(status.behind)), systemImage: "arrow.down")
                .foregroundStyle(.secondary)
        }
    }

    private var pullConfirmationMessage: String {
        guard let status = diffStore.headerStatus,
              let upstream = status.upstream,
              let branch = status.branch else { return "" }
        return L10n.format(
            L10n.Repository.pullConfirmationMessage,
            Int64(status.behind),
            upstream,
            branch
        )
    }

    private func performPull() async {
        guard let result = await diffStore.pullFromUpstream() else {
            pullFlow = .skipped
            return
        }
        pullFlow = result == .succeeded ? .succeeded : .failed
    }

    @ViewBuilder
    private func branchLabel(_ status: RepoHeaderStatus) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(.secondary)
            if status.isDetached {
                Text(L10n.Repository.detachedHead)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.cyan)
            } else {
                Text(status.branch ?? "—")
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.cyan)
            }
            if status.ahead > 0 {
                Label(L10n.format(L10n.Repository.ahead, Int64(status.ahead)), systemImage: "arrow.up")
                    .foregroundStyle(.secondary)
            }
            if status.behind > 0 || diffStore.isPulling {
                pullButton(for: status)
            }

            Button {
                openInSystemTerminal()
            } label: {
                Image(systemName: "terminal")
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(L10n.Pane.openInTerminal)
            .accessibilityLabel(L10n.Pane.openInTerminal)

            Button(action: onToggleTerminalOnly) {
                Image(systemName: isTerminalOnly ? "rectangle.bottomhalf.inset.filled" : "rectangle.bottomhalf.inset")
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(isTerminalOnly ? L10n.Pane.showTopArea : L10n.Pane.terminalOnly)
            .accessibilityLabel(isTerminalOnly ? L10n.Pane.showTopArea : L10n.Pane.terminalOnly)
        }
        .font(.caption)
        .labelStyle(.titleAndIcon)
    }

    /// Membuka Terminal.app sistem (bukan terminal bawaan Gridline) di root
    /// folder repo — mirror perilaku "buka folder ini di Terminal" Finder.
    private func openInSystemTerminal() {
        guard let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        NSWorkspace.shared.open(
            [URL(fileURLWithPath: repo.path)],
            withApplicationAt: terminalURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}

/// Spinner kecil + caption, dipakai untuk status "membuka branch" dan "sedang
/// pull" yang sebelumnya dua blok identik dengan teks berbeda.
private struct StatusSpinnerLabel: View {
    let text: LocalizedStringResource

    var body: some View {
        HStack(spacing: 5) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
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
