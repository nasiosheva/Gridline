//
//  RepoPaneView.swift
//  Gridline
//
//  Satu pane repo: header, area atas (tab Diff + tab viewer file), area
//  bawah (terminal). Grid multi-pane dikelola oleh NestedPaneSplitView.
//

import SwiftUI

struct RepoPaneView: View {
    let repo: Repo
    let availableRepos: [Repo]
    @ObservedObject var session: RepoSession
    @Binding var topFraction: CGFloat
    @Binding var sideFraction: CGFloat
    let isActivePane: Bool
    let isMaximized: Bool
    let isTerminalOnly: Bool
    let viewerAsSidePanel: Bool
    var onSelectRepo: (UUID) -> Void
    var onManageRepositories: () -> Void
    var onClose: () -> Void
    var canClosePane: Bool
    var onClosePane: () -> Void
    var onToggleMaximize: () -> Void
    var onToggleTerminalOnly: () -> Void
    var onToggleViewerAsSidePanel: () -> Void

    @EnvironmentObject private var sessionStore: RepoSessionStore
    @EnvironmentObject private var diffStoreRegistry: RepoDiffStoreRegistry
    @EnvironmentObject private var topAreaStoreRegistry: TopAreaStoreRegistry
    @State private var toast: PaneToast?
    @State private var ambiguousPicker: AmbiguousLinkPicker?
    @State private var orientation: PaneOrientationPolicy.Orientation = .vertical

    var body: some View {
        let topAreaStore = topAreaStoreRegistry.store(for: repo)
        let diffStore = diffStoreRegistry.store(for: repo)

        VStack(spacing: 0) {
            RepoPaneHeaderView(
                repo: repo,
                availableRepos: availableRepos,
                diffStore: diffStore,
                attention: session.attention,
                workStatus: session.workStatus,
                isMaximized: isMaximized,
                isTerminalOnly: isTerminalOnly,
                onSelectRepo: onSelectRepo,
                onManageRepositories: onManageRepositories,
                onClose: onClose,
                canClosePane: canClosePane,
                onClosePane: onClosePane,
                onToggleMaximize: onToggleMaximize,
                onToggleTerminalOnly: onToggleTerminalOnly
            )
            Divider()
            if isTerminalOnly {
                TerminalAreaView(session: session, isActivePane: isActivePane)
            } else {
                Group {
                    switch orientation {
                    case .vertical:
                        PersistedVSplit(
                            topFraction: $topFraction,
                            minTopHeight: 200,
                            minBottomHeight: 164
                        ) {
                            TopAreaView(
                                topAreaStore: topAreaStore,
                                diffStore: diffStore,
                                viewerAsSidePanel: viewerAsSidePanel,
                                onToggleViewerAsSidePanel: onToggleViewerAsSidePanel
                            )
                        } bottom: {
                            TerminalAreaView(session: session, isActivePane: isActivePane)
                        }
                    case .horizontal:
                        PersistedHSplit(
                            leadingFraction: $sideFraction,
                            minLeadingWidth: 320,
                            minTrailingWidth: 320
                        ) {
                            TopAreaView(
                                topAreaStore: topAreaStore,
                                diffStore: diffStore,
                                viewerAsSidePanel: viewerAsSidePanel,
                                onToggleViewerAsSidePanel: onToggleViewerAsSidePanel
                            )
                        } trailing: {
                            TerminalAreaView(session: session, isActivePane: isActivePane)
                        }
                    }
                }
                .onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: { newSize in
                    orientation = PaneOrientationPolicy.orientation(for: newSize, current: orientation)
                }
            }
        }
        .frame(minWidth: 680, minHeight: 440)
        .paneToast($toast)
        .sheet(item: $ambiguousPicker) { picker in
            AmbiguousFilePickerView(picker: picker, repoPath: repo.path) { chosen in
                topAreaStore.openFile(path: chosen, scrollToLine: picker.line)
            }
        }
        .task(id: repo.id) {
            session.openFileHandler = { target in
                handleLinkTarget(target, topAreaStore: topAreaStore)
            }
        }
    }

    /// Menindaklanjuti hasil Cmd+klik sebuah path di terminal (bagian 9
    /// apps-spec.md): buka di viewer, atau tampilkan toast/pilihan jika
    /// perlu.
    private func handleLinkTarget(_ target: TerminalLinkTarget, topAreaStore: TopAreaStore) {
        switch target {
        case .file(let path, let line, let isOutsideRepo):
            topAreaStore.openFile(path: path, scrollToLine: line)
            if isOutsideRepo {
                toast = PaneToast(message: L10n.format(L10n.Workspace.openedOutsideRepository, path))
            }
        case .ambiguous(let candidates, let line):
            ambiguousPicker = AmbiguousLinkPicker(candidates: candidates, line: line)
        case .notFound(let text):
            toast = PaneToast(message: L10n.format(L10n.Workspace.fileNotFound, text))
        }
    }
}

