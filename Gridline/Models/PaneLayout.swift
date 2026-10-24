//
//  PaneLayout.swift
//  Gridline
//
//  State murni untuk susunan grid. Pane hanya mereferensikan repo; sesi
//  terminal, diff, dan viewer tetap dimiliki registry per repo (D6).
//

import Foundation

enum PaneLayoutPreset: Int, CaseIterable, Identifiable, Codable {
    case onePane = 1
    case twoColumns = 2
    case fourGrid = 4

    var id: Int { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .onePane: L10n.Layout.onePane
        case .twoColumns: L10n.Layout.twoColumns
        case .fourGrid: L10n.Layout.fourGrid
        }
    }

    var systemImage: String {
        switch self {
        case .onePane: "rectangle"
        case .twoColumns: "rectangle.split.2x1"
        case .fourGrid: "square.grid.2x2"
        }
    }
}

enum PaneFocusDirection {
    case left
    case right
    case up
    case down
}

enum PaneDividerRole: Hashable {
    case topColumn
    case bottomColumn
    case row
}

struct PaneSlot: Identifiable, Codable, Equatable {
    let id: UUID
    var repoID: UUID?
    var topFraction: Double
    var viewerAsSidePanel: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case repoID
        case topFraction
        case viewerAsSidePanel
    }

    init(
        id: UUID = UUID(),
        repoID: UUID? = nil,
        topFraction: Double = 0.6,
        viewerAsSidePanel: Bool = false
    ) {
        self.id = id
        self.repoID = repoID
        self.topFraction = topFraction
        self.viewerAsSidePanel = viewerAsSidePanel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            repoID: try container.decodeIfPresent(UUID.self, forKey: .repoID),
            topFraction: try container.decodeIfPresent(Double.self, forKey: .topFraction) ?? 0.6,
            viewerAsSidePanel: try container.decodeIfPresent(Bool.self, forKey: .viewerAsSidePanel) ?? false
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(repoID, forKey: .repoID)
        try container.encode(topFraction, forKey: .topFraction)
        try container.encode(viewerAsSidePanel, forKey: .viewerAsSidePanel)
    }
}

struct PaneLayout: Codable, Equatable {
    static let maximumPaneCount = 4

    var slots: [PaneSlot]
    var activePaneID: UUID
    var topColumnFraction: Double
    var bottomColumnFraction: Double
    var rowFraction: Double
    var maximizedPaneID: UUID?
    var terminalOnlyPaneID: UUID?

    private enum CodingKeys: String, CodingKey {
        case slots
        case activePaneID
        case topColumnFraction
        case bottomColumnFraction
        case rowFraction
        case maximizedPaneID
        case terminalOnlyPaneID
    }

