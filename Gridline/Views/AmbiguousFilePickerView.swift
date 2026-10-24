//
//  AmbiguousFilePickerView.swift
//  Gridline
//
//  Daftar pilihan saat Cmd+klik mencocokkan lebih dari satu file di repo
//  dengan nama yang sama — menampilkan pilihan, bukan membuka file pertama
//  yang ditemukan (apps-spec.md bagian 9).
//

import SwiftUI

struct AmbiguousLinkPicker: Identifiable {
    let id = UUID()
    let candidates: [String]
    let line: Int?
}

struct AmbiguousFilePickerView: View {
    let picker: AmbiguousLinkPicker
    let repoPath: String
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.Picker.ambiguousFilesTitle)
                .font(.headline)
                .padding()
            Divider()
            List(picker.candidates, id: \.self) { path in
                Button {
                    onPick(path)
                    dismiss()
                } label: {
                    Text(displayPath(path))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minWidth: 360, minHeight: 240)
    }

    private func displayPath(_ path: String) -> String {
        guard path.hasPrefix(repoPath) else { return path }
        let relative = path.dropFirst(repoPath.count)
        return relative.hasPrefix("/") ? String(relative.dropFirst()) : String(relative)
    }
}
