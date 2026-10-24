# Pintasan Bersihkan Riwayat Terminal — 2026-10-24

Gridline menyediakan ⌘K untuk membersihkan riwayat scrollback tab terminal aktif di pane aktif. Pada layar shell biasa, aksi ini juga mengirim Ctrl+L melalui PTY agar prompt digambar ulang pada layar kosong. Saat program memakai alternate screen (misalnya Codex), Gridline mempertahankan tampilan program aktif dan hanya membuang riwayat scrollback buffer utama.

Pintasan muncul di menu aplikasi dan dialog bantuan pintasan. Label UI memakai katalog `Localizable.xcstrings` untuk bahasa Indonesia dan English.

Typecheck seluruh 49 file Swift berhasil dengan dua warning yang sudah ada di `GridlineApp.swift` dan `RepoPaneView.swift`. Build dan launch lewat Xcode GUI berhasil. Build CLI tetap terhalang penulisan cache SwiftPM di luar workspace.

## Penghapusan tombol jalankan ulang

Ikon panah melingkar pada chip tab ternyata mengirim ulang command terakhir ke shell. Karena aksi tersebut dapat mengulang efek samping command, tombol dan mekanisme pencatatan command di shell integration dihapus. Chip tab kini hanya menampilkan nama tab dan aksi tutup.

## Konfirmasi tutup tab

Tombol **×** meminta konfirmasi hanya jika hook zsh menandai command sedang berjalan. Hook memakai `preexec`/`precmd` untuk menulis status `running`/`idle` ke file privat tanpa merekam command. Shell idle di prompt ditutup tanpa dialog; shell selain zsh memakai fallback konservatif dan tetap meminta konfirmasi.

## Fokus setelah membuka tab terminal

Saat tab baru menjadi aktif, `TerminalHostView` meminta view terminal menjadi first responder setelah pemasangan SwiftUI. Permintaan fokus dicoba ulang sebentar bila view/window belum siap, dan dibatalkan jika pane tidak lagi aktif atau tab sudah berganti.

## Hasil smoke test GUI — 2026-10-24

- Menambah tab terminal lalu mengetik `echo GRIDLINE_FOCUS_OK` tanpa klik tambahan menghasilkan output di tab baru.
- Tab zsh yang kembali ke prompt setelah command selesai tertutup tanpa dialog.
- Saat `sleep 45` berjalan, menekan **×** menampilkan konfirmasi. Memilih **Batal** mempertahankan tab; setelah `Ctrl+C`, tab tertutup tanpa dialog.
- Pada probe PTY terpisah yang memakai profil zsh hasil Gridline, status berubah `idle` → `running` saat Python REPL aktif → `idle` setelah `exit()` normal.
- Skenario Codex diuji langsung di aplikasi dengan sesi baru yang terpisah dari task aktif: saat TUI Codex terbuka, **×** menampilkan konfirmasi; setelah `/exit` mengembalikan prompt zsh, **×** menutup tab tanpa dialog. Tab uji ditutup dan pane dikembalikan ke keadaan semula.
- ⌘K pada prompt zsh membuang output lama, mempertahankan prompt, dan command berikutnya tetap dapat diketik.
- Pada build sebelum perbaikan alternate screen, ⌘K saat Codex TUI aktif mengosongkan tampilan Codex. `TerminalTab.clearTerminal()` kini tidak mengirim Ctrl+L saat SwiftTerm melaporkan alternate screen aktif. Build Xcode GUI setelah perubahan berhasil. Uji GUI pada salinan build terpisah menunjukkan TUI Codex tetap tampil setelah ⌘K, `/exit` tetap bekerja, dan ⌘K di prompt zsh kembali membersihkan layar tanpa menghapus prompt. Proses Gridline lama beserta sesi terminalnya tidak dihentikan.
- Smoke test beban mengeluarkan 5.000 baris (~85 karakter per baris) sampai penanda akhir. Uji berikutnya mengeluarkan 2.000 baris bertahap; pane dapat di-resize saat output berjalan, lalu penanda akhir dan prompt muncul. Perpindahan tab setelahnya tetap responsif. Ini belum merupakan pengukuran latensi, memori, atau uji durasi panjang.
- Pada salinan build baru, 2.000 baris (~85 karakter per baris) dengan jeda 5 ms per baris selesai dalam 12,32 detik menurut `time.perf_counter()` di Python. Saat output berjalan, perpindahan ke tab lain dan kembali diterima; masing-masing panggilan klik otomasi memerlukan 267 ms dan 263 ms. Angka klik termasuk overhead alat otomasi, sehingga bukan latensi murni Gridline. Tidak ada crash atau output terputus pada uji ini.

## Warna terminal — 2026-10-24

Terminal memakai latar hitam, teks terang, dan palet ANSI 16 warna dengan aksen hijau, biru, kuning, merah, cyan, dan magenta. Palet dikonfigurasi terpusat di `Gridline/Support/TerminalAppearance.swift` dan diterapkan ke setiap terminal SwiftTerm. ANSI 256/truecolor tetap diproses oleh SwiftTerm, jadi warna aplikasi interaktif tidak diratakan ke palet 16 warna. Prompt zsh bawaan menampilkan path dalam hijau; prompt dan `LSCOLORS` yang sudah diatur pengguna tetap dipertahankan.

## Clear Recent — 2026-10-24

Menu **Repo Terakhir** pada pane kosong menyediakan **Clear Recent**. Daftar tiga repo terakhir kini disimpan terpisah dari seluruh repo tersimpan supaya membersihkan riwayat tidak melepaskan repo dari pane atau menghapus data. State versi sebelumnya dimigrasikan dari tiga entri terakhir yang tersimpan. Label dan keadaan daftar kosong tersedia dalam Bahasa Indonesia dan English.
