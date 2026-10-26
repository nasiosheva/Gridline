//
//  PersistedHSplit.swift
//  Gridline
//
//  Pembagi kiri/kanan dalam satu pane, dipakai saat `PaneOrientationPolicy`
//  memilih orientasi horizontal (pane lebar-pendek). Sama persis dengan
//  `PersistedVSplit` tapi sumbunya ditukar; posisi disimpan sebagai pecahan
//  lebar total lewat `PaneSlot.sideFraction`.
//

import SwiftUI

struct PersistedHSplit<Leading: View, Trailing: View>: View {
    @Binding var leadingFraction: CGFloat
    let minLeadingWidth: CGFloat
    let minTrailingWidth: CGFloat
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    @State private var liveLeadingWidth: CGFloat?
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let maxLeading = max(minLeadingWidth, totalWidth - minTrailingWidth)
            let committedLeadingWidth = BoundedValue.clamp(totalWidth * leadingFraction, to: minLeadingWidth...maxLeading)
            let leadingWidth = BoundedValue.clamp(liveLeadingWidth ?? committedLeadingWidth, to: minLeadingWidth...maxLeading)

            HStack(spacing: 0) {
                leading()
                    .frame(width: leadingWidth)
                    .clipped()

                dividerHandle(totalWidth: totalWidth, maxLeading: maxLeading, currentLeading: leadingWidth)

                trailing()
                    .frame(width: max(0, totalWidth - leadingWidth - 6))
                    .clipped()
            }
        }
    }

    private func dividerHandle(totalWidth: CGFloat, maxLeading: CGFloat, currentLeading: CGFloat) -> some View {
        Divider()
            .frame(width: 6)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    NSCursor.resizeLeftRight.set()
                } else if !isDragging {
                    NSCursor.arrow.set()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        isDragging = true
                        let newLeading = BoundedValue.clamp(currentLeading + value.translation.width, to: minLeadingWidth...maxLeading)
                        liveLeadingWidth = newLeading
                    }
                    .onEnded { _ in
                        if totalWidth > 0, let finalLeading = liveLeadingWidth {
                            leadingFraction = finalLeading / totalWidth
                        }
                        liveLeadingWidth = nil
                        isDragging = false
                        NSCursor.arrow.set()
                    }
            )
    }
}
