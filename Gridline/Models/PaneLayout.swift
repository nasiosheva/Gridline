//
//  PaneLayout.swift
//  Gridline
//
//  State murni untuk susunan grid. Pane hanya mereferensikan repo; sesi
//  terminal, diff, dan viewer tetap dimiliki registry per repo (D6).
//

import Foundation

enum PaneFocusDirection {
    case left
    case right
    case up
    case down
}

enum PaneDividerRole: Hashable {
    case columns(row: Int)
    case rows

    var storageKey: String {
        switch self {
        case .columns(let row): "columns.\(row)"
        case .rows: "rows"
        }
    }
}

struct PaneGridShape {
    let columnCount: Int
    let rowLengths: [Int]

    var rowCount: Int { rowLengths.count }

    init(paneCount: Int) {
        let count = max(1, paneCount)
        columnCount = Int(ceil(sqrt(Double(count))))
        let rows = Int(ceil(Double(count) / Double(columnCount)))
        let baseRowLength = count / rows
        let longerRowCount = count % rows
        rowLengths = (0..<rows).map { row in
            baseRowLength + (row < longerRowCount ? 1 : 0)
        }
    }

    var positions: [(row: Double, column: Double)] {
        rowLengths.enumerated().flatMap { row, length in
            (0..<length).map { column in
                (Double(row), Double(column))
            }
        }
    }
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
    var slots: [PaneSlot]
    var displayPaneCount: Int
    var activePaneID: UUID
    var topColumnFraction: Double
    var bottomColumnFraction: Double
    var rowFraction: Double
    var gridDividerFractions: [String: [Double]]
    var maximizedPaneID: UUID?
    var terminalOnlyPaneID: UUID?

    private enum CodingKeys: String, CodingKey {
        case slots
        case displayPaneCount
        case activePaneID
        case topColumnFraction
        case bottomColumnFraction
        case rowFraction
        case dividerFractions
        case maximizedPaneID
        case terminalOnlyPaneID
    }

