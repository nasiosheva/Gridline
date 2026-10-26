# Progres coverage test (2026-10-26)

Suite `GridlineTests` ditambah tes logika dan hosted-view pada file dengan coverage rendah:

- `GitPullService`: fast-forward dari bare remote lokal berhasil, pull tanpa upstream gagal, dan branch divergen ditolak tanpa mengubah working file.
- `WordDiffPolicy`: baris sama, rentang perubahan terpisah, Unicode, token sisipan, sisi kosong, batas 256 token, dan fallback di atas batas.
- `DiffLinePairingPolicy`: baris konteks, pasangan hapus/tambah, baris tanpa pasangan, jumlah tambahan/penghapusan yang berbeda, serta input kosong.
- Hosted AppKit/SwiftUI: pemasangan dan pembaruan `ReadOnlyTextView` dan `PDFKitView`, permintaan scroll, gambar nomor baris, halaman Settings, siklus hidup toast, dan tombol pemulihan repo.

Tes Git memakai repositori sementara dan bare remote lokal, tanpa mengakses jaringan. Run penuh scheme `Gridline` di Xcode GUI lulus **101 tes, 0 gagal**. Laporan Xcode `Test-Gridline-2026.10.26_13-39-03-+0700.xcresult` mengukur:

- `Gridline.app`: **8.453 / 11.342 baris executable (74,53%)**.
- `Gridline/Models` + `Gridline/Support`: **2.575 / 2.819 (91,34%)**, dijumlahkan dari baris executable per file.
- `GitPullService.swift`: **12 / 12 (100%)**.
- `WordDiffPolicy.swift`: **93 / 94 (98,9%)**; `DiffLinePairingPolicy.swift`: **31 / 31 (100%)**.
- `ReadOnlyTextView.swift`: **87 / 87 (100%)**; `LineNumberRulerView.swift`: **66 / 70 (94,3%)**.
- `GridlineSettingsView.swift`: **73 / 80 (91,2%)**; `PaneToastView.swift`: **61 / 63 (96,8%)**.
- `PDFKitView.swift`: **14 / 14 (100%)**.

Persentase app mencakup seluruh source Swift app, termasuk view SwiftUI/AppKit. File logic terendah berikutnya dalam Models/Support adalah `RepoOpener.swift` (64,3%), `LocalNotificationService.swift` (64,7%), dan `TCCPermission.swift` (73,7%). Baris yang tersisa di `RepoOpener` adalah pembukaan modal `NSOpenPanel`; `LocalNotificationService` menyisakan adapter sistem notifikasi dan jalur yang memakai `UNUserNotificationCenter`. Keduanya membutuhkan batas integrasi terisolasi atau UI/system test untuk dibuktikan aman.

File app dengan coverage terendah setelah hosted-view batch ini adalah `WorktreeBranchPickerView.swift` (32,4%), `ContentView.swift` (41,7%), dan `NestedPaneSplitView.swift` (57,8%). Ini masih perlu tes UI/runtime untuk menaikkan app-wide coverage.

Angka coverage app bervariasi antar-run GUI karena jalur view/runtime yang ikut berjalan; gunakan hitungan baris dan cakupan yang sama saat membandingkan. `xcodebuild test` CLI dicoba, tetapi berhenti sebelum kompilasi saat sandbox menolak penulisan cache manifest SwiftPM dan module cache Clang di luar workspace. Hasil 101/101 berasal dari Xcode GUI. Coverage 100% app-wide belum tercapai; pekerjaan berikutnya tetap menutup file coverage terendah lalu memperluas pengujian UI/runtime.