    init(
        slots: [PaneSlot] = [PaneSlot(), PaneSlot()],
        activePaneID: UUID? = nil,
        topColumnFraction: Double = 0.5,
        bottomColumnFraction: Double = 0.5,
        rowFraction: Double = 0.5,
        maximizedPaneID: UUID? = nil,
        terminalOnlyPaneID: UUID? = nil
    ) {
        let normalizedSlots = Array(slots.prefix(Self.maximumPaneCount))
        let resolvedSlots = normalizedSlots.isEmpty ? [PaneSlot()] : normalizedSlots
        self.slots = resolvedSlots
        self.activePaneID = activePaneID.flatMap { candidate in
            resolvedSlots.contains(where: { $0.id == candidate }) ? candidate : nil
        } ?? resolvedSlots[0].id
        self.topColumnFraction = topColumnFraction.clampedFraction
        self.bottomColumnFraction = bottomColumnFraction.clampedFraction
        self.rowFraction = rowFraction.clampedFraction
        self.maximizedPaneID = resolvedSlots.contains(where: { $0.id == maximizedPaneID }) ? maximizedPaneID : nil
        self.terminalOnlyPaneID = resolvedSlots.contains(where: { $0.id == terminalOnlyPaneID })
            ? terminalOnlyPaneID
            : nil
        if self.maximizedPaneID != nil {
            self.terminalOnlyPaneID = nil
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            slots: try container.decodeIfPresent([PaneSlot].self, forKey: .slots) ?? [],
            activePaneID: try container.decodeIfPresent(UUID.self, forKey: .activePaneID),
            topColumnFraction: try container.decodeIfPresent(Double.self, forKey: .topColumnFraction) ?? 0.5,
            bottomColumnFraction: try container.decodeIfPresent(Double.self, forKey: .bottomColumnFraction) ?? 0.5,
            rowFraction: try container.decodeIfPresent(Double.self, forKey: .rowFraction) ?? 0.5,
            maximizedPaneID: try container.decodeIfPresent(UUID.self, forKey: .maximizedPaneID),
            terminalOnlyPaneID: try container.decodeIfPresent(UUID.self, forKey: .terminalOnlyPaneID)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(slots, forKey: .slots)
        try container.encode(activePaneID, forKey: .activePaneID)
        try container.encode(topColumnFraction, forKey: .topColumnFraction)
        try container.encode(bottomColumnFraction, forKey: .bottomColumnFraction)
        try container.encode(rowFraction, forKey: .rowFraction)
        try container.encodeIfPresent(maximizedPaneID, forKey: .maximizedPaneID)
        try container.encodeIfPresent(terminalOnlyPaneID, forKey: .terminalOnlyPaneID)
    }

    static func migrated(activeRepoID: UUID?, topFraction: Double) -> PaneLayout {
        let first = PaneSlot(repoID: activeRepoID, topFraction: topFraction)
        return PaneLayout(slots: [first, PaneSlot(topFraction: topFraction)], activePaneID: first.id)
    }

    var activeSlot: PaneSlot {
        slots.first(where: { $0.id == activePaneID }) ?? slots[0]
    }

    mutating func setPreset(_ preset: PaneLayoutPreset) {
        let desiredCount = preset.rawValue
        if slots.count < desiredCount {
            slots.append(contentsOf: (slots.count..<desiredCount).map { _ in PaneSlot() })
        } else if slots.count > desiredCount {
            slots = Array(slots.prefix(desiredCount))
        }
        if !slots.contains(where: { $0.id == activePaneID }) {
            activePaneID = slots.last!.id
        }
        normalizeTransientModes()
    }

    @discardableResult
    mutating func addPane() -> UUID? {
        guard slots.count < Self.maximumPaneCount else { return nil }
        let slot = PaneSlot()
        slots.append(slot)
        activePaneID = slot.id
        return slot.id
    }

    @discardableResult
    mutating func removePane(_ paneID: UUID) -> Bool {
        guard slots.count > 1,
              let index = slots.firstIndex(where: { $0.id == paneID }) else { return false }

        slots.remove(at: index)
        if activePaneID == paneID {
            activePaneID = slots[min(index, slots.count - 1)].id
        }
        if maximizedPaneID == paneID {
            maximizedPaneID = nil
        }
        if terminalOnlyPaneID == paneID {
            terminalOnlyPaneID = nil
        }
        return true
    }

    @discardableResult
    mutating func assign(repoID: UUID, preferNewPane: Bool = false) -> UUID {
        if let existing = slots.first(where: { $0.repoID == repoID }) {
            activePaneID = existing.id
            return existing.id
        }

        if preferNewPane, let newPaneID = addPane(),
           let index = slots.firstIndex(where: { $0.id == newPaneID }) {
            slots[index].repoID = repoID
            return newPaneID
        }

        let activeIndex = slots.firstIndex(where: { $0.id == activePaneID }) ?? 0
        if slots[activeIndex].repoID == nil {
            slots[activeIndex].repoID = repoID
            return slots[activeIndex].id
        }

        if let emptyIndex = slots.firstIndex(where: { $0.repoID == nil }) {
            slots[emptyIndex].repoID = repoID
            activePaneID = slots[emptyIndex].id
            return slots[emptyIndex].id
        }

        if let newPaneID = addPane(),
           let index = slots.firstIndex(where: { $0.id == newPaneID }) {
            slots[index].repoID = repoID
            return newPaneID
        }

        slots[activeIndex].repoID = repoID
        return slots[activeIndex].id
    }

    mutating func clearRepo(in paneID: UUID) {
        guard let index = slots.firstIndex(where: { $0.id == paneID }) else { return }
        slots[index].repoID = nil
        activePaneID = paneID
        if maximizedPaneID == paneID {
            maximizedPaneID = nil
        }
        if terminalOnlyPaneID == paneID {
            terminalOnlyPaneID = nil
        }
    }

    mutating func restoreRepo(_ repoID: UUID, in paneID: UUID) {
        if let existingIndex = slots.firstIndex(where: { $0.repoID == repoID }) {
            activePaneID = slots[existingIndex].id
            return
        }
        guard let paneIndex = slots.firstIndex(where: { $0.id == paneID }) else { return }
        if slots[paneIndex].repoID == nil {
            slots[paneIndex].repoID = repoID
            activePaneID = paneID
        } else {
            _ = assign(repoID: repoID)
        }
    }

    mutating func toggleMaximizedPane(_ paneID: UUID) {
        guard slots.contains(where: { $0.id == paneID && $0.repoID != nil }) else { return }
        activePaneID = paneID
        maximizedPaneID = maximizedPaneID == paneID ? nil : paneID
        terminalOnlyPaneID = nil
    }

    mutating func toggleTerminalOnlyPane(_ paneID: UUID) {
        guard slots.contains(where: { $0.id == paneID && $0.repoID != nil }) else { return }
        activePaneID = paneID
        terminalOnlyPaneID = terminalOnlyPaneID == paneID ? nil : paneID
        maximizedPaneID = nil
    }

    private mutating func normalizeTransientModes() {
        if let maximizedPaneID, !slots.contains(where: { $0.id == maximizedPaneID }) {
            self.maximizedPaneID = nil
        }
        if let terminalOnlyPaneID, !slots.contains(where: { $0.id == terminalOnlyPaneID }) {
            self.terminalOnlyPaneID = nil
        }
        if maximizedPaneID != nil {
            terminalOnlyPaneID = nil
        }
    }

    mutating func removeRepoReference(_ repoID: UUID) {
        for index in slots.indices where slots[index].repoID == repoID {
            slots[index].repoID = nil
            if maximizedPaneID == slots[index].id {
                maximizedPaneID = nil
            }
            if terminalOnlyPaneID == slots[index].id {
                terminalOnlyPaneID = nil
            }
        }
    }

    mutating func focusPane(at index: Int) {
        guard slots.indices.contains(index) else { return }
        activePaneID = slots[index].id
    }

    mutating func focus(_ direction: PaneFocusDirection) {
        guard let currentIndex = slots.firstIndex(where: { $0.id == activePaneID }) else { return }
        let positions = gridPositions
        let current = positions[currentIndex]

        let candidates = positions.enumerated().filter { index, position in
            guard index != currentIndex else { return false }
            switch direction {
            case .left:
                return position.row == current.row && position.column < current.column
            case .right:
                return position.row == current.row && position.column > current.column
            case .up:
                return position.row < current.row
            case .down:
                return position.row > current.row
            }
        }

        let target = candidates.min { lhs, rhs in
            distance(from: current, to: lhs.element, direction: direction)
                < distance(from: current, to: rhs.element, direction: direction)
        }
        if let target {
            activePaneID = slots[target.offset].id
        }
    }

    mutating func setTopFraction(_ fraction: Double, for paneID: UUID) {
        guard let index = slots.firstIndex(where: { $0.id == paneID }) else { return }
        slots[index].topFraction = fraction.clampedFraction
    }

    mutating func setViewerAsSidePanel(_ isEnabled: Bool, for paneID: UUID) {
        guard let index = slots.firstIndex(where: { $0.id == paneID }) else { return }
        slots[index].viewerAsSidePanel = isEnabled
    }

    private var gridPositions: [(row: Double, column: Double)] {
        switch slots.count {
        case 1:
            [(0, 0)]
        case 2:
            [(0, 0), (0, 1)]
        case 3:
            [(0, 0), (0, 1), (1, 0.5)]
        default:
            [(0, 0), (0, 1), (1, 0), (1, 1)]
        }
    }

    private func distance(
        from source: (row: Double, column: Double),
        to target: (row: Double, column: Double),
        direction: PaneFocusDirection
    ) -> Double {
        switch direction {
        case .left, .right:
            abs(source.column - target.column)
        case .up, .down:
            abs(source.row - target.row) * 10 + abs(source.column - target.column)
        }
    }
}

private extension Double {
    var clampedFraction: Double {
        min(max(self, 0.1), 0.9)
    }
}
