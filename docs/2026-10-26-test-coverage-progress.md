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

## Lanjutan: Worktree branch picker (2026-10-26)

`WorktreeBranchPickerView` kini memakai `WorktreeBranchPickerModel` untuk state daftar/carian, pemuatan branch, pembukaan worktree, dan pemetaan error. Tes model menggunakan repositori Git dan worktree sementara. Tes model dan hosted-view baru lulus pada laporan terbaru.

Laporan Xcode GUI `Test-Gridline-2026.10.26_13-51-04-+0700.xcresult` mencatat 106 tes, **105 sukses dan 1 gagal**. Kegagalan yang tercatat adalah `ZeroCoverageViewTests.testFileViewerContentBodyCoversEveryLoadState()`, dengan pesan test runner keluar sebelum rangkaian selesai. Karena itu run ini bukan suite hijau dan perlu diulang setelah menelusuri kegagalan tersebut.

Coverage dalam target app pada run itu:

- `Gridline.app`: **8.720 / 11.380 baris (76,63%)**.
- `WorktreeBranchPickerView.swift`: **373 / 408 (91,42%)**; seluruh metode model tercakup, kecuali `open(...)` yang 26/27 (96,3%).
- File terendah berikutnya: `ContentView.swift` **541 / 1.272 (42,53%)**, `FileViewerContentView.swift` **97 / 170 (57,06%)**, dan `NestedPaneSplitView.swift` **148 / 256 (57,81%)**.

Percobaan CLI dengan DerivedData dan package cache diarahkan ke `/private/tmp` tetap berhenti saat SwiftPM mencoba menulis `swiftterm.dia` ke `~/Library/Caches/org.swift.swiftpm/manifests/ManifestLoading` dan ditolak sandbox. Angka di atas berasal dari laporan GUI, bukan dari run CLI tersebut. Coverage app-wide 100% belum tercapai.

## Tes split-grid berikutnya

Dua tes `NestedPaneSplitViewTests` ditambahkan untuk membangun grid 2×2, menjaga controller pane saat konten diperbarui, membentuk ulang grid saat pane disembunyikan/dimunculkan, melaporkan fraksi divider, dan melepas observer. File `CoreLogicTests.swift` dan `GitMetadataRefreshTests.swift` lolos `swiftc -typecheck` terhadap modul Debug yang tersedia. Tes baru belum dijalankan oleh XCTest; angka coverage 76,63% di atas tidak memasukkan cakupan dari tes ini.

## Verifikasi dan tes tambahan (2026-10-26)

Run penuh terbaru di Xcode GUI lulus **122 tes, 0 gagal** (54,203 detik), termasuk dua tes split-grid dan seluruh tes tambahan pada `CoreLogicTests.swift` serta `GitMetadataRefreshTests.swift`. Ini menggantikan catatan run 106 tes yang gagal dan status “belum dijalankan” pada bagian sebelumnya; kegagalan lama tidak muncul kembali.

Coverage dari `Test-Gridline-2026.10.26_14-22-36-+0700.xcresult`:

- `Gridline.app`: **9.004 / 11.443 baris executable (78,69%)**.
- `GridlineTests.xctest`: **3.433 / 3.481 baris executable (98,62%)**; angka ini khusus target test dan bukan coverage aplikasi.

Tambahan tes mencakup kebijakan keputusan saat jumlah pane dikurangi, pilihan branch perbandingan, filter Quick Switcher, edge case layout/state, serta refresh dan snapshot metadata Git. Coverage aplikasi pada run ini masih di bawah target 80%; hasil unit test hijau tidak membuktikan seluruh UI/runtime atau integrasi OS.
