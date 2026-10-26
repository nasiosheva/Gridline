//
//  PersistedVSplit.swift
//  Gridline
//
//  Pembagi atas/bawah dalam satu pane, bisa digeser dan posisinya disimpan
//  (bagian 4 & 12 apps-spec.md). Dibuat manual (bukan SwiftUI VSplitView)
//  supaya posisi bisa dibaca dan dipulihkan sebagai pecahan tinggi total.
//  NSSplitViewController bersarang (disebut di bagian 15) dicadangkan untuk
//  pembagi ANTAR-PANE di grid M3; pembagi di dalam satu pane ini cukup
//  dengan drag gesture SwiftUI.
//

import SwiftUI

struct PersistedVSplit<Top: View, Bottom: View>: View {
    @Binding var topFraction: CGFloat
    let minTopHeight: CGFloat
    let minBottomHeight: CGFloat
    @ViewBuilder var top: () -> Top
    @ViewBuilder var bottom: () -> Bottom

    @State private var liveTopHeight: CGFloat?
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let totalHeight = geo.size.height
            let maxTop = max(minTopHeight, totalHeight - minBottomHeight)
            let committedTopHeight = BoundedValue.clamp(totalHeight * topFraction, to: minTopHeight...maxTop)
            let topHeight = BoundedValue.clamp(liveTopHeight ?? committedTopHeight, to: minTopHeight...maxTop)

            VStack(spacing: 0) {
                top()
                    .frame(height: topHeight)
                    .clipped()

                dividerHandle(totalHeight: totalHeight, maxTop: maxTop, currentTop: topHeight)

                bottom()
                    .frame(height: max(0, totalHeight - topHeight - 6))
                    .clipped()
            }
        }
    }

    private func dividerHandle(totalHeight: CGFloat, maxTop: CGFloat, currentTop: CGFloat) -> some View {
        Divider()
            .frame(height: 6)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    NSCursor.resizeUpDown.set()
                } else if !isDragging {
                    NSCursor.arrow.set()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        isDragging = true
                        let newTop = BoundedValue.clamp(currentTop + value.translation.height, to: minTopHeight...maxTop)
                        liveTopHeight = newTop
                    }
                    .onEnded { _ in
                        if totalHeight > 0, let finalTop = liveTopHeight {
                            topFraction = finalTop / totalHeight
                        }
                        liveTopHeight = nil
                        isDragging = false
                        NSCursor.arrow.set()
                    }
            )
    }
}
