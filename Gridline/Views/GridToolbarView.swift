//
//  GridToolbarView.swift
//  Gridline
//

import SwiftUI

struct GridToolbarView: View {
    let paneCount: Int
    let paneCountLimit: Int
    let paneCountChoices: [Int]
    let canAddPane: Bool
    let attentionCount: Int
    let selectedPaneCount: Int
    let onOpenRepo: () -> Void
    let onAddPane: () -> Void
    let onSelectPaneCount: (Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(L10n.Common.openRepository, systemImage: "folder.badge.plus", action: onOpenRepo)

            Menu {
                Button(L10n.Menu.addPane, systemImage: "plus.rectangle.on.rectangle", action: onAddPane)
                    .disabled(!canAddPane)

                Divider()

                ForEach(paneCountChoices, id: \.self) { count in
                    Button {
                        onSelectPaneCount(count)
                    } label: {
                        HStack {
                            Label(
                                L10n.Layout.paneCountOption(count),
                                systemImage: layoutSymbol(for: count)
                            )
                            Spacer()
                            if selectedPaneCount == count {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label {
                    Text(L10n.format(L10n.Layout.menuLabel, Int64(paneCount), Int64(paneCountLimit)))
                } icon: {
                    Image(systemName: "square.grid.2x2")
                }
            }
            .help(L10n.Layout.menuHelp)
            .accessibilityLabel(L10n.format(L10n.Layout.menuLabel, Int64(paneCount), Int64(paneCountLimit)))

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

    private func layoutSymbol(for count: Int) -> String {
        switch count {
        case 1: "rectangle"
        case 2: "rectangle.split.2x1"
        default: "square.grid.2x2"
        }
    }
}
