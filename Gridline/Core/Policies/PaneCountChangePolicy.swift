import Foundation

enum PaneCountChangeDecision: Equatable {
    case applyImmediately(Int)
    case confirm(paneCount: Int, activeCommandCount: Int)
}

enum PaneCountChangePolicy {
    static func decision(
        paneCount: Int,
        layout: PaneLayout,
        visiblePaneSlots: [PaneSlot],
        activeCommandCountForRepo: (UUID) -> Int
    ) -> PaneCountChangeDecision {
        guard paneCount < layout.displayPaneCount else {
            return .applyImmediately(paneCount)
        }

        var proposedLayout = layout
        proposedLayout.setDisplayPaneCount(paneCount)
        let retainedRepoIDs = Set(proposedLayout.displayedSlots.compactMap(\.repoID))
        let hiddenRepoIDs = Set(visiblePaneSlots.compactMap(\.repoID)).subtracting(retainedRepoIDs)
        let activeCommandCount = hiddenRepoIDs.reduce(into: 0) { total, repoID in
            total += activeCommandCountForRepo(repoID)
        }

        guard activeCommandCount > 0 else {
            return .applyImmediately(paneCount)
        }
        return .confirm(paneCount: paneCount, activeCommandCount: activeCommandCount)
    }
}
