//
//  Clipboard.swift
//  Gridline
//
//  Helper kecil untuk tombol "Salin ..." (path, perintah, diff) di panel
//  diff dan viewer (bagian 7, 9 & 17a apps-spec.md).
//

import AppKit

extension NSPasteboard {
    static func copyString(_ string: String) {
        general.clearContents()
        general.setString(string, forType: .string)
    }
}
