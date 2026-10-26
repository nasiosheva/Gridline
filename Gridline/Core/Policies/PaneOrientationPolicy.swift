import CoreGraphics

/// Menentukan arah pembagi dalam satu pane (atas/bawah vs kiri/kanan) dari
/// bentuk aktual area kontennya. Pane yang lebar-pendek (mis. window
/// di-tile ke atas/bawah lewat menu Window macOS) memakai split kiri-kanan
/// (diff kiri, terminal kanan) supaya lebar termanfaatkan; pane yang
/// sempit-tinggi (di-tile ke kiri/kanan) tetap atas-bawah seperti semula.
/// Ambang ganda (histeresis) mencegah orientasi bolak-balik di dekat rasio
/// 1:1 saat pengguna resize window perlahan.
enum PaneOrientationPolicy {
    enum Orientation: Equatable {
        case vertical
        case horizontal
    }

    private static let toHorizontalAspectRatio: CGFloat = 1.6
    private static let toVerticalAspectRatio: CGFloat = 1.3

    static func orientation(for size: CGSize, current: Orientation) -> Orientation {
        guard size.width > 0, size.height > 0 else { return current }
        let aspectRatio = size.width / size.height
        switch current {
        case .vertical where aspectRatio >= toHorizontalAspectRatio:
            return .horizontal
        case .horizontal where aspectRatio <= toVerticalAspectRatio:
            return .vertical
        default:
            return current
        }
    }
}
