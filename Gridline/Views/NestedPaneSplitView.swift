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
    let retainedPaneIDs: [UUID]
    let dividerFractions: [PaneDividerRole: [CGFloat]]
    let onDividerChanged: (PaneDividerRole, [CGFloat]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDividerChanged: onDividerChanged)
    }

    func makeNSViewController(context: Context) -> PaneGridRootViewController {
        let controller = PaneGridRootViewController()
        controller.update(items: items, retainedPaneIDs: retainedPaneIDs, coordinator: context.coordinator)
        controller.applyDividerFractions(dividerFractions)
        return controller
    }

    func updateNSViewController(_ controller: PaneGridRootViewController, context: Context) {
        context.coordinator.onDividerChanged = onDividerChanged
        controller.update(items: items, retainedPaneIDs: retainedPaneIDs, coordinator: context.coordinator)
        controller.applyDividerFractions(dividerFractions)
    }

    static func dismantleNSViewController(_ controller: PaneGridRootViewController, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    @MainActor
    final class Coordinator: NSObject {
        var onDividerChanged: (PaneDividerRole, [CGFloat]) -> Void
        private var observations: [NSObjectProtocol] = []
        private var roles: [ObjectIdentifier: PaneDividerRole] = [:]
        private var isApplyingFractions = false

        init(onDividerChanged: @escaping (PaneDividerRole, [CGFloat]) -> Void) {
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
            let fractions = splitView.subviews.dropLast().map { subview in
                let dividerPosition = splitView.isVertical ? subview.frame.maxX : subview.frame.maxY
                return dividerPosition / total
            }
            // Notifikasi NSSplitView dapat muncul ketika SwiftUI sedang
            // menjalankan updateNSViewController. Tunda publikasi state satu
            // putaran run loop agar perubahan tidak re-entrant ke view update.
            DispatchQueue.main.async { [weak self] in
                self?.onDividerChanged(role, fractions)
            }
        }
    }
}

@MainActor
final class PaneGridRootViewController: NSViewController {
    private var visiblePaneIDs: [UUID] = []
    private var hostingControllers: [UUID: NSHostingController<AnyView>] = [:]
    private var gridController: NSViewController?
    private weak var coordinator: NestedPaneSplitView.Coordinator?
    private var dividerViews: [PaneDividerRole: NSSplitView] = [:]
    /// Fraction terakhir yang benar-benar diterapkan — dipakai supaya
    /// `applyDividerFractions` tidak memicu `layoutSubtreeIfNeeded()` (layout
    /// pass AppKit sinkron) saat SwiftUI re-render karena state lain yang
    /// tidak terkait grid (lihat AppStateStore, satu `@Published` untuk
    /// seluruh `AppState`).
    private var lastAppliedFractions: [PaneDividerRole: [CGFloat]]?

    override func loadView() {
        view = NSView()
    }

    func update(
        items: [PaneGridItem],
        retainedPaneIDs: [UUID],
        coordinator: NestedPaneSplitView.Coordinator
    ) {
        self.coordinator = coordinator
        let retainedIDs = Set(retainedPaneIDs)
        let removedIDs = hostingControllers.keys.filter { !retainedIDs.contains($0) }
        for id in removedIDs {
            guard let controller = hostingControllers.removeValue(forKey: id) else { continue }
            controller.view.removeFromSuperview()
            controller.removeFromParent()
        }

        for item in items {
            if let controller = hostingControllers[item.id] {
                controller.rootView = item.content
            } else {
                hostingControllers[item.id] = NSHostingController(rootView: item.content)
            }
        }

        let newVisiblePaneIDs = items.map(\.id)
        guard newVisiblePaneIDs != visiblePaneIDs else { return }
        rebuild(with: items, coordinator: coordinator)
    }

    func applyDividerFractions(_ fractions: [PaneDividerRole: [CGFloat]]) {
        guard let coordinator else { return }
        guard lastAppliedFractions != fractions else { return }
        lastAppliedFractions = fractions
        view.layoutSubtreeIfNeeded()
        coordinator.applyingFractions {
            for (role, splitFractions) in fractions {
                set(splitFractions, on: dividerViews[role])
            }
        }
    }

    private func rebuild(with items: [PaneGridItem], coordinator: NestedPaneSplitView.Coordinator) {
        coordinator.stopObserving()
        // Keep each pane's hosting controller alive while its tile is outside
        // the selected view. Only detach it from the current split hierarchy.
        hostingControllers.values.forEach { controller in
            controller.view.removeFromSuperview()
            controller.removeFromParent()
        }
        if let gridController {
            gridController.view.removeFromSuperview()
            gridController.removeFromParent()
        }

        visiblePaneIDs = items.map(\.id)
        dividerViews.removeAll()
        // Split view baru belum punya posisi divider — paksa applyDividerFractions
        // berikutnya benar-benar jalan walau fraction-nya kebetulan sama seperti
        // sebelum rebuild.
        lastAppliedFractions = nil

        let shape = PaneGridShape(paneCount: items.count)
        var itemOffset = 0
        var rowControllers: [NSViewController] = []
        if !items.isEmpty {
            for (row, rowLength) in shape.rowLengths.enumerated() {
                let rowItems = Array(items[itemOffset..<(itemOffset + rowLength)])
                var controllers = rowItems.compactMap { hostingControllers[$0.id] }
                while controllers.count < shape.columnCount {
                    controllers.append(NSHostingController(rootView: AnyView(Color.clear)))
                }
                rowControllers.append(makeColumnSplit(controllers: controllers, row: row))
                itemOffset += rowLength
            }
        }

        let nextController: NSViewController
        switch items.count {
        case 0:
            nextController = NSHostingController(rootView: AnyView(EmptyView()))
        case 1:
            nextController = rowControllers[0]
        default:
            nextController = makeRowSplit(controllers: rowControllers)
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
        row: Int
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
        dividerViews[.columns(row: row)] = splitController.splitView
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
        dividerViews[.rows] = splitController.splitView
        return splitController
    }

    private func set(_ fractions: [CGFloat], on splitView: NSSplitView?) {
        guard let splitView, splitView.subviews.count > 1 else { return }
        let total = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
        guard total > 0 else { return }
        for (index, fraction) in fractions.enumerated() where index < splitView.subviews.count - 1 {
            let target = total * BoundedValue.clamp(fraction, to: 0.1...0.9)
            let current = splitView.isVertical
                ? splitView.subviews[index].frame.maxX
                : splitView.subviews[index].frame.maxY
            guard abs(current - target) > 1 else { continue }
            splitView.setPosition(target, ofDividerAt: index)
        }
    }
}

enum PaneMetrics {
    static let toolbarHeight: CGFloat = 52
    static let minimumPaneWidth: CGFloat = 680
    static let minimumPaneHeight: CGFloat = 440
    static let columnGap: CGFloat = 20
    static let rowGap: CGFloat = 8

    static func minimumGridSize(for paneCount: Int) -> CGSize {
        let shape = PaneGridShape(paneCount: paneCount)
        return CGSize(
            width: CGFloat(shape.columnCount) * minimumPaneWidth
                + CGFloat(max(0, shape.columnCount - 1)) * columnGap,
            height: CGFloat(shape.rowCount) * minimumPaneHeight
                + CGFloat(max(0, shape.rowCount - 1)) * rowGap
        )
    }
}
