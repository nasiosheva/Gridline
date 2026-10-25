# Perluasan unit test (2026-10-25)

Scheme `Gridline` mengaktifkan code coverage dan target `GridlineTests` diperluas untuk menguji jalur logika yang sebelumnya belum tercakup. Test baru meliputi:

- Parsing dan resolusi link terminal, termasuk path di luar repo, basename ambigu, suffix baris/kolom, dan file tersembunyi.
- `FileLoader`, `FileViewerTab`, status isi viewer, kebijakan ukuran diff, status Git, serta preferensi terminal/diff.
- Bentuk grid, operasi slot, assignment repo, fokus, mode pane, divider, dan kompatibilitas Codable pada `PaneLayout`.
- Pemulihan/persistensi `AppStateStore`, recent repo, pemilihan pane, comparison selection, dan debounce penyimpanan divider.
- Status staged/unstaged/untracked, pemilihan file, perbandingan branch, dan callback konsumsi branch awal pada `RepoDiffStore`.
- Batas path TCC, pesan error pembukaan repo, dan konstruksi body view untuk jalur viewer/picker tanpa menekan aksi UI eksternal.
- Alur `GitWorktreeService`, termasuk sorting branch, pembuatan dan pembukaan ulang worktree, pemulihan metadata worktree yang foldernya hilang, serta jalur error path/repository.

Verifikasi Xcode GUI terakhir menjalankan seluruh 48 test dengan 0 kegagalan. Snapshot coverage Xcode yang terukur sebelum delapan test model/viewer terakhir ditambahkan menunjukkan `Gridline.app` 51,8% dari 10.429 executable lines. Coverage belum diukur ulang untuk suite 48 test, sehingga 51,8% dicatat sebagai snapshot, bukan angka final. Target rata-rata 80% belum dapat dikonfirmasi; view/AppKit yang perlu interaksi runtime, notifikasi, clipboard, atau izin sistem belum seluruhnya diuji.

Percobaan `xcodebuild test` dari CLI masih berhenti saat SwiftPM menulis cache/diagnostik di luar workspace. Hasil 48/48 berasal dari scheme Xcode GUI pada destination My Mac.

## Prioritas coverage terendah

Profil Xcode terakhir yang tersedia menunjukkan coverage source Gridline 52,92% line coverage setelah dependency SwiftTerm dikeluarkan. `GitWorktreeService` masih 0% pada profil lama, sehingga empat test integrasi Git sementara ditambahkan sebagai prioritas pertama. Empat test tambahan menutup perilaku `TopAreaStore`, pesan diagnostik, dan state idle `TerminalTab`. Tiga test berikutnya menutup status `RepoWorkStatus`, reuse registry viewer, serta lifecycle `RepoSessionStore`. Tiga test lanjutan menutup clipboard, pembuatan konten notifikasi/ruler, dan factory `PDFKitView`. Empat test berikutnya menutup metrik layout diff, rename/binary/untracked parsing, file diff per group, dan perbandingan branch. Satu test tambahan membangun cabang body diff, viewer, dan header pane. Batch terakhir menutup metadata `Repo`, parsing OSC 7, eksekusi `GitProcess`, dan lifecycle `RepoSession`. Suite bertambah dua puluh delapan test dari baseline 48 test menjadi 76 test; profil perlu diukur ulang melalui Xcode setelah suite terbaru dijalankan. Angka 52,92% adalah baseline analisis, bukan hasil setelah patch ini.

Pemeriksaan tipe Swift 5 untuk dua file test dan parse source berhasil. `xcodebuild test` dari CLI masih berhenti sebelum kompilasi karena SwiftPM mencoba menulis cache manifest di luar sandbox; integrasi worktree juga tidak dapat dijalankan di sandbox karena Application Support dibatasi.

Batch lanjutan menambahkan coverage untuk helper clipboard, pembuatan isi notifikasi selesai/gagal, setup `LineNumberRulerView`, metadata `Repo`, parsing OSC 7, `GitProcess`, dan lifecycle `RepoSession`. `LocalNotificationService` kini memisahkan pembentukan konten dari pengiriman sistem agar bagian yang deterministik dapat diuji tanpa izin notifikasi. Suite saat ini berisi 76 test function.

Target rata-rata 80% belum dapat dikonfirmasi sampai suite dijalankan ulang dengan coverage Xcode. Profil lama tidak mencerminkan test-test baru ini.

