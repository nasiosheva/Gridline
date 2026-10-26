//
//  RepoIdentityColor.swift
//  Gridline
//

import SwiftUI

enum RepoIdentityColor {
    private static let palette: [Color] = [
        .blue, .purple, .orange, .teal, .pink, .green, .indigo, .cyan
    ]

    static func color(for repo: Repo) -> Color {
        let hash = repo.id.uuidString.utf8.reduce(UInt64(1469598103934665603)) { partial, byte in
            (partial ^ UInt64(byte)) &* 1099511628211
        }
        return palette[Int(hash % UInt64(palette.count))]
    }
}
