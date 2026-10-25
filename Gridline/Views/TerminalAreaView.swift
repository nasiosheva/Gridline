//
//  TerminalAreaView.swift
//  Gridline
//
//  Area bawah pane: bar tab terminal (+ dan ×) dan terminal aktif.
//  Konfirmasi menutup tab hanya saat shell melaporkan command aktif.
//

import SwiftUI

struct TerminalAreaView: View {
    @ObservedObject var session: RepoSession
    let isActivePane: Bool
    @AppStorage(GridlinePreferences.terminalFontSizeKey)
    private var terminalFontSize = GridlinePreferences.defaultTerminalFontSize

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            if let activeTab = session.tabs.first(where: { $0.id == session.activeTabID }) {
                TerminalHostView(tab: activeTab, isActivePane: isActivePane)
                    .id(activeTab.id)
            }
        }
        .background(Color.black.opacity(0.85))
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 2) {
                    ForEach(session.tabs) { tabChip(for: $0) }
                }

                HStack(spacing: 2) {
                    if let activeTab = session.tabs.first(where: { $0.id == session.activeTabID }) {
                        tabChip(for: activeTab)
                    }
                    tabOverflowMenu
                }
            }

            Button {
                session.addTab()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .padding(6)
            .help(L10n.Terminal.newTab)

            Spacer()

            Button {
                GridlinePreferences.adjustTerminalFontSize(by: -1)
            } label: {
                Image(systemName: "textformat.size.smaller")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(terminalFontSize <= GridlinePreferences.minimumTerminalFontSize)
            .help(L10n.Terminal.decreaseTextSize)
            .accessibilityLabel(L10n.Terminal.decreaseTextSize)

            Button {
                GridlinePreferences.adjustTerminalFontSize(by: 1)
            } label: {
                Image(systemName: "textformat.size.larger")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(terminalFontSize >= GridlinePreferences.maximumTerminalFontSize)
            .help(L10n.Terminal.increaseTextSize)
            .accessibilityLabel(L10n.Terminal.increaseTextSize)
        }
        .padding(.horizontal, 4)
        .frame(height: 28)
    }

    private var tabOverflowMenu: some View {
        Menu {
            ForEach(session.tabs) { tab in
                Button {
                    session.activeTabID = tab.id
                } label: {
                    if tab.id == session.activeTabID {
                        Label(tab.title, systemImage: "checkmark")
                    } else {
                        Text(tab.title)
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .help(L10n.Terminal.openTabs)
        .accessibilityLabel(L10n.Terminal.openTabs)
    }

    private func tabChip(for tab: TerminalTab) -> some View {
        TerminalTabChip(
            tab: tab,
            isActive: tab.id == session.activeTabID,
            onSelect: { session.activeTabID = tab.id },
            onClose: { session.closeTab(id: tab.id) }
        )
    }
}

private struct TerminalTabChip: View {
    @ObservedObject var tab: TerminalTab
    let isActive: Bool
    var onSelect: () -> Void
    var onClose: () -> Void

    @State private var isRenaming = false
    @State private var draftTitle = ""
    @State private var isConfirmingClose = false

    var body: some View {
        HStack(spacing: 4) {
            if isRenaming {
                TextField(String(localized: L10n.Terminal.tabNamePlaceholder), text: $draftTitle, onCommit: commitRename)
                    .textFieldStyle(.plain)
                    .frame(width: 80)
            } else {
                Text(tab.title)
                    .lineLimit(1)
                    .onTapGesture(count: 2) {
                        draftTitle = tab.title
                        isRenaming = true
                    }
            }

            Button {
                if tab.hasActiveCommand {
                    isConfirmingClose = true
                } else {
                    onClose()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
            }
            .buttonStyle(.plain)
            .help(L10n.Terminal.closeTab)
            .accessibilityLabel(L10n.Terminal.closeTab)
        }
        .font(.caption)
        .foregroundStyle(isActive ? .primary : .secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isActive ? Color.white.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .confirmationDialog(
            String(localized: L10n.Terminal.closeRunningTabTitle),
            isPresented: $isConfirmingClose,
            titleVisibility: .visible
        ) {
            Button(L10n.Terminal.closeTab, role: .destructive, action: onClose)
            Button(L10n.Common.cancel, role: .cancel) {}
        } message: {
            Text(L10n.Terminal.closeRunningTabMessage)
        }
    }

    private func commitRename() {
        tab.rename(to: draftTitle)
        isRenaming = false
    }
}
