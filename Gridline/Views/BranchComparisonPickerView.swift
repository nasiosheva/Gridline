import SwiftUI

struct BranchComparisonPickerView: View {
    @ObservedObject var store: RepoDiffStore
    @Environment(\.dismiss) private var dismiss
    @State private var baseBranch = ""
    @State private var targetBranch = ""

    private var canCompare: Bool {
        !baseBranch.isEmpty && !targetBranch.isEmpty && baseBranch != targetBranch
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
        .onAppear(perform: selectInitialBranches)
    }

    private func selectInitialBranches() {
        let branches = store.availableComparisonBranches
        baseBranch = store.comparisonBaseBranch ?? branches.first ?? ""
        targetBranch = store.comparisonTargetBranch
            ?? branches.first(where: { $0 != baseBranch })
            ?? ""
    }
}
