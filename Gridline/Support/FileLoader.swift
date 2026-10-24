//
//  FileLoader.swift
//  Gridline
//
//  Memuat isi file untuk viewer read-only, dengan batas ukuran dari bagian 7
//  apps-spec.md: teks sampai 5 MB, gambar/PDF sampai 20 MB. File di luar itu
//  atau jenis biner lain tidak dibuka sebagai teks.
//

import AppKit
import Foundation

enum FileContent {
    case loading
    case text(String)
    case image(NSImage)
    case pdf(URL)
    case tooLarge(sizeBytes: Int64, isMedia: Bool)
    case unsupportedBinary
    case notFound
    case error(String)
}

enum FileLoader {
    static let maxTextBytes: Int64 = 5 * 1024 * 1024
    static let maxMediaBytes: Int64 = 20 * 1024 * 1024

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "heic", "webp"
    ]

    static func load(path: String) -> FileContent {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return .notFound
        }
        guard let attributes = try? fm.attributesOfItem(atPath: path),
              let size = attributes[.size] as? Int64 else {
            return .error(String(localized: L10n.Viewer.readAttributesFailed))
        }

        let ext = (path as NSString).pathExtension.lowercased()

        if imageExtensions.contains(ext) {
            guard size <= maxMediaBytes else { return .tooLarge(sizeBytes: size, isMedia: true) }
            guard let image = NSImage(contentsOfFile: path) else { return .error(String(localized: L10n.Viewer.imageLoadFailed)) }
            return .image(image)
        }

        if ext == "pdf" {
            guard size <= maxMediaBytes else { return .tooLarge(sizeBytes: size, isMedia: true) }
            return .pdf(URL(fileURLWithPath: path))
        }

        guard size <= maxTextBytes else { return .tooLarge(sizeBytes: size, isMedia: false) }
        guard let data = fm.contents(atPath: path) else { return .error(String(localized: L10n.Viewer.readContentsFailed)) }
        if data.isEmpty { return .text("") }
        guard let text = String(data: data, encoding: .utf8) else { return .unsupportedBinary }
        return .text(text)
    }
}
