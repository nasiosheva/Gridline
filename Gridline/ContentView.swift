//
//  ContentView.swift
//  Gridline
//
//  Root UI: toolbar grid, NSSplitViewController antar-pane, serta alur buka
//  repo ke pane aktif. Model sesi tetap berada di registry per repo.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var appState: AppStateStore
    @EnvironmentObject private var sessionStore: RepoSessionStore
    @EnvironmentObject private var diffStoreRegistry: RepoDiffStoreRegistry
    @EnvironmentObject private var topAreaStoreRegistry: TopAreaStoreRegistry
    @State private var errorMessage: String?
    @State private var tccWarningPath: String?
    @State private var closedRepoToast: ClosedRepoToast?
    @State private var pendingRepoClose: PendingRepoClose?
    @State private var isConfirmingQuit = false
    @State private var diagnosticsExportError: String?
    @State private var activeSheet: ContentSheet?

    var body: some View {
        VStack(spacing: 0) {
            GridToolbarView(
                paneCount: layout.slots.count,
                attentionCount: attentionCount,
                activePreset: activePreset,
                onOpenRepo: openRepo,
                onAddPane: appState.addPane,
                onSelectPreset: appState.setLayoutPreset
            )
            Divider()
            grid
        }
        .frame(minWidth: 680, minHeight: 500)
        .modifier(ClearTerminalShortcutModifier())
        .background(WindowConfigurator(autosaveName: "GridlineMainWindow"))
        .onDrop(of: [UTType.fileURL], isTargeted: nil, perform: openDroppedFolder)
        .overlay(alignment: .bottom) {
            if let closedRepoToast {
                ClosedRepoToastView(repoName: closedRepoToast.repo.name) {
                    appState.restoreRepo(id: closedRepoToast.repo.id, in: closedRepoToast.paneID)
                    self.closedRepoToast = nil
                }
                .task(id: closedRepoToast.id) {
                    try? await Task.sleep(for: .seconds(3))
                    if self.closedRepoToast?.id == closedRepoToast.id {
                        self.closedRepoToast = nil
                    }
                }
            }
        }
        .onAppear {
            clearAttention(for: layout.activePaneID)
        }
        .onChange(of: appState.state.paneLayout.activePaneID) { _, paneID in
            clearAttention(for: paneID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .gridlineOpenRepo)) { _ in
            openRepo()
        }
        .onReceive(NotificationCenter.default.publisher(for: .gridlineCloseActiveRepo)) { _ in
            closeRepo(in: layout.activePaneID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .gridlineRequestQuit)) { _ in
            requestQuit()
        }
        .onReceive(NotificationCenter.default.publisher(for: .gridlineQuickSwitcher)) { _ in
            activeSheet = .quickSwitcher
        }
        .onReceive(NotificationCenter.default.publisher(for: .gridlineShortcutHelp)) { _ in
            activeSheet = .shortcutHelp
        }
        .onReceive(NotificationCenter.default.publisher(for: .gridlineToggleDiffFocus)) { _ in
            toggleDiffFocusForActivePane()
        }
        .onReceive(NotificationCenter.default.publisher(for: .gridlineExportDiagnostics)) { _ in
            exportDiagnostics()
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .quickSwitcher:
                QuickSwitcherView(
                    repos: appState.state.savedRepos,
                    files: topAreaStoreRegistry.openFiles(for: appState.state.savedRepos),
                    onSelectRepo: { repo in
                        appState.openRepo(id: repo.id, in: layout.activePaneID)
                    },
                    onSelectFile: { file in
                        guard let repo = appState.state.savedRepos.first(where: { $0.id == file.repoID }) else { return }
                        appState.openRepo(id: repo.id, in: layout.activePaneID)
                        topAreaStoreRegistry.selectFile(path: file.path, in: repo)
                    }
                )
            case .shortcutHelp:
                ShortcutHelpView()
            }
        }
        .confirmationDialog(
            String(localized: L10n.Workspace.closeRepositoryTitle),
            isPresented: Binding(
                get: { pendingRepoClose != nil },
                set: { if !$0 { pendingRepoClose = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.Repository.closeAction, role: .destructive) {
                guard let pendingRepoClose else { return }
                performClose(repo: pendingRepoClose.repo, paneID: pendingRepoClose.paneID)
            }
            Button(L10n.Common.cancel, role: .cancel) {}
        } message: {
            Text(L10n.format(L10n.Workspace.repositoryClosedMessage, Int64(pendingRepoClose?.runningProcessCount ?? 0)))
        }
        .confirmationDialog(
            String(localized: L10n.Workspace.quitTitle),
            isPresented: $isConfirmingQuit,
            titleVisibility: .visible
        ) {
            Button(L10n.Common.cancel, role: .cancel) {}
                .keyboardShortcut(.defaultAction)
            Button(L10n.Menu.quit) {
                NSApp.terminate(nil)
            }
        } message: {
            Text(L10n.format(L10n.Workspace.quitMessage, Int64(sessionStore.runningProcessCount)))
        }
        .alert(String(localized: L10n.Workspace.cannotOpenRepository), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(L10n.Common.ok, role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert(String(localized: L10n.Workspace.folderPermissionTitle), isPresented: Binding(
            get: { tccWarningPath != nil },
            set: { if !$0 { tccWarningPath = nil } }
        )) {
            Button(L10n.Workspace.openSystemSettings) {
                TCCPermission.openPrivacySettings()
            }
            Button(L10n.Common.cancel, role: .cancel) {}
        } message: {
            Text(L10n.format(L10n.Workspace.folderPermissionMessage, tccWarningPath ?? ""))
        }
        .alert(String(localized: L10n.Diagnostics.exportFailedTitle), isPresented: Binding(
            get: { diagnosticsExportError != nil },
            set: { if !$0 { diagnosticsExportError = nil } }
        )) {
            Button(L10n.Common.ok, role: .cancel) {}
        } message: {
            Text(diagnosticsExportError ?? "")
        }
    }

    private var layout: PaneLayout {
        appState.state.paneLayout
    }

    private var activePreset: PaneLayoutPreset? {
        PaneLayoutPreset(rawValue: layout.slots.count)
    }

    private var attentionCount: Int {
        layout.slots.reduce(into: 0) { count, slot in
            guard let repoID = slot.repoID,
                  let repo = appState.state.savedRepos.first(where: { $0.id == repoID }),
                  sessionStore.existingSession(for: repo)?.attention != nil else { return }
            count += 1
        }
    }

    private var grid: some View {
        GeometryReader { geometry in
            if let maximizedPaneID = layout.maximizedPaneID,
               let slot = layout.slots.first(where: { $0.id == maximizedPaneID }) {
                paneContent(for: slot)
                    .environmentObject(appState)
                    .environmentObject(sessionStore)
                    .environmentObject(diffStoreRegistry)
                    .environmentObject(topAreaStoreRegistry)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let minimumSize = PaneMetrics.minimumGridSize(for: layout.slots.count)
                ZStack(alignment: .top) {
                    ScrollView([.horizontal, .vertical]) {
                        NestedPaneSplitView(
                            items: layout.slots.map(makeGridItem),
                            topColumnFraction: CGFloat(layout.topColumnFraction),
                            bottomColumnFraction: CGFloat(layout.bottomColumnFraction),
                            rowFraction: CGFloat(layout.rowFraction)
                        ) { role, fraction in
                            appState.setGridDividerFraction(Double(fraction), role: role)
                        }
                        .frame(
                            width: max(geometry.size.width, minimumSize.width),
                            height: max(geometry.size.height, minimumSize.height)
                        )
                    }

                    if geometry.size.width < minimumSize.width || geometry.size.height < minimumSize.height {
                        sizeWarning
                            .padding(.top, 8)
                    }
                }
            }
        }
    }

    private var sizeWarning: some View {
        Label(L10n.Workspace.minimumWindowSize, systemImage: "arrow.up.left.and.arrow.down.right")
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .shadow(radius: 2)
    }

    private func makeGridItem(_ slot: PaneSlot) -> PaneGridItem {
        PaneGridItem(
            id: slot.id,
            content: AnyView(
                paneContent(for: slot)
                    .environmentObject(appState)
                    .environmentObject(sessionStore)
                    .environmentObject(diffStoreRegistry)
                    .environmentObject(topAreaStoreRegistry)
            )
        )
    }

    @ViewBuilder
    private func paneContent(for slot: PaneSlot) -> some View {
        let isActive = slot.id == layout.activePaneID
        Group {
            if let repoID = slot.repoID,
               let repo = appState.state.savedRepos.first(where: { $0.id == repoID }) {
                if repo.existsOnDisk {
                    RepoPaneView(
                        repo: repo,
                        session: sessionStore.session(for: repo),
                        topFraction: Binding(
                            get: {
                                CGFloat(appState.state.paneLayout.slots.first(where: { $0.id == slot.id })?.topFraction ?? 0.6)
                            },
                            set: { appState.setPaneSplitTopFraction(Double($0), paneID: slot.id) }
                        ),
                        isActivePane: isActive,
                        isMaximized: layout.maximizedPaneID == slot.id,
                        isTerminalOnly: layout.terminalOnlyPaneID == slot.id,
                        viewerAsSidePanel: slot.viewerAsSidePanel,
                        onClose: { closeRepo(in: slot.id) },
                        canClosePane: layout.slots.count > 1,
                        onClosePane: { appState.removePane(id: slot.id) },
                        onToggleMaximize: { appState.toggleMaximizedPane(id: slot.id) },
                        onToggleTerminalOnly: { appState.toggleTerminalOnlyPane(id: slot.id) },
                        onToggleViewerAsSidePanel: {
                            appState.setViewerAsSidePanel(!slot.viewerAsSidePanel, paneID: slot.id)
                        }
                    )
                } else {
                    missingRepoPlaceholder(repo: repo, paneID: slot.id)
                }
            } else {
                panePlaceholder(paneID: slot.id, isActive: isActive)
            }
        }
        .overlay {
            Rectangle()
                .stroke(isActive ? Color.accentColor : .clear, lineWidth: 2)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded {
                appState.focusPane(id: slot.id)
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.format(L10n.Pane.accessibilityLabel, Int64((layout.slots.firstIndex(where: { $0.id == slot.id }) ?? 0) + 1)))
    }

    private func panePlaceholder(paneID: UUID, isActive: Bool) -> some View {
        VStack(spacing: 12) {
            paneActionsMenu(paneID: paneID)
            Image(systemName: "rectangle.dashed")
                .font(.system(size: 32))
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
            Text(L10n.Workspace.emptyPaneTitle)
                .font(.headline)
            Text(L10n.Pane.emptyMessage)
                .foregroundStyle(.secondary)
            if !appState.state.savedRepos.isEmpty {
                Menu {
                    if appState.recentRepositories.isEmpty {
                        Text(L10n.Workspace.noRecentRepositories)
                    } else {
                        ForEach(appState.recentRepositories) { repo in
                            Button {
                                appState.openRepo(id: repo.id, in: paneID)
                            } label: {
                                Label(repo.name, systemImage: "folder")
                            }
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        appState.clearRecentRepositories()
                    } label: {
                        Label(L10n.Workspace.clearRecentRepositories, systemImage: "trash")
                    }
                    .disabled(appState.recentRepositories.isEmpty)
                } label: {
                    Label(L10n.Workspace.recentRepositories, systemImage: "clock.arrow.circlepath")
                }
            }
            Button(L10n.Workspace.openRepository) {
                appState.focusPane(id: paneID)
                openRepo()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private func missingRepoPlaceholder(repo: Repo, paneID: UUID) -> some View {
        VStack(spacing: 12) {
            paneActionsMenu(paneID: paneID)
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.orange)
            Text(L10n.Workspace.missingRepository)
                .font(.headline)
            Text(repo.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Button(L10n.Repository.chooseFolderAgain) {
                appState.focusPane(id: paneID)
                openRepo()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
        .background(.background)
    }

    private func paneActionsMenu(paneID: UUID) -> some View {
        HStack {
            Spacer()
            PaneActionsMenu(
                canClosePane: layout.slots.count > 1,
                onClosePane: { appState.removePane(id: paneID) },
                separatesClosePaneAction: false
            ) {
                EmptyView()
            }
        }
    }

    private func openRepo() {
        guard let result = RepoOpener.choosePanelRepoPath() else { return }
        switch result {
        case .failure(let error):
            errorMessage = error.errorDescription
        case .success(let path):
            openRepo(path: path)
        }
    }

    private func openDroppedFolder(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: URL.self) }) else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            DispatchQueue.main.async {
                openRepo(path: url.path)
            }
        }
        return true
    }

    private func openRepo(path: String) {
        if TCCPermission.isProtectedByTCC(path: path) && !TCCPermission.canReadDirectory(path: path) {
            tccWarningPath = path
            return
        }
        guard Repo(path: path).existsOnDisk else {
            errorMessage = "Folder tidak berisi repository Git yang valid."
            return
        }
        _ = appState.addRepo(path: path)
    }

    private func closeRepo(in paneID: UUID) {
        guard let slot = layout.slots.first(where: { $0.id == paneID }),
              let repoID = slot.repoID,
              let repo = appState.state.savedRepos.first(where: { $0.id == repoID }) else { return }
        let runningProcessCount = sessionStore.existingSession(for: repo)?.runningProcessCount ?? 0
        if runningProcessCount > 0 {
            pendingRepoClose = PendingRepoClose(repo: repo, paneID: paneID, runningProcessCount: runningProcessCount)
        } else {
            performClose(repo: repo, paneID: paneID)
        }
    }

    private func performClose(repo: Repo, paneID: UUID) {
        pendingRepoClose = nil
        appState.clearRepo(in: paneID)
        closedRepoToast = ClosedRepoToast(repo: repo, paneID: paneID)
    }

    private func requestQuit() {
        guard sessionStore.runningProcessCount > 0 else {
            NSApp.terminate(nil)
            return
        }
        isConfirmingQuit = true
    }

    private func clearAttention(for paneID: UUID) {
        guard let slot = layout.slots.first(where: { $0.id == paneID }),
              let repoID = slot.repoID,
              let repo = appState.state.savedRepos.first(where: { $0.id == repoID }) else { return }
        sessionStore.existingSession(for: repo)?.clearAttention()
    }

    private func toggleDiffFocusForActivePane() {
        guard let slot = layout.slots.first(where: { $0.id == layout.activePaneID }),
              let repoID = slot.repoID,
              let repo = appState.state.savedRepos.first(where: { $0.id == repoID }) else { return }
        let diffStore = diffStoreRegistry.store(for: repo)
        diffStore.isFocusMode.toggle()
    }

    private func exportDiagnostics() {
        DiagnosticLog.shared.record(.logExportRequested)
        Task {
            let gitVersion = await GitProcess.version()
            let report = DiagnosticLog.shared.report(gitVersion: gitVersion)
            await MainActor.run {
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.plainText]
                panel.nameFieldStringValue = "Gridline-Diagnostics.txt"
                guard panel.runModal() == .OK, let url = panel.url else { return }
                do {
                    try report.write(to: url, atomically: true, encoding: .utf8)
                    DiagnosticLog.shared.record(.logExported)
                } catch {
                    DiagnosticLog.shared.record(.logExportFailed)
                    diagnosticsExportError = error.localizedDescription
                }
            }
        }
    }
}

private struct ClearTerminalShortcutModifier: ViewModifier {
    @EnvironmentObject private var appState: AppStateStore
    @EnvironmentObject private var sessionStore: RepoSessionStore

    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: .gridlineClearTerminal)) { _ in
            clearActiveTerminal()
        }
    }

    private func clearActiveTerminal() {
        let layout = appState.state.paneLayout
        guard let slot = layout.slots.first(where: { $0.id == layout.activePaneID }),
              let repoID = slot.repoID,
              let repo = appState.state.savedRepos.first(where: { $0.id == repoID }),
              let session = sessionStore.existingSession(for: repo),
              let activeTabID = session.activeTabID,
              let activeTab = session.tabs.first(where: { $0.id == activeTabID }) else { return }
        activeTab.clearTerminal()
    }
}

private enum ContentSheet: String, Identifiable {
    case quickSwitcher
    case shortcutHelp

    var id: String { rawValue }
}

private struct PendingRepoClose: Identifiable {
    let id = UUID()
    let repo: Repo
    let paneID: UUID
    let runningProcessCount: Int
}
