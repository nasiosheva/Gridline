//
//  GridToolbarView.swift
//  Gridline
//

import SwiftUI

struct GridToolbarView: View {
    let paneCount: Int
    let attentionCount: Int
    let activePreset: PaneLayoutPreset?
    let onOpenRepo: () -> Void
    let onAddPane: () -> Void
    let onSelectPreset: (PaneLayoutPreset) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(L10n.Common.openRepository, systemImage: "folder.badge.plus", action: onOpenRepo)

            Menu {
                Button(L10n.Menu.addPane, systemImage: "plus.rectangle.on.rectangle", action: onAddPane)
                    .disabled(paneCount >= PaneLayout.maximumPaneCount)

                Divider()

                ForEach(PaneLayoutPreset.allCases) { preset in
                    Button {
                        onSelectPreset(preset)
                    } label: {
                        HStack {
                            Label(preset.title, systemImage: preset.systemImage)
                            Spacer()
                            if activePreset == preset {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label {
                    Text(L10n.format(L10n.Layout.menuLabel, Int64(paneCount), Int64(PaneLayout.maximumPaneCount)))
                } icon: {
                    Image(systemName: "square.grid.2x2")
                }
            }
            .help(L10n.Layout.menuHelp)
            .accessibilityLabel(L10n.format(L10n.Layout.menuLabel, Int64(paneCount), Int64(PaneLayout.maximumPaneCount)))

            Spacer()

            if attentionCount > 0 {
                Label("\(attentionCount)", systemImage: "bell.badge.fill")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.orange)
                    .help(L10n.format(L10n.Pane.attentionCount, Int64(attentionCount)))
                    .accessibilityLabel(L10n.format(L10n.Pane.attentionCount, Int64(attentionCount)))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: PaneMetrics.toolbarHeight)
        .background(.bar)
    }
}
