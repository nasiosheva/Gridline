//
//  NestedPaneSplitView.swift
//  Gridline
//
//  Grid antar-pane berbasis NSSplitViewController bersarang. SwiftUI tetap
//  mengelola isi setiap pane; AppKit hanya mengelola pembagi grid.
//

import AppKit
import SwiftUI

struct PaneGridItem: Identifiable {
    let id: UUID
    let content: AnyView
}

struct NestedPaneSplitView: NSViewControllerRepresentable {
    let items: [PaneGridItem]
    let topColumnFraction: CGFloat
    let bottomColumnFraction: CGFloat
    let rowFraction: CGFloat
    let onDividerChanged: (PaneDividerRole, CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDividerChanged: onDividerChanged)
    }

    func makeNSViewController(context: Context) -> PaneGridRootViewController {
        let controller = PaneGridRootViewController()
        controller.update(items: items, coordinator: context.coordinator)
        controller.applyDividerFractions(
            topColumn: topColumnFraction,
            bottomColumn: bottomColumnFraction,
            row: rowFraction
        )
        return controller
    }

    func updateNSViewController(_ controller: PaneGridRootViewController, context: Context) {
        context.coordinator.onDividerChanged = onDividerChanged
        controller.update(items: items, coordinator: context.coordinator)
        controller.applyDividerFractions(
            topColumn: topColumnFraction,
            bottomColumn: bottomColumnFraction,
            row: rowFraction
        )
    }

    static func dismantleNSViewController(_ controller: PaneGridRootViewController, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    @MainActor
    final class Coordinator: NSObject {
        var onDividerChanged: (PaneDividerRole, CGFloat) -> Void
        private var observations: [NSObjectProtocol] = []
        private var roles: [ObjectIdentifier: PaneDividerRole] = [:]
        private var isApplyingFractions = false

        init(onDividerChanged: @escaping (PaneDividerRole, CGFloat) -> Void) {
            self.onDividerChanged = onDividerChanged
        }

        func observe(_ splitViews: [(NSSplitView, PaneDividerRole)]) {
            stopObserving()
            for (splitView, role) in splitViews {
                roles[ObjectIdentifier(splitView)] = role
                let observation = NotificationCenter.default.addObserver(
                    forName: NSSplitView.didResizeSubviewsNotification,
                    object: splitView,
                    queue: .main
                ) { [weak self, weak splitView] _ in
                    guard let self, let splitView else { return }
                    MainActor.assumeIsolated {
                        self.reportFraction(for: splitView)
                    }
                }
                observations.append(observation)
            }
        }

        func stopObserving() {
            observations.forEach(NotificationCenter.default.removeObserver)
            observations.removeAll()
            roles.removeAll()
        }

        func applyingFractions(_ action: () -> Void) {
            isApplyingFractions = true
            action()
            isApplyingFractions = false
        }

        private func reportFraction(for splitView: NSSplitView) {
            guard !isApplyingFractions,
                  splitView.subviews.count > 1,
                  let role = roles[ObjectIdentifier(splitView)] else { return }
            let total = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
            guard total > 0 else { return }
            let firstLength = splitView.isVertical
                ? splitView.subviews[0].frame.width
                : splitView.subviews[0].frame.height
            let fraction = firstLength / total
            // Notifikasi NSSplitView dapat muncul ketika SwiftUI sedang
            // menjalankan updateNSViewController. Tunda publikasi state satu
            // putaran run loop agar perubahan tidak re-entrant ke view update.
            DispatchQueue.main.async { [weak self] in
                self?.onDividerChanged(role, fraction)
            }
        }
    }
}

@MainActor
final class PaneGridRootViewController: NSViewController {
    private var paneIDs: [UUID] = []
    private var hostingControllers: [UUID: NSHostingController<AnyView>] = [:]
    private var gridController: NSViewController?
    private weak var coordinator: NestedPaneSplitView.Coordinator?
    private var dividerViews: [PaneDividerRole: NSSplitView] = [:]
    /// Fraction terakhir yang benar-benar diterapkan — dipakai supaya
    /// `applyDividerFractions` tidak memicu `layoutSubtreeIfNeeded()` (layout
    /// pass AppKit sinkron) saat SwiftUI re-render karena state lain yang
    /// tidak terkait grid (lihat AppStateStore, satu `@Published` untuk
    /// seluruh `AppState`).
    private var lastAppliedFractions: (topColumn: CGFloat, bottomColumn: CGFloat, row: CGFloat)?

    override func loadView() {
        view = NSView()
    }

    func update(items: [PaneGridItem], coordinator: NestedPaneSplitView.Coordinator) {
        self.coordinator = coordinator
        let newIDs = items.map(\.id)
        if newIDs != paneIDs {
            rebuild(with: items, coordinator: coordinator)
        } else {
            for item in items {
                hostingControllers[item.id]?.rootView = item.content
            }
        }
    }

