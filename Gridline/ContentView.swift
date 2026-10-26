//
//  ContentView.swift
//  Gridline
//
//  Root UI: NSSplitViewController antar-pane serta alur buka
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
    @State private var batchCloseQueue: [BatchCloseCandidate] = []
    @State private var batchCloseIndex = 0
    @State private var pendingBatchClose: PendingBatchClose?
    @State private var pendingLayoutChange: PendingLayoutChange?
    @State private var isConfirmingQuit = false
    @State private var diagnosticsExportError: String?
    @State private var activeSheet: ContentSheet?

    var body: some View {
        diagnosticsAlert
    }

    private var baseContent: some View {
        grid
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
    }

    private var lifecycleContent: some View {
        baseContent
        .onAppear(perform: configureInitialState)
        .onChange(of: paneRepoIDs) { _, _ in
            updateStoreVisibility()
        }
        .onChange(of: topAreaRepoIDs) { _, _ in
            updateStoreVisibility()
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
        .onReceive(NotificationCenter.default.publisher(for: .gridlineCloseAllRepositories)) { _ in
            closeAllRepositoriesFromPanes()
        }
        .onReceive(NotificationCenter.default.publisher(for: .gridlineManageRepositories)) { _ in
            activeSheet = .repositoryManager
        }
        .onReceive(NotificationCenter.default.publisher(for: .gridlineRequestQuit)) { _ in
            requestQuit()
        }
        .onReceive(NotificationCenter.default.publisher(for: .gridlineQuickSwitcher)) { _ in
            openQuickSwitcher()
        }
        .onReceive(NotificationCenter.default.publisher(for: .gridlineShowSingleRepository)) { _ in
            showSingleRepositoryPicker()
        }
        .onReceive(NotificationCenter.default.publisher(for: .gridlineRequestPaneCount)) { notification in
            guard let paneCount = notification.userInfo?["paneCount"] as? Int else { return }
            requestPaneCount(paneCount)
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
    }

    private var sheetContent: some View {
        lifecycleContent
            .sheet(item: $activeSheet, content: sheetView(for:))
    }

    @ViewBuilder
    private func sheetView(for sheet: ContentSheet) -> some View {
        switch sheet {
        case .quickSwitcher:
            QuickSwitcherView(
                repos: appState.state.savedRepos,
                files: topAreaStoreRegistry.openFiles(for: appState.state.savedRepos),
                onSelectRepo: selectQuickSwitcherRepo,
                onSelectFile: selectQuickSwitcherFile
            )
        case .shortcutHelp:
            ShortcutHelpView()
        case .repositoryManager:
            RepositoryManagerView(
                repos: appState.state.savedRepos,
                onRemoveRepositories: removeSavedRepositories
            )
        case .worktreePicker(let repo, let paneID):
            WorktreeBranchPickerView(repo: repo, replacingPaneID: paneID)
                .environmentObject(appState)
        }
    }

    private func selectQuickSwitcherRepo(_ repo: Repo) {
        appState.openRepo(id: repo.id, in: layout.activePaneID)
    }

    private func openQuickSwitcher() {
        activeSheet = .quickSwitcher
    }

    private func showSingleRepositoryPicker() {
        requestPaneCount(1, opensQuickSwitcherAfterward: true)
    }

    private func presentQuickSwitcherAfterCurrentAction() {
        Task { @MainActor in
            await Task.yield()
            activeSheet = .quickSwitcher
        }
    }

    private func selectQuickSwitcherFile(_ file: QuickSwitcherFile) {
        guard let repo = appState.state.savedRepos.first(where: { $0.id == file.repoID }) else { return }
        appState.openRepo(id: repo.id, in: layout.activePaneID)
        topAreaStoreRegistry.selectFile(path: file.path, in: repo)
    }

    private var repositoryCloseConfirmation: some View {
        sheetContent
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
            Text(L10n.format(L10n.Workspace.repositoryClosedMessage, Int64(pendingRepoClose?.activeCommandCount ?? 0)))
        }
        .confirmationDialog(
            L10n.format(L10n.Workspace.batchCloseTitle, pendingBatchClose?.repo.name ?? ""),
            isPresented: Binding(
                get: { pendingBatchClose != nil },
                set: { isPresented in
                    if !isPresented, pendingBatchClose != nil {
                        resolveBatchClose(stopAndClose: false)
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.Workspace.stopAndCloseRepository, role: .destructive) {
                resolveBatchClose(stopAndClose: true)
            }
            Button(L10n.Workspace.keepRepositoryOpen, role: .cancel) {
                resolveBatchClose(stopAndClose: false)
            }
        } message: {
            Text(L10n.format(
                L10n.Workspace.batchCloseMessage,
                Int64(pendingBatchClose?.activeCommandCount ?? 0),
                pendingBatchClose?.repo.name ?? ""
            ))
        }
    }

    private var layoutChangeConfirmation: some View {
        repositoryCloseConfirmation
        .confirmationDialog(
            String(localized: L10n.Layout.hideWithActiveTerminalCommandsTitle),
            isPresented: Binding(
                get: { pendingLayoutChange != nil },
                set: { if !$0 { pendingLayoutChange = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.Layout.changeLayout) {
                guard let pendingLayoutChange else { return }
                appState.setDisplayPaneCount(pendingLayoutChange.paneCount)
                let shouldOpenQuickSwitcher = pendingLayoutChange.opensQuickSwitcherAfterward
                self.pendingLayoutChange = nil
                if shouldOpenQuickSwitcher {
                    presentQuickSwitcherAfterCurrentAction()
                }
            }
            .keyboardShortcut(.defaultAction)
            Button(L10n.Common.cancel, role: .cancel) {}
        } message: {
            Text(L10n.format(
                L10n.Layout.hideWithActiveTerminalCommandsMessage,
                Int64(pendingLayoutChange?.activeCommandCount ?? 0)
            ))
        }
    }

    private var quitConfirmation: some View {
        layoutChangeConfirmation
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
    }

    private var repositoryOpenErrorAlert: some View {
        quitConfirmation
        .alert(String(localized: L10n.Workspace.cannotOpenRepository), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(L10n.Common.ok, role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var folderPermissionAlert: some View {
        repositoryOpenErrorAlert
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
    }

    private var diagnosticsAlert: some View {
        folderPermissionAlert
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

    private var visiblePaneSlots: [PaneSlot] {
        guard let maximizedPaneID = layout.maximizedPaneID else { return layout.displayedSlots }
        return layout.slots.filter { $0.id == maximizedPaneID }
    }

    private var paneRepoIDs: Set<UUID> {
        Set(visiblePaneSlots.compactMap(\.repoID))
    }

    private var topAreaRepoIDs: Set<UUID> {
        Set(visiblePaneSlots.filter { $0.id != layout.terminalOnlyPaneID }.compactMap(\.repoID))
    }

    private func updateStoreVisibility(refreshExistingDiffStores: Bool = false) {
        diffStoreRegistry.setVisibleRepoIDs(paneRepoIDs, refreshExisting: refreshExistingDiffStores)
        topAreaStoreRegistry.setVisibleRepoIDs(topAreaRepoIDs)
    }

    private func configureInitialState() {
        updateStoreVisibility(refreshExistingDiffStores: true)
        clearAttention(for: layout.activePaneID)
    }

    private func requestPaneCount(_ paneCount: Int, opensQuickSwitcherAfterward: Bool = false) {
        let decision = PaneCountChangePolicy.decision(
            paneCount: paneCount,
            layout: layout,
            visiblePaneSlots: visiblePaneSlots
        ) { repoID in
            guard let repo = appState.state.savedRepos.first(where: { $0.id == repoID }) else { return 0 }
            return sessionStore.existingSession(for: repo)?.activeCommandCount ?? 0
        }

        switch decision {
        case .applyImmediately(let paneCount):
            appState.setDisplayPaneCount(paneCount)
            if opensQuickSwitcherAfterward {
                presentQuickSwitcherAfterCurrentAction()
            }
        case .confirm(let paneCount, let activeCommandCount):
            pendingLayoutChange = PendingLayoutChange(
                paneCount: paneCount,
                activeCommandCount: activeCommandCount,
                opensQuickSwitcherAfterward: opensQuickSwitcherAfterward
            )
        }
    }

    private var availablePaneRepos: [Repo] {
        appState.state.savedRepos.filter(\.existsOnDisk)
    }

    private var grid: some View {
        GeometryReader { geometry in
            let gridSlots = visiblePaneSlots
            let minimumSize = PaneMetrics.minimumGridSize(for: gridSlots.count)
            ZStack(alignment: .top) {
                ScrollView([.horizontal, .vertical]) {
                    NestedPaneSplitView(
                        items: gridSlots.map(makeGridItem),
                        retainedPaneIDs: layout.slots.map(\.id),
                        dividerFractions: layout.dividerFractions(for: gridSlots.count).mapValues { fractions in
                            fractions.map { CGFloat($0) }
                        }
                    ) { role, fractions in
                        appState.setGridDividerFractions(fractions.map { Double($0) }, role: role)
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
                        availableRepos: availablePaneRepos,
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
                        onSelectRepo: { appState.selectRepo(id: $0, in: slot.id) },
                        onManageRepositories: { activeSheet = .repositoryManager },
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
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 12) {
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

            closePaneButton(paneID)
                .padding(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private func missingRepoPlaceholder(repo: Repo, paneID: UUID) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 12) {
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
                if let sourceRepo = worktreeSourceRepo(for: repo) {
                    Button(L10n.Worktree.chooseBranchAgain) {
                        appState.focusPane(id: paneID)
                        activeSheet = .worktreePicker(repo: sourceRepo, paneID: paneID)
                    }
                } else {
                    Button(L10n.Repository.chooseFolderAgain) {
                        appState.focusPane(id: paneID)
                        openRepo()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            closePaneButton(paneID)
                .padding(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
        .background(.background)
    }

    private func closePaneButton(_ paneID: UUID) -> some View {
        PaneCloseButton(canClosePane: layout.slots.count > 1) {
            appState.removePane(id: paneID)
        }
    }

    private func worktreeSourceRepo(for missingRepo: Repo) -> Repo? {
        let candidates = appState.state.savedRepos.filter { $0.id != missingRepo.id && $0.existsOnDisk }
        if let sourceID = missingRepo.worktreeSourceRepoID {
            return candidates.first(where: { $0.id == sourceID })
        }
        if let displayName = missingRepo.displayName,
           let separator = displayName.range(of: " — ") {
            let sourceName = String(displayName[..<separator.lowerBound])
            let matchingRepos = candidates.filter { $0.name == sourceName }
            if matchingRepos.count == 1 { return matchingRepos.first }
        }
        return candidates.count == 1 ? candidates.first : nil
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
            errorMessage = L10n.format(L10n.Repository.invalidRepositoryMessage, path)
            return
        }
        _ = appState.addRepo(path: path)
    }

    private func closeRepo(in paneID: UUID) {
        guard let slot = layout.slots.first(where: { $0.id == paneID }),
              let repoID = slot.repoID,
              let repo = appState.state.savedRepos.first(where: { $0.id == repoID }) else { return }
        let activeCommandCount = sessionStore.existingSession(for: repo)?.activeCommandCount ?? 0
        if activeCommandCount > 0 {
            pendingRepoClose = PendingRepoClose(repo: repo, paneID: paneID, activeCommandCount: activeCommandCount)
        } else {
            performClose(repo: repo, paneID: paneID)
        }
    }

    private func performClose(repo: Repo, paneID: UUID) {
        pendingRepoClose = nil
        appState.clearRepo(in: paneID)
        closedRepoToast = ClosedRepoToast(repo: repo, paneID: paneID)
    }

    private func removeSavedRepositories(_ repos: [Repo]) {
        for repo in repos {
            sessionStore.terminateSession(for: repo)
            appState.removeRepo(id: repo.id)
        }
    }

    private func closeAllRepositoriesFromPanes() {
        guard pendingBatchClose == nil else { return }
        batchCloseQueue = layout.slots.compactMap { slot in
            guard let repoID = slot.repoID else { return nil }
            return BatchCloseCandidate(repoID: repoID, paneID: slot.id)
        }
        batchCloseIndex = 0
        advanceBatchCloseQueue()
    }

    private func advanceBatchCloseQueue() {
        while batchCloseIndex < batchCloseQueue.count {
            let candidate = batchCloseQueue[batchCloseIndex]
            batchCloseIndex += 1
            guard layout.slots.contains(where: { $0.id == candidate.paneID && $0.repoID == candidate.repoID }),
                  let repo = appState.state.savedRepos.first(where: { $0.id == candidate.repoID }) else { continue }

            let activeCommandCount = sessionStore.existingSession(for: repo)?.activeCommandCount ?? 0
            if activeCommandCount > 0 {
                pendingBatchClose = PendingBatchClose(
                    repo: repo,
                    paneID: candidate.paneID,
                    activeCommandCount: activeCommandCount
                )
                return
            }
            appState.clearRepo(in: candidate.paneID)
        }
        batchCloseQueue.removeAll()
        batchCloseIndex = 0
    }

    private func resolveBatchClose(stopAndClose: Bool) {
        guard let pendingBatchClose else { return }
        self.pendingBatchClose = nil
        if stopAndClose {
            sessionStore.terminateSession(for: pendingBatchClose.repo)
            appState.clearRepo(in: pendingBatchClose.paneID)
        }
        Task { @MainActor in
            await Task.yield()
            advanceBatchCloseQueue()
        }
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

private enum ContentSheet: Identifiable {
    case quickSwitcher
    case shortcutHelp
    case repositoryManager
    case worktreePicker(repo: Repo, paneID: UUID)

    var id: String {
        switch self {
        case .quickSwitcher:
            return "quickSwitcher"
        case .shortcutHelp:
            return "shortcutHelp"
        case .repositoryManager:
            return "repositoryManager"
        case .worktreePicker(let repo, let paneID):
            return "worktreePicker-\(repo.id.uuidString)-\(paneID.uuidString)"
        }
    }
}

private struct PendingRepoClose: Identifiable {
    let id = UUID()
    let repo: Repo
    let paneID: UUID
    let activeCommandCount: Int
}

private struct BatchCloseCandidate {
    let repoID: UUID
    let paneID: UUID
}

private struct PendingBatchClose {
    let repo: Repo
    let paneID: UUID
    let activeCommandCount: Int
}

private struct PendingLayoutChange {
    let paneCount: Int
    let activeCommandCount: Int
    let opensQuickSwitcherAfterward: Bool
}