## Hasil ukur ulang Xcode GUI

Scheme **Gridline**, destination **My Mac**, menjalankan 76 test dengan 0 kegagalan. Laporan `Test-Gridline-2026.10.25_22-14-28-+0700.xcresult` mencatat target `Gridline.app` 6.983 dari 10.433 executable lines (66,93%); `GridlineTests.xctest` 2.111/2.163 (97,60%). Angka agregat 72,20% juga memasukkan test target dan tidak dipakai sebagai coverage app. Profil Xcode terbaru tidak menunjukkan file app dengan 0% coverage.

Pengujian bertambah dari 63 ke 76 test. Empat test worktree, helper clipboard, pembuatan konten notifikasi, setup ruler, factory PDF, dan batch view yang dirender lewat `NSHostingView` sekarang masuk ke run terukur. CLI tetap tidak menjadi jalur verifikasi yang dapat diulang di sandbox: resolusi SwiftPM gagal saat menulis cache/diagnostik di direktori pengguna. Jalur Xcode GUI berhasil.

Prioritas terendah setelah file 0% tertutup: `GridlineSettingsView` 2,5%, `ReadOnlyTextView` 4,6%, `LocalNotificationService` 15,2%, dan `LineNumberRulerView` 15,7%. Ini persentase berkas dari run di atas; bagian yang memerlukan interaksi AppKit, permission sistem, atau pengiriman notifikasi perlu diuji lewat batas injeksi atau tes GUI yang sesuai, bukan dengan menaikkan angka melalui assertion tanpa perilaku.

Hasil test mencatat warning SwiftUI karena sejumlah test lama membaca `body` langsung tanpa memasang view ke hierarchy, sehingga `State`/`FocusState` tidak aktif. Test view baru memakai `NSHostingView` untuk state/layout yang memerlukannya. Pisahkan pembersihan warning lama dari cakupan fitur, dan jangan menganggap build/test lulus sebagai bukti interaksi UI penuh.

## Pengukuran logic saja

Setelah fokus dialihkan ke unit test logika, test berbasis render `NSHostingView` yang ditambahkan pada batch sebelumnya dikeluarkan. Run Xcode GUI terbaru (`Test-Gridline-2026.10.25_22-28-30-+0700.xcresult`) lulus dengan 75 test dan 0 kegagalan. Coverage pada berkas `Gridline/Models` dan `Gridline/Support` adalah 2.774 dari 3.137 executable lines (88,43%). Coverage seluruh target `Gridline.app` adalah 5.839 dari 10.453 lines (55,86%); angka ini mencakup UI/AppKit yang memang tidak menjadi fokus batch ini. Jadi ambang 70% tercapai untuk lingkup logic Models/Support, tetapi belum untuk seluruh app.

CLI `xcodebuild test` tetap terhalang penulisan cache SwiftPM di luar workspace; angka terukur ini berasal dari Xcode GUI. Cakupan Models/Support dihitung dengan menjumlahkan baris executable dan covered per berkas pada laporan `xccov`, tidak dengan merata-ratakan persentase tiap berkas.

## Fokus berkas dengan coverage rendah

Run Xcode GUI `Test-Gridline-2026.10.25_22-46-47-+0700.xcresult` lulus dengan 85 test dan 0 kegagalan. Coverage `Models` + `Support` naik menjadi 2.924/3.158 (92,59%); target app naik menjadi 5.989/10.474 (57,18%). Test tambahan fokus pada lifecycle `TerminalTab`/`RepoSession`, resolusi link terminal, hasil pemilihan folder, registry viewer, dan resolusi direktori Git worktree.

Ambang 99% tidak dapat dicapai untuk seluruh lingkup `Models` + `Support` dengan unit test logika saja selama laporan tetap memasukkan adapter sistem/UI: 18 baris layanan notifikasi sistem, 10 baris pembukaan `NSOpenPanel`, dan 5 baris pembukaan Pengaturan Sistem tidak dijalankan tanpa interaksi atau efek sistem. Bahkan jika semua baris lain tercakup, batas atas lingkup ini sekitar 98,95%. Coverage seluruh app lebih rendah karena ribuan baris SwiftUI/AppKit juga belum diuji; 99% app-wide membutuhkan cakupan UI/runtime.
