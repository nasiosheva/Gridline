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

## Ukuran teks terminal

Bar tab terminal menyediakan tombol kecil untuk memperkecil dan memperbesar teks 1 pt per klik, dengan batas 9–24 pt. Ukuran disimpan di preferensi aplikasi dan langsung diterapkan ke seluruh tab terminal yang terbuka tanpa membuat ulang shell, termasuk tab pada pane yang sedang tersembunyi. Tab baru memakai ukuran terakhir. Label aksesibilitas dan tooltip tersedia dalam bahasa Indonesia dan English.

## Ukuran teks diff

Toolbar diff menyediakan menu untuk memperbesar, memperkecil, dan mengatur ulang ukuran teks. Preferensi ini terpisah dari terminal, berlaku untuk daftar file dan isi diff di semua pane, dan tersimpan antarsesi. Gutter nomor baris ikut melebar sesuai font agar nomor tetap terbaca. Viewer file tidak ikut berubah. Copy menu tersedia dalam bahasa Indonesia dan English.

Pemeriksaan sintaks Swift, pemeriksaan tipe preferensi, validasi JSON dan kunci lokalisasi, serta `git diff --check` berhasil. Build Xcode berhenti saat resolusi paket karena sandbox menolak cache SwiftPM/Clang di direktori pengguna; pemeriksaan tipe seluruh proyek lewat `swiftc` juga terhalang server macro SwiftUI dalam sandbox. Tampilan aplikasi belum diuji langsung.

## Gulir horizontal diff

Isi diff kini dapat digulir horizontal dan vertikal. Baris kode serta header hunk tetap satu baris pada semua ukuran font diff. Lebar konten dihitung dari file diff aktif; mode split menggunakan lebar kolom yang sama untuk seluruh pasangan baris agar pemisah kolom tidak bergeser. Daftar file, pemilihan file, navigasi hunk, dan sesi terminal tidak diubah.

Lebar baris terpanjang disimpan sementara selama isi diff tidak berubah, sehingga perpindahan hunk dan resize pane tidak memindai ulang seluruh baris. Pemeriksaan parser Swift dan `git diff --check` berhasil; verifikasi build serta tampilan Xcode masih pending karena batasan sandbox yang sudah dicatat di atas.

## Uji GUI gulir terminal

Build Debug yang lebih baru daripada perubahan source dibuka dengan empat pane. Pada tab sementara, `seq` menghasilkan 10.000 baris dan Python menghasilkan 2.000 baris secara bertahap. Riwayat dapat digulir dan langkah gulir kecil mengubah posisi scrollbar secara konsisten. Ketika output bertahap berlangsung sambil riwayat ditahan, tangkapan layar sempat menunjukkan area terminal kosong sampai scrollbar digerakkan lagi. Belum ada pengukuran frame time atau CPU, sehingga status kelancaran gulir belum terkonfirmasi. Tab uji ditutup dan layout empat pane dikembalikan.

## Uji ulang redraw terminal saat membaca scrollback

Build Debug Xcode berhasil. Dengan output bertahap, viewport digeser ke tengah scrollback sementara output masih berjalan. Teks sempat terlihat, tetapi beberapa tangkapan layar berikutnya kembali menunjukkan area terminal kosong; menggeser scrollbar menggambar teks lagi. Baik invalidasi penuh maupun `displayIfNeeded()` yang dikoaleskan pada main queue tidak mencegah gejala. Pengaman tambahan di `GridlineTerminalView` dibuang karena tidak memperbaiki hasil dan berisiko menambah kerja render. Tab uji ditutup; satu shell idle tersisa. Akar masalah render belum terkonfirmasi.

Uji lanjutan scrollback terminal: perubahan redraw yang dikoaleskan khusus setelah callback scroll juga tidak mencegah layar kosong saat output terus masuk, sehingga patch tersebut dibuang. Renderer Metal SwiftTerm dicoba sementara dan menunjukkan gejala kosong yang sama setelah interaksi scrollbar; renderer default tetap dipakai. Reproduksi terkontrol memakai 180 baris output bertahap: setelah scrollback terlihat, area terminal kembali kosong ketika stream berlanjut; menekan Page Up menggambar riwayat lagi. Kedua tab uji ditutup dan satu shell idle dipertahankan. Akar masalah masih terbuka.

Percobaan tambahan `terminal.updateFullScreen()` pada callback scrollback juga tetap mereproduksi area kosong selama stream aktif. Patch ini dibuang. Xcode berhasil build dengan patch percobaan; kode terminal kembali ke baseline. Sesi uji dihentikan dan tab sementara ditutup.