    init(
        slots: [PaneSlot] = [PaneSlot(), PaneSlot()],
        displayPaneCount: Int? = nil,
        activePaneID: UUID? = nil,
        topColumnFraction: Double = 0.5,
        bottomColumnFraction: Double = 0.5,
        rowFraction: Double = 0.5,
        gridDividerFractions: [String: [Double]] = [:],
        maximizedPaneID: UUID? = nil,
        terminalOnlyPaneID: UUID? = nil
    ) {
        let resolvedSlots = slots.isEmpty ? [PaneSlot()] : slots
        self.slots = resolvedSlots
        self.displayPaneCount = min(max(1, displayPaneCount ?? resolvedSlots.count), resolvedSlots.count)
        self.activePaneID = activePaneID.flatMap { candidate in
            resolvedSlots.contains(where: { $0.id == candidate }) ? candidate : nil
        } ?? resolvedSlots[0].id
        self.topColumnFraction = topColumnFraction.clampedFraction
        self.bottomColumnFraction = bottomColumnFraction.clampedFraction
        self.rowFraction = rowFraction.clampedFraction
        self.gridDividerFractions = gridDividerFractions.mapValues { $0.map(\.clampedFraction) }
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
        let decodedSlots = try container.decodeIfPresent([PaneSlot].self, forKey: .slots) ?? []
        self.init(
            slots: decodedSlots,
            displayPaneCount: try container.decodeIfPresent(Int.self, forKey: .displayPaneCount) ?? decodedSlots.count,
            activePaneID: try container.decodeIfPresent(UUID.self, forKey: .activePaneID),
            topColumnFraction: try container.decodeIfPresent(Double.self, forKey: .topColumnFraction) ?? 0.5,
            bottomColumnFraction: try container.decodeIfPresent(Double.self, forKey: .bottomColumnFraction) ?? 0.5,
            rowFraction: try container.decodeIfPresent(Double.self, forKey: .rowFraction) ?? 0.5,
            gridDividerFractions: try container.decodeIfPresent([String: [Double]].self, forKey: .dividerFractions) ?? [:],
            maximizedPaneID: try container.decodeIfPresent(UUID.self, forKey: .maximizedPaneID),
            terminalOnlyPaneID: try container.decodeIfPresent(UUID.self, forKey: .terminalOnlyPaneID)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(slots, forKey: .slots)
        try container.encode(displayPaneCount, forKey: .displayPaneCount)
        try container.encode(activePaneID, forKey: .activePaneID)
        try container.encode(topColumnFraction, forKey: .topColumnFraction)
        try container.encode(bottomColumnFraction, forKey: .bottomColumnFraction)
        try container.encode(rowFraction, forKey: .rowFraction)
        try container.encode(gridDividerFractions, forKey: .dividerFractions)
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

    var displayedSlots: [PaneSlot] {
        let visibleCount = min(displayPaneCount, slots.count)
        var visibleSlots = Array(slots.prefix(visibleCount))
        let currentSlot = activeSlot
        if !visibleSlots.contains(where: { $0.id == currentSlot.id }), !visibleSlots.isEmpty {
            visibleSlots[visibleSlots.count - 1] = currentSlot
        }
        return visibleSlots
    }

    mutating func setDisplayPaneCount(_ desiredCount: Int) {
        let desiredCount = max(1, desiredCount)
        if slots.count < desiredCount {
            slots.append(contentsOf: (slots.count..<desiredCount).map { _ in PaneSlot() })
        }
        displayPaneCount = desiredCount
        maximizedPaneID = nil
        normalizeTransientModes()
    }

    @discardableResult
    mutating func addPane() -> UUID {
        let slot = PaneSlot()
        slots.append(slot)
        displayPaneCount = slots.count
        activePaneID = slot.id
        return slot.id
    }

    @discardableResult
    mutating func removePane(_ paneID: UUID) -> Bool {
        guard slots.count > 1,
              let index = slots.firstIndex(where: { $0.id == paneID }) else { return false }

        slots.remove(at: index)
        displayPaneCount = min(displayPaneCount, slots.count)
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

        if preferNewPane {
            let newPaneID = addPane()
            guard let index = slots.firstIndex(where: { $0.id == newPaneID }) else { return newPaneID }
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

        let newPaneID = addPane()
        if let index = slots.firstIndex(where: { $0.id == newPaneID }) {
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

    mutating func selectRepo(_ repoID: UUID, in paneID: UUID) {
        guard let paneIndex = slots.firstIndex(where: { $0.id == paneID }) else { return }
        let preservesMaximizedMode = maximizedPaneID == paneID
        let preservesTerminalOnlyMode = terminalOnlyPaneID == paneID

        if let existingIndex = slots.firstIndex(where: { $0.repoID == repoID }) {
            guard existingIndex != paneIndex else {
                activePaneID = paneID
                return
            }
            slots.swapAt(paneIndex, existingIndex)
            activePaneID = slots[paneIndex].id
        } else {
            if slots[paneIndex].repoID == nil {
                slots[paneIndex].repoID = repoID
                activePaneID = paneID
            } else {
                let previousSlot = slots.remove(at: paneIndex)
                let selectedSlot = PaneSlot(repoID: repoID)
                slots.insert(selectedSlot, at: paneIndex)
                slots.append(previousSlot)
                activePaneID = selectedSlot.id
            }
        }

        if preservesMaximizedMode {
            maximizedPaneID = activePaneID
        }
        if preservesTerminalOnlyMode {
            terminalOnlyPaneID = activePaneID
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
        let visibleSlots = displayedSlots
        guard visibleSlots.indices.contains(index) else { return }
        activePaneID = visibleSlots[index].id
    }

    mutating func focus(_ direction: PaneFocusDirection) {
        let visibleSlots = displayedSlots
        guard let currentIndex = visibleSlots.firstIndex(where: { $0.id == activePaneID }) else { return }
        let positions = PaneGridShape(paneCount: visibleSlots.count).positions
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
            activePaneID = visibleSlots[target.offset].id
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

    func dividerFractions(for paneCount: Int) -> [PaneDividerRole: [Double]] {
        let shape = PaneGridShape(paneCount: paneCount)
        var result: [PaneDividerRole: [Double]] = [:]
        for (row, length) in shape.rowLengths.enumerated() where length > 1 {
            let role = PaneDividerRole.columns(row: row)
            if let saved = gridDividerFractions[role.storageKey], saved.count == length - 1 {
                result[role] = saved
            } else if length == 2 {
                result[role] = [row == 0 ? topColumnFraction : bottomColumnFraction]
            } else {
                result[role] = evenlySpacedFractions(dividerCount: length - 1)
            }
        }
        if shape.rowCount > 1 {
            let role = PaneDividerRole.rows
            if let saved = gridDividerFractions[role.storageKey], saved.count == shape.rowCount - 1 {
                result[role] = saved
            } else if shape.rowCount == 2 {
                result[role] = [rowFraction]
            } else {
                result[role] = evenlySpacedFractions(dividerCount: shape.rowCount - 1)
            }
        }
        return result
    }

    mutating func setDividerFractions(_ fractions: [Double], for role: PaneDividerRole) {
        let clamped = fractions.map(\.clampedFraction)
        guard gridDividerFractions[role.storageKey] != clamped else { return }
        gridDividerFractions[role.storageKey] = clamped
        switch role {
        case .columns(row: 0) where clamped.count == 1:
            topColumnFraction = clamped[0]
        case .columns(row: 1) where clamped.count == 1:
            bottomColumnFraction = clamped[0]
        case .rows where clamped.count == 1:
            rowFraction = clamped[0]
        default:
            break
        }
    }

    private func evenlySpacedFractions(dividerCount: Int) -> [Double] {
        (1...dividerCount).map { Double($0) / Double(dividerCount + 1) }
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
            abs(source.row - target.row) * Double(Int(ceil(sqrt(Double(slots.count)))) + 1)
                + abs(source.column - target.column)
        }
    }
}

private extension Double {
    var clampedFraction: Double {
        min(max(self, 0.1), 0.9)
    }
}
