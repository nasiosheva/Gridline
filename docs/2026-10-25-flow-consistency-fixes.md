# Perbaikan konsistensi alur Gridline — 2026-10-25

## Perubahan

- Konfirmasi tutup repo menghitung perintah terminal aktif, sama seperti aksi tutup semua repo. Shell zsh yang idle tidak lagi memicu konfirmasi. Sesi terminal tetap berjalan setelah repo dilepas dari pane.
- Repo yang dipilih dari daftar repo terbaru atau quick switcher sekarang diarahkan ke pane tujuan dengan perilaku swap yang sama seperti pemilih repo di header.
- Pemulihan pane worktree menggunakan penempatan yang sama. Jika branch/worktree sudah terbuka di pane lain, kedua penempatan ditukar sehingga pane yang sedang dipulihkan menampilkan worktree terpilih.
- `apps-spec.md`, `TASK.md`, dan `DECISIONS.md` diperbarui untuk mencatat perilaku tersebut.

## Menu Aksi Workspace

Menu toolbar Aksi Workspace yang ditambahkan pada awalnya dipindahkan ke menu bar macOS setelah pengguna meminta area pane yang lebih tinggi. Baris toolbar di dalam jendela dihapus. Menu **Repository** kini memuat **Tampilkan Satu Repo…** dan fungsi repository lainnya; menu **Pane** memuat pilihan jumlah pane dinamis. Perubahan layout tetap menghormati konfirmasi untuk perintah aktif sebelum Quick Switcher dibuka. Pane kosong tetap memiliki tombol **Buka Repo…**.

README dan dokumentasi proyek diperbarui. Build dan test tetap tidak dijalankan.

## Navigasi keyboard pada daftar diff

Daftar diff sebelumnya tidak memiliki handler ↑/↓; ketika terminal masih first responder, shell menerima tombol itu sebagai history. Daftar diff kini menangani ↑/↓ saat list fokus, sedangkan terminal tetap memakai tombol tersebut untuk history. ⌥↑/⌥↓ tetap berpindah hunk dari list atau area diff, dan perpindahan file mengikuti filter yang tampak.

Area diff kini juga mengambil fokus saat diklik. Monitor event keyboard lokal mengabaikan flag `.numericPad` bawaan tombol panah, lalu menangkap ↑/↓ sebelum event mencapai terminal dan memilih file yang terlihat; ⌥↑/⌥↓ berpindah hunk. Klik daftar file mengaktifkan monitor secara langsung, dan monitor dilepas saat pane diff tidak tampil.

Saat area diff fokus, daftar file menampilkan garis aksen dan petunjuk `↑↓ File · ⌥↑↓ Hunk`. File terpilih memakai latar serta garis aksen agar berbeda dari hover abu-abu. Petunjuk tersedia dalam bahasa Indonesia dan English di katalog lokalisasi.

Build dan test tidak dijalankan.

## Peringatan perubahan selection saat render

Binding selection pada daftar diff sebelumnya memanggil `RepoDiffStore.select` secara sinkron. Karena method itu segera mengubah `@Published selectedFileID`, SwiftUI melaporkan “Publishing changes from within view updates”. Binding kini menunda pemanggilan model sampai siklus update view selesai.

Build dan test tidak dijalankan.

## Isolasi Swift 6 dan capture terminal

Helper pembacaan file, resolusi link terminal, dan hitung baris file untracked ditandai `nonisolated` agar tetap berjalan dari worker tanpa menyentuh state `MainActor`. Hasil pembacaan file dan target link diberi batas `Sendable` untuk perpindahan hasil worker ke UI. Buffer keluaran Git tetap memakai lock dan kini bertipe nonisolated, sehingga callback pembacaan pipe dapat mengambil teks dengan aman. Handler buka file pada pane mempertahankan `TopAreaStore` secara konsisten, dan aksi Find memakai selector AppKit bertipe.

Build dan test tidak dijalankan sesuai instruksi.

## Verifikasi

- Pemeriksaan source mengonfirmasi seluruh entry point memilih repo melalui `AppStateStore.openRepo(id:in:)`.
- Pemeriksaan source mengonfirmasi pemulihan worktree meneruskan `replacingPaneID` dan service dapat mengembalikan worktree yang sudah ada.
- `swiftc -frontend -parse` pada file Swift yang berubah, validasi JSON katalog lokalisasi, dan `git diff --check` berhasil.
- Build Debug dicoba, tetapi terhenti saat resolusi paket sebelum kompilasi: akses DNS GitHub tidak tersedia dan cache manifest SwiftPM di luar workspace tidak dapat ditulis dari sandbox. Uji GUI belum dijalankan.
