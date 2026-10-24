//
//  PaneToastView.swift
//  Gridline
//
//  Pesan singkat yang hilang sendiri, dipakai untuk notifikasi non-modal
//  (apps-spec.md bagian 15b), misalnya "file tidak ditemukan" dari Cmd+klik.
//

import SwiftUI

struct PaneToast: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

struct PaneToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 4)
            .padding(.bottom, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

struct ClosedRepoToast: Identifiable, Equatable {
    let id = UUID()
    let repo: Repo
    let paneID: UUID
}

struct ClosedRepoToastView: View {
    let repoName: String
    var onRestore: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(L10n.Toast.repositoryClosed)
            Button(L10n.Toast.reopen, action: onRestore)
                .buttonStyle(.link)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 4)
        .padding(.bottom, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.format(L10n.Toast.repositoryClosedAccessibility, repoName))
    }
}

extension View {
    /// Menampilkan toast di bagian bawah, hilang otomatis setelah `duration`.
    func paneToast(_ toast: Binding<PaneToast?>, duration: Duration = .seconds(3)) -> some View {
        overlay(alignment: .bottom) {
            if let current = toast.wrappedValue {
                PaneToastView(message: current.message)
                    .task(id: current.id) {
                        try? await Task.sleep(for: duration)
                        if toast.wrappedValue?.id == current.id {
                            toast.wrappedValue = nil
                        }
                    }
            }
        }
        .animation(.default, value: toast.wrappedValue)
    }
}
