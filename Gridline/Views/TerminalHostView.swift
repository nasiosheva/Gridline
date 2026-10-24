//
//  TerminalHostView.swift
//  Gridline
//
//  Pembungkus NSViewRepresentable di sekitar LocalProcessTerminalView yang
//  SUDAH ADA di TerminalTab. Representable ini tidak pernah membuat view
//  baru — hanya menitipkan tampilan dari model, supaya identitas proses
//  tidak terikat ke siklus hidup struct SwiftUI.
//

import AppKit
import SwiftTerm
import SwiftUI

struct TerminalHostView: NSViewRepresentable {
    let tab: TerminalTab
    let isActivePane: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        tab.terminalView
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        let tabChanged = context.coordinator.tabID != tab.id
        guard isActivePane else {
            context.coordinator.isActivePane = false
            context.coordinator.tabID = tab.id
            return
        }

        let becameActive = !context.coordinator.isActivePane
        context.coordinator.isActivePane = true
        context.coordinator.tabID = tab.id
        guard tabChanged || becameActive else { return }
        requestFocus(for: nsView, tabID: tab.id, coordinator: context.coordinator)
    }

    private func requestFocus(
        for terminalView: LocalProcessTerminalView,
        tabID: UUID,
        coordinator: Coordinator,
        attempt: Int = 0
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(attempt == 0 ? 0 : 20)) {
            guard coordinator.isActivePane,
                  coordinator.tabID == tabID else { return }

            guard let window = terminalView.window else {
                guard attempt < 8 else { return }
                requestFocus(for: terminalView, tabID: tabID, coordinator: coordinator, attempt: attempt + 1)
                return
            }

            guard window.firstResponder !== terminalView,
                  !window.makeFirstResponder(terminalView) else { return }

            guard attempt < 8 else { return }
            requestFocus(for: terminalView, tabID: tabID, coordinator: coordinator, attempt: attempt + 1)
        }
    }

    final class Coordinator {
        var isActivePane = false
        var tabID: UUID?
    }
}