    func applyDividerFractions(topColumn: CGFloat, bottomColumn: CGFloat, row: CGFloat) {
        guard let coordinator else { return }
        if let last = lastAppliedFractions,
           last.topColumn == topColumn, last.bottomColumn == bottomColumn, last.row == row {
            return
        }
        lastAppliedFractions = (topColumn, bottomColumn, row)
        view.layoutSubtreeIfNeeded()
        coordinator.applyingFractions {
            set(topColumn, on: dividerViews[.topColumn])
            set(bottomColumn, on: dividerViews[.bottomColumn])
            set(row, on: dividerViews[.row])
        }
    }

    private func rebuild(with items: [PaneGridItem], coordinator: NestedPaneSplitView.Coordinator) {
        coordinator.stopObserving()
        if let gridController {
            gridController.view.removeFromSuperview()
            gridController.removeFromParent()
        }

        paneIDs = items.map(\.id)
        hostingControllers = Dictionary(uniqueKeysWithValues: items.map { item in
            (item.id, NSHostingController(rootView: item.content))
        })
        dividerViews.removeAll()
        // Split view baru belum punya posisi divider — paksa applyDividerFractions
        // berikutnya benar-benar jalan walau fraction-nya kebetulan sama seperti
        // sebelum rebuild.
        lastAppliedFractions = nil

        let nextController: NSViewController
        switch items.count {
        case 0:
            nextController = NSHostingController(rootView: AnyView(EmptyView()))
        case 1:
            nextController = hostingControllers[items[0].id]!
        case 2:
            nextController = makeColumnSplit(
                controllers: items.compactMap { hostingControllers[$0.id] },
                role: .topColumn
            )
        default:
            let top = makeColumnSplit(
                controllers: Array(items.prefix(2)).compactMap { hostingControllers[$0.id] },
                role: .topColumn
            )
            let bottom = makeColumnSplit(
                controllers: Array(items.dropFirst(2)).compactMap { hostingControllers[$0.id] },
                role: .bottomColumn
            )
            nextController = makeRowSplit(controllers: [top, bottom])
        }

        addChild(nextController)
        nextController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(nextController.view)
        NSLayoutConstraint.activate([
            nextController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            nextController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            nextController.view.topAnchor.constraint(equalTo: view.topAnchor),
            nextController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        gridController = nextController

        coordinator.observe(dividerViews.map { ($0.value, $0.key) })
    }

    private func makeColumnSplit(
        controllers: [NSViewController],
        role: PaneDividerRole
    ) -> NSViewController {
        guard controllers.count > 1 else { return controllers[0] }
        let splitController = NSSplitViewController()
        splitController.splitView.isVertical = true
        splitController.splitView.dividerStyle = .thin
        controllers.forEach { controller in
            let item = NSSplitViewItem(viewController: controller)
            item.minimumThickness = PaneMetrics.minimumPaneWidth
            item.canCollapse = false
            splitController.addSplitViewItem(item)
        }
        dividerViews[role] = splitController.splitView
        return splitController
    }

    private func makeRowSplit(controllers: [NSViewController]) -> NSSplitViewController {
        let splitController = NSSplitViewController()
        splitController.splitView.isVertical = false
        splitController.splitView.dividerStyle = .thin
        controllers.forEach { controller in
            let item = NSSplitViewItem(viewController: controller)
            item.minimumThickness = PaneMetrics.minimumPaneHeight
            item.canCollapse = false
            splitController.addSplitViewItem(item)
        }
        dividerViews[.row] = splitController.splitView
        return splitController
    }

    private func set(_ fraction: CGFloat, on splitView: NSSplitView?) {
        guard let splitView, splitView.subviews.count > 1 else { return }
        let total = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
        guard total > 0 else { return }
        let target = total * min(max(fraction, 0.1), 0.9)
        let current = splitView.isVertical
            ? splitView.subviews[0].frame.width
            : splitView.subviews[0].frame.height
        guard abs(current - target) > 1 else { return }
        splitView.setPosition(target, ofDividerAt: 0)
    }
}

enum PaneMetrics {
    static let toolbarHeight: CGFloat = 52
    static let minimumPaneWidth: CGFloat = 680
    static let minimumPaneHeight: CGFloat = 440
    static let twoColumnWidth: CGFloat = 1_380
    static let twoRowHeight: CGFloat = 888

    static func minimumGridSize(for paneCount: Int) -> CGSize {
        switch paneCount {
        case 1:
            CGSize(width: minimumPaneWidth, height: minimumPaneHeight)
        case 2:
            CGSize(width: twoColumnWidth, height: minimumPaneHeight)
        default:
            CGSize(width: twoColumnWidth, height: twoRowHeight)
        }
    }
}
