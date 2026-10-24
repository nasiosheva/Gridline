//
//  PDFKitView.swift
//  Gridline
//
//  Pratinjau PDF di viewer (bagian 7 apps-spec.md), pakai PDFKit bawaan.
//

import PDFKit
import SwiftUI

struct PDFKitView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document?.documentURL != url {
            nsView.document = PDFDocument(url: url)
        }
    }
}
