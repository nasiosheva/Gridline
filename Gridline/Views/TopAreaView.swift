//
//  TopAreaView.swift
//  Gridline
//
//  Area atas pane: tab bar dengan tab "Diff" (selalu ada, tidak bisa
//  ditutup) dan tab viewer file yang bisa ditutup (bagian 4 apps-spec.md).
//  Menu overflow untuk tab yang tidak muat ditunda ke M4 (lihat TASK.md).
//

import SwiftUI

struct TopAreaView: View {
    @ObservedObject var topAreaStore: TopAreaStore
    @ObservedObject var diffStore: RepoDiffStore
    let viewerAsSidePanel: Bool
    var onToggleViewerAsSidePanel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            content
        }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                TopTabChip(
                    title: String(localized: L10n.TopArea.diffTab),
                    isActive: topAreaStore.selection == .diff,
                    isClosable: false,
                    onSelect: { topAreaStore.selection = .diff },
                    onClose: {}
                )

                ForEach(topAreaStore.openFiles) { tab in
                    TopTabChip(
                        title: tab.displayName,
                        isActive: topAreaStore.selection == .file(tab.id),
                        isClosable: true,
                        onSelect: { topAreaStore.selection = .file(tab.id) },
                        onClose: { topAreaStore.closeFile(id: tab.id) }
                    )
                }

                Spacer(minLength: 8)

                Button(action: onToggleViewerAsSidePanel) {
                    Image(systemName: viewerAsSidePanel ? "rectangle.split.2x1" : "sidebar.right")
                }
                .buttonStyle(.plain)
                .help(viewerAsSidePanel ? L10n.TopArea.showViewerAsTab : L10n.TopArea.showViewerBesideDiff)
                .accessibilityLabel(viewerAsSidePanel ? L10n.TopArea.showViewerAsTab : L10n.TopArea.showViewerBesideDiff)
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 28)
    }

    @ViewBuilder
    private var content: some View {
        switch topAreaStore.selection {
        case .diff:
            DiffAreaView(store: diffStore) { path in
                topAreaStore.openFile(path: path)
            }
        case .file(let id):
            if let tab = topAreaStore.openFiles.first(where: { $0.id == id }) {
                if viewerAsSidePanel {
                    HSplitView {
                        DiffAreaView(
                            store: diffStore,
                            onOpenFile: { path in topAreaStore.openFile(path: path) },
                            showsFileList: false
                        )
                        .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)

                        FileViewerContentView(tab: tab)
                            .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    FileViewerContentView(tab: tab)
                }
            } else {
                DiffAreaView(store: diffStore) { path in
                    topAreaStore.openFile(path: path)
                }
            }
        }
    }
}

private struct TopTabChip: View {
    let title: String
    let isActive: Bool
    let isClosable: Bool
    var onSelect: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .lineLimit(1)
            if isClosable {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                }
                .buttonStyle(.plain)
            }
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}
