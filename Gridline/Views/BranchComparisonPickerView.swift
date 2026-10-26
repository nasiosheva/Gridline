import SwiftUI

enum BranchComparisonPickerPolicy {
    static func canCompare(base: String, target: String) -> Bool {
        !base.isEmpty && !target.isEmpty && base != target
    }

    static func initialSelection(
        branches: [String],
        savedBase: String?,
        savedTarget: String?
    ) -> (base: String, target: String) {
        let base = savedBase ?? branches.first ?? ""
        let target = savedTarget ?? branches.first(where: { $0 != base }) ?? ""
        return (base, target)
    }

    static func repairedSelection(
        branches: [String],
        base: String,
        target: String
    ) -> (base: String, target: String) {
        guard !branches.isEmpty else { return (base, target) }
        let repairedBase = branches.contains(base) ? base : branches[0]
        let repairedTarget = branches.contains(target) && target != repairedBase
            ? target
            : branches.first(where: { $0 != repairedBase }) ?? ""
        return (repairedBase, repairedTarget)
    }
}

struct BranchComparisonPickerView: View {
    @ObservedObject var store: RepoDiffStore
    @Environment(\.dismiss) private var dismiss
    @State private var baseBranch = ""
    @State private var targetBranch = ""

    private var canCompare: Bool {
        BranchComparisonPickerPolicy.canCompare(base: baseBranch, target: targetBranch)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.Diff.compareBranches)
                .font(.headline)

            if store.availableComparisonBranches.count < 2 {
                ContentUnavailableView(
                    String(localized: L10n.Diff.notEnoughBranches),
                    systemImage: "arrow.triangle.branch"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Picker(L10n.Diff.baseBranch, selection: $baseBranch) {
                    ForEach(store.availableComparisonBranches, id: \.self) { branch in
                        Text(branch).tag(branch)
                    }
                }

                Picker(L10n.Diff.targetBranch, selection: $targetBranch) {
                    ForEach(store.availableComparisonBranches, id: \.self) { branch in
                        Text(branch).tag(branch)
                    }
                }

                Text(L10n.Diff.branchComparisonExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }

            HStack {
                Button(L10n.Common.cancel) {
                    dismiss()
                }

                Spacer()

                Button(L10n.Diff.applyBranchComparison) {
                    guard canCompare else { return }
                    store.selectComparisonBranches(from: baseBranch, to: targetBranch)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCompare)
            }
        }
        .padding(20)
        .frame(width: 420, height: 270)
        .onAppear {
            selectInitialBranches()
            store.refreshGitMetadata()
        }
        .onReceive(store.$availableComparisonBranches) { branches in
            // Hanya betulkan pilihan kalau branch yang sedang terpilih sudah tidak ada
            // lagi di daftar baru (misalnya dihapus dari luar) — jangan menimpa pilihan
            // manual pengguna yang masih valid setiap kali daftar branch di-refresh.
            let selection = BranchComparisonPickerPolicy.repairedSelection(
                branches: branches,
                base: baseBranch,
                target: targetBranch
            )
            baseBranch = selection.base
            targetBranch = selection.target
        }
    }

    private func selectInitialBranches() {
        let selection = BranchComparisonPickerPolicy.initialSelection(
            branches: store.availableComparisonBranches,
            savedBase: store.comparisonBaseBranch,
            savedTarget: store.comparisonTargetBranch
        )
        baseBranch = selection.base
        targetBranch = selection.target
    }
}
