//
//  ShortcutHelpView.swift
//  Gridline
//

import SwiftUI

struct ShortcutHelpView: View {
    private let shortcuts: [(String, LocalizedStringResource)] = [
        ("⌘O", L10n.Shortcut.openRepository),
        ("⌘P", L10n.Shortcut.searchRepositoryOrFile),
        ("⌘T", L10n.Shortcut.openTerminalTab),
        ("⌘W", L10n.Shortcut.closeActiveTab),
        ("⌘⇧W", L10n.Shortcut.closeRepository),
        ("⌘1–⌘4", L10n.Shortcut.focusPane),
        ("⌥⌘ + ←/↑/→/↓", L10n.Shortcut.focusNearestPane),
        ("⌃⌘M", L10n.Shortcut.maximizePane),
        ("⌥⌘M", L10n.Shortcut.maximizeTerminal),
        ("⌘F", L10n.Shortcut.findInViewer),
        ("⌘K", L10n.Shortcut.clearTerminal),
        ("⌘Q", L10n.Shortcut.quit)
    ]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.Shortcut.helpTitle)
                    .font(.title2.weight(.semibold))
                Spacer()
                Button(L10n.Common.close) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                ForEach(shortcuts, id: \.0) { item in
                    GridRow {
                        Text(item.0)
                            .font(.system(.body, design: .monospaced).weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(item.1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 480, height: 430)
    }
}
