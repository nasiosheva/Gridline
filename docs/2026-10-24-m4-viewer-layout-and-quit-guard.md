# Implementasi M4 — 2026-10-24

## Scope

Implementasi ini mengerjakan checklist 16–21: pilihan viewer berdampingan dengan diff per pane, konfirmasi saat keluar ketika terminal masih menjalankan proses, quick switcher repo/file dengan pencarian, warna identitas repo, menu/overlay pintasan, mode fokus diff, status kerja repo/notifikasi, filter diff, drag folder, perbandingan branch, pengaturan scrollback, dan ekspor diagnostik.

Permintaan tambahan UI sederhana: toolbar memakai satu menu **Layout** untuk tambah pane dan preset; header repo memakai satu menu **•••** untuk maksimalkan, mode terminal, tutup repo, dan tutup pane. Pane kosong menjadikan **Buka Repo…** aksi utama dan repo terakhir sebagai menu. Tutup pane mempertahankan repo dan sesi terminal di registry, tidak menutup pane terakhir, dan memilih tetangga jika pane aktif ditutup.

## Perubahan

- `PaneSlot.viewerAsSidePanel` menyimpan preferensi panel samping secara Codable. Nilai default `false` menjaga tampilan tab yang sudah ada.
- `TopAreaView` memberi tombol untuk berpindah antara mode tab dan mode side panel. Dalam mode side panel, Diff dan viewer file tampil berdampingan saat tab file dipilih.
- `RepoSessionStore` menghitung shell yang masih hidup. Perintah Quit dan ⌘Q langsung keluar jika tidak ada proses; jika ada, dialog menampilkan jumlah proses dan tombol Batal ditetapkan sebagai aksi default.
- ⌘P membuka sheet pencarian dengan bagian Repo dan File terbuka. Memilih repo memfokuskannya atau menempatkannya di pane aktif; memilih file juga membuka tab viewer yang sesuai.
- Warna identitas stabil ditampilkan di header pane dan hasil repo quick switcher. Menu Repo, Pane, dan Bantuan menyediakan tindakan dan pintasan; ⌘/ menampilkan overlay pintasan. Mode fokus diff menyembunyikan daftar file, dengan aksi pulihkan.
- Checklist 20: header menampilkan status idle/berjalan/perlu perhatian; proses selesai meminta izin notifikasi lalu memberi konteks nama repo/tab; panel diff memfilter file yang berubah dalam sepuluh menit dan menyembunyikan file besar; folder dapat diseret ke jendela; panel diff membandingkan working tree dengan branch lokal lain.
- Checklist 21: Settings ⌘, mengatur batas scrollback dan mengirim perubahan ke terminal yang sudah berjalan. DiagnosticLog menyimpan maksimal 500 kejadian tanpa path repo, isi file, atau isi terminal. Ekspor log memuat metadata kejadian dan versi Gridline/macOS/Git. Sparkle tidak ditambahkan karena D24 belum dikonfirmasi.
- Pembaruan 2026-10-24: fitur tombol jalankan ulang perintah terakhir dihapus setelah evaluasi UX; ikon reload pada tab tidak boleh mengeksekusi ulang command.
- `TASK.md`, `apps-spec.md`, dan `CLAUDE.md` memuat status implementasi. Checklist 16–21 tetap pending sampai build GUI dan smoke test dapat diverifikasi.

## Batas Verifikasi

Kompilasi dan link executable arm64 dari seluruh 48 file Swift berhasil lewat `swiftc -emit-executable -disable-sandbox` dengan object SwiftTerm yang sudah dibangun sebelumnya; outputnya Mach-O arm64. Proses ini menemukan dan memperbaiki urutan inisialisasi watcher perintah di `TerminalTab`. Muncul dua warning lama di `RepoPaneView.swift` dan `GridlineApp.swift`. Ini belum menghasilkan bundle app atau membuktikan asset dan perilaku runtime.

Build Xcode penuh tetap terhenti di SwiftPM: upaya awal tidak dapat menulis manifest diagnostic ke `~/Library/Caches`, dan setelah diarahkan ke cache sementara, resolver gagal menerapkan sandbox bersarang. Kompilasi SwiftTerm terisolasi berhenti karena komponen Metal Toolchain belum terpasang (`xcrun` menyarankan `xcodebuild -downloadComponent MetalToolchain`). Percobaan menjalankan bundle smoke terisolasi gagal di Launch Services (`kLSNoExecutableErr`) meskipun binary tersedia; menjalankan binary langsung berakhir `SIGABRT` di AppKit `___RegisterApplication`. Jadi belum ada bukti jendela atau perilaku runtime aplikasi. Checklist 16–21 tetap pending sampai build GUI dan perilaku runtime diperiksa.

Typecheck seluruh source Swift dengan target arm64/macOS 27 berhasil setelah fitur Tutup pane ditambahkan. Tidak ada error; hanya dua warning yang sudah ada di `GridlineApp.swift` (Selector) dan `RepoPaneView.swift` (weak capture), serta diagnostik sandbox dari subprocess compiler. Build Xcode GUI dan smoke test visual masih belum terverifikasi.


## Lokalisasi

- `Gridline/Support/L10n.swift` memusatkan kunci `LocalizedStringResource`; `Gridline/Localizable.xcstrings` menyimpan copy English dan Indonesia.
- Katalog 150 entri mencakup menu, dialog, tooltip, aksesibilitas, viewer, diff, settings, notifikasi, dan heading ekspor diagnostik. Placeholder memungkinkan urutan kalimat berbeda antarbahasa.
- Project mengenali `en` dan `id`; bahasa antarmuka mengikuti bahasa macOS. Belum ada override bahasa dalam aplikasi.
- Nama/path repo, branch, perintah terminal, Git output, dan identifier event diagnostik dibiarkan sebagai data atau metadata teknis.
- Typecheck seluruh source Swift berhasil; pemeriksaan JSON dan placeholder katalog lolos. Build Xcode belum memvalidasi kompilasi katalog karena resolusi SwiftPM gagal menulis cache di home dalam sandbox. Runtime UI belum diverifikasi.

## Warna terminal

- `ShellIntegration` menyalakan `CLICOLOR` untuk sesi zsh dan memberi warna pada prompt bawaan saja. Prompt yang sudah diatur di `.zshrc` pengguna tidak ditimpa.
- SwiftTerm sudah memakai `xterm-256color` dan `COLORTERM=truecolor`, jadi escape sequence warna dari program terminal tetap dirender.

## Stabilitas dan performa terminal

- `RepoSession.addTab()` memasang callback proses sebelum menjalankan shell. PTY yang gagal dibuat sekarang dicatat sebagai `terminal.start_failed`, bukan tertinggal sebagai proses berjalan.
- `TerminalHostView` hanya memindahkan keyboard focus ke terminal pane aktif. Update dari pane lain tidak lagi meminta responder window.
- Saat delegate menerima `applicationWillTerminate`, ia memanggil `terminate()` pada setiap terminal di registry. SwiftTerm mengirim SIGTERM ke shell child; membebaskan objek SwiftTerm sendiri tidak menjamin sinyal itu dikirim.
- SwiftTerm checkout yang dipakai sudah memiliki backpressure pada antrean output: pembacaan PTY berhenti ketika antrean pending melewati 4 MiB dan dilanjutkan saat turun di bawah 1 MiB. Pemrosesan antrean juga dibagi per time slice 4 ms.
- Typecheck source berhasil. Pengukuran beban multi-pane dan smoke test GUI belum dilakukan; build Xcode tetap terkendala penulisan cache SwiftPM di sandbox.
