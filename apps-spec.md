# Gridline: Spesifikasi Workspace Repo, Diff, Terminal, dan Viewer (macOS)

**Nama**: Gridline (nama kerja, belum dicek ketersediaannya di App Store atau sebagai merek dagang)
**Status**: Draft v0.19
**Platform**: macOS, Apple Silicon (arm64)
**Stack**: SwiftUI (dengan AppKit untuk bagian yang butuh kontrol lebih)

## 1. Ringkasan

Apps macOS native untuk membuka beberapa **repository kode (coding project) yang sudah terintegrasi dengan Git** sekaligus, dalam satu jendela. Apps ini tidak dirancang untuk folder biasa tanpa `.git`.

Jendela utama tidak memakai sidebar. Area kerjanya terbagi menjadi **pane** (panel repo) dalam bentuk grid, dengan batas maksimal **4 pane** (2 baris × 2 kolom). Tiap pane menampilkan satu repo lengkap:

- diff perubahan kode,
- viewer file read-only,
- terminal dengan banyak tab.

Tujuan utama adalah **tampilan dan navigasi**, bukan pengeditan kode. Apps ini tidak punya editor. Semua file dibuka dalam mode read-only.

## 2. Tujuan dan Non-Tujuan

**Tujuan**
- Melihat beberapa repo sekaligus, tanpa berpindah jendela atau sidebar.
- Melihat diff, file, dan terminal dari beberapa repo secara bersamaan.
- Menjalankan banyak proses paralel (server, test, agen AI) di terminal.
- Membuka file dari output terminal dengan satu klik.
- Terasa seperti apps macOS asli: ringan, responsif, dan mengikuti konvensi macOS.
- Hemat RAM dan CPU, termasuk saat 4 repo dan banyak terminal berjalan bersamaan (lihat bagian 15).

**Bukan tujuan (versi awal)**
- Mengedit file di dalam apps.
- Debugger, refactoring, language server, atau autocomplete kode.
- Sinkronisasi cloud atau akun pengguna.
- Dukungan platform selain macOS (iOS, Windows, Linux).
- Membuka URL dari terminal.
- Lebih dari 4 pane.

## 3. Platform dan Build

- **Arsitektur**: arm64 (Apple Silicon) saja. Tidak ada build Intel atau universal.
- **Minimum macOS**: macOS 26 (Tahoe) ke atas. Versi ini dipilih agar dapat memakai API SwiftUI dan AppKit terbaru.
- **Bahasa**: Swift, dengan Xcode sebagai toolchain.
- **Sandbox**: App Sandbox tidak aktif. Hardened Runtime aktif. Apps ini untuk pemakaian pribadi, dan dibangun agar bisa menjalankan shell pengguna dan `git` di folder mana pun.
- **Distribusi**: pemakaian pribadi. Dibangun dan ditandatangani dengan Developer ID, dengan notarization. Tidak untuk App Store.

**Lokalisasi**
- Teks antarmuka dikelola terpusat dalam String Catalog `Gridline/Localizable.xcstrings`; kode memakai kunci stabil melalui `Gridline/Support/L10n.swift`.
- Versi awal mendukung Bahasa Indonesia (`id`) dan English (`en`). Bahasa aplikasi mengikuti pilihan bahasa macOS pengguna; belum ada pemilih bahasa di dalam aplikasi.
- Teks dinamis memakai placeholder di katalog supaya susunan kalimat bisa berbeda per bahasa. Nama repo, path, branch, perintah, dan keluaran terminal adalah data pengguna/teknis sehingga dipertahankan apa adanya.

## 4. Layout Utama

Jendela utama tidak punya sidebar. Isinya adalah **grid pane**, dengan gaya yang mirip jendela merge di IntelliJ: beberapa panel kerja berdampingan dalam satu jendela.

**Layar pertama dan pemulihan**

- **Pertama kali dibuka** (belum ada repo tersimpan): grid kosong dengan satu pane berisi tombol **Buka repo** yang jelas.
- **Placeholder pane kosong**: setiap slot kosong menampilkan daftar repo terakhir sebagai tombol. Klik tombol untuk membuka repo itu di slot tersebut. Tombol **Buka repo** tetap tersedia di bawah daftar.
- **Dibuka kembali** (sudah ada repo tersimpan): susunan terakhir dipulihkan, yaitu jumlah pane, repo di tiap pane, dan pane yang aktif. Setiap pane menampilkan diff dan **satu tab terminal** saja, yaitu tab yang aktif saat aplikasi ditutup, dengan shell baru di folder repo.
- Tab terminal tambahan dari sesi sebelumnya **tidak** dipulihkan saat aplikasi dibuka ulang. Ini berlaku untuk setiap repo, termasuk repo yang di sesi sebelumnya punya banyak tab.
- Saat aplikasi ditutup, proses terminal berhenti seperti biasa (bagian 8), sehingga tidak ada yang perlu dipertahankan dari sesi sebelumnya.
- Jika repo di pane sudah tidak ada di disk, pane menampilkan pesan dan tombol "cari ulang folder" (bagian 13).

**Toolbar di atas**
- Tombol **Buka repo** untuk memilih repo lewat dialog folder (`NSOpenPanel`).
- Tombol **Tambah pane** (aktif selama pane kurang dari 4).
- Indikator jumlah pane, misalnya "2 / 4".
- Preset layout: 1 pane, 2 kolom, dan grid 2 × 2. Preset memudahkan pemilihan susunan tanpa menambah pane satu per satu. Default adalah 2 kolom.

**Susunan pane**

| Jumlah pane | Susunan |
|---|---|
| 1 | Satu pane penuh |
| 2 | Kiri dan kanan |
| 3 atau 4 | Grid 2 × 2. Slot yang belum dipakai berupa placeholder "Buka repo" |

Setiap pane punya tiga bagian:

1. **Header pane**: nama repo, nama branch aktif dengan indikator ahead/behind, badge jumlah file berubah, dan tombol **×** untuk menutup repo dari pane itu.
2. **Area atas**: tab diff (selalu ada, tidak bisa ditutup) dan tab viewer file yang dibuka dari terminal. Jika tab tidak muat, tab sisanya masuk menu overflow, dan ⌘P bisa dipakai untuk pindah ke file yang sudah terbuka.
3. **Area bawah**: bar tab terminal dan terminal aktif.

**Perilaku pembagi**
- Pembagi antara area atas dan area bawah dalam satu pane bisa digeser.
- Pembagi antar-pane (vertikal dan horizontal) juga bisa digeser.
- Semua posisi pembagi disimpan dan dipulihkan saat aplikasi dibuka lagi.

**Fokus pane**
- Hanya satu pane yang aktif, ditandai dengan garis tepi berwarna.
- Berpindah fokus antar-pane: ⌘1 sampai ⌘4 langsung ke pane ke-n, atau ⌥⌘ dengan tombol panah ke pane terdekat.
- Perintah dan pintasan (⌘T, ⌘P, ⌘F, dan lain-lain) selalu berlaku untuk pane yang sedang aktif.

**Maksimalkan pane**
- Tombol di header pane (atau ⌃⌘M) memaksimalkan pane aktif ke seluruh jendela. Pane lain tetap berjalan, hanya tidak tampil.
- Tekan lagi untuk kembali ke grid. Posisi pembagi grid tidak berubah.
- Di dalam pane, tombol terpisah (⌥⌘M) memaksimalkan area bawah (terminal) saja, dengan area atas disembunyikan sementara.

**Penanda pane yang butuh perhatian**
- Pane yang tidak aktif menampilkan titik kecil di header jika ada proses yang selesai atau berhenti dengan error sejak terakhir difokuskan.
- Titik berwarna kuning untuk proses selesai, merah untuk error. Hilang saat pane difokuskan.
- Ringkasan di toolbar menampilkan jumlah pane yang butuh perhatian.

**Jendela**
- Ukuran dan posisi jendela utama disimpan.
- Jika monitor yang dipakai dicabut dan posisi jendela berada di luar layar, jendela dipindahkan ke layar utama.

**Batas ukuran**
**Ukuran minimum (dalam point, bukan piksel)**

Ukuran ini diturunkan dari kebutuhan isi apps, bukan dari ukuran layar tertentu:

| Elemen | Minimum | Dasar |
|---|---|---|
| Toolbar | tinggi 52 | Tombol Buka repo, Tambah pane, dan indikator jumlah pane |
| Header pane | tinggi 32 | Nama repo, branch, badge, dan tombol × |
| Area terminal | 80 kolom × 12 baris | Lebar standar terminal, sekitar 640 point dengan font 13 pt |
| Area diff dan viewer | 680 × 200 | Diff split yang masih terbaca |
| Satu pane | 680 × 440 | Header + area atas + area terminal |
| Jendela utama (1 pane) | 680 × 500 | Toolbar + satu pane |
| Jendela (2 pane) | 1.380 × 500 | Dua pane berdampingan dengan pembagi |
| Jendela (3 atau 4 pane) | 1.380 × 940 | Grid 2 × 2 dengan pembagi |

- Pane tidak pernah lebih kecil dari ukuran minimumnya. Pembagi berhenti bergeser di batas ini.
- Jika jendela lebih kecil dari yang dibutuhkan jumlah pane yang ada, pane tidak dihapus. Jendela menampilkan pesan agar diperbesar, dan pane yang tidak muat digulir (scroll).
- Susunan grid 2 × 2 membutuhkan layar yang cukup besar. Di laptop kecil, pengguna sebaiknya memakai 2 pane atau maksimalkan pane.

## 5. Manajemen Repo

**Membuka repo**
- Tombol **Buka repo** atau ⌘O membuka dialog pilih folder (`NSOpenPanel`).
- Repo dibuka di pane yang sedang aktif. Jika pane aktif sudah berisi repo dan jumlah pane masih di bawah 4, repo dibuka di pane baru.
- Option+klik pada repo di daftar repo tersimpan membuka repo di pane baru, walaupun pane aktif masih kosong.
- Repo yang dipilih harus berupa folder kode dengan `.git`. Jika tidak, tampilkan pesan dan tidak membuka repo.
- Folder dokumen atau data biasa tidak termasuk cakupan.
- Repo (atau worktree) yang sudah terbuka di salah satu pane tidak dibuka dua kali. Pane yang berisi repo itu langsung difokuskan.
- Dua worktree dari repo yang sama boleh berdampingan (lihat bagian 17b). Repo dikenali per worktree, bukan per folder induk.
- Setiap repo disimpan sebagai path. Tanpa sandbox, akses ke folder tidak memerlukan bookmark.

**Daftar repo tersimpan**
- Tersedia lewat menu **Repo** dan ⌘P (quick switcher, bagian 10).
- Daftar ini berisi semua repo yang pernah dibuka, termasuk yang sedang tidak tampil di pane.
- Menu **Repo Terakhir** pada pane kosong menampilkan hingga tiga repo terakhir dibuka. **Clear Recent** mengosongkan riwayat ini saja; repo tersimpan, pane terbuka, dan folder di disk tidak terhapus.
- Memilih repo dari daftar membukanya di pane aktif, mengikuti aturan di atas.

**Memilih dan berpindah**
- Setiap pane punya kumpulan tab terminal dan tab viewer sendiri.
- Menutup repo dari pane tidak menghentikan repo lain. Repo itu bisa dibuka lagi kapan saja.
- Sesi terminal repo tetap hidup walaupun repo sudah tidak tampil di pane (bagian 8).

**Menutup repo dari pane**
- Tombol **×** di header pane, atau ⌘⇧W, menutup repo dari pane itu. Repo tetap ada di daftar tersimpan.
- Menutup repo dari pane **tidak menghentikan** proses terminalnya. Sesi tetap berjalan di model repo, dan repo bisa dibuka lagi tanpa kehilangan tab atau scrollback.
- Jika ada proses yang berjalan di tab terminal repo tersebut, konfirmasi tetap ditampilkan untuk memastikan pengguna tidak lupa, tetapi konfirmasi ini hanya menjelaskan bahwa proses masih berjalan, dan tidak menghentikannya.
- Menghentikan proses dilakukan secara eksplisit, lewat tombol **×** di tab terminal.

**Menghapus repo dari daftar tersimpan**
- Menu klik kanan di daftar repo: "Hapus dari daftar". Ini hanya menghapus dari apps, folder dan isinya tidak disentuh.

**Indikator per pane**
- Nama branch aktif dan badge jumlah file berubah di header pane.
- Indikator kecil jika ada proses yang masih berjalan di salah satu tab terminal repo tersebut.

## 6. Panel Diff

Diff berada di area atas setiap pane sebagai tab yang tidak bisa ditutup.

**Isi**
- Daftar file berubah, dikelompokkan menjadi: *staged*, *unstaged*, dan *untracked*.
- Setiap file menampilkan jumlah baris ditambah dan dihapus.

**Tampilan perbedaan**
- Klik file menampilkan diff-nya.
- Baris ditambah berwarna hijau, baris dihapus berwarna merah.
- Nomor baris ditampilkan di kedua sisi (lama dan baru).
- Mode yang bisa dipilih: **split** (dua kolom) atau **unified** (satu kolom). Default mengikuti pengaturan.
- Di pane kecil (grid 2 × 2), mode unified dipakai secara otomatis jika lebar area atas kurang dari batas minimum split.

**Navigasi**
- ↑/↓ memilih file sebelumnya atau berikutnya di daftar file.
- ⌥↑/⌥↓ pindah ke hunk sebelumnya atau berikutnya di dalam diff.

**Pembaruan**
- Diff diperbarui otomatis saat file berubah di disk (FSEvents).
- Perubahan dari luar apps (misalnya agen atau editor lain) langsung terlihat.
- Pembaruan digabung (debounce) agar tidak memanggil Git berulang kali saat banyak file berubah sekaligus.

**Sumber data**
- Diambil dari `git status` dan `git diff` di folder repo, dijalankan lewat `Process`.
- Apps tidak menulis ke repo.

**Catatan implementasi**
- Diff perlu dirender sendiri di SwiftUI/AppKit. Belum ada komponen siap pakai seperti di ekosistem web, sehingga ini bagian dengan usaha pengembangan terbesar.
- Untuk file besar, render bertahap (lazy) agar tetap responsif. Empat pane dengan diff besar sekaligus adalah kasus yang perlu diuji.

## 7. Viewer File (Read-Only)

Viewer berada di area atas pane yang sama dengan diff, sebagai tab.

**Membuka file**
- File dibuka sebagai tab baru di area atas pane tempat terminal asalnya berada, atau dipilih kembali jika sudah terbuka.
- Tab viewer punya tombol **×** untuk menutup. Tab diff tidak bisa ditutup.
- Bisa membuka banyak file sekaligus, masing-masing sebagai tab.

**Tampilan**
- Teks dengan nomor baris dan syntax highlighting.
- Syntax highlighting memakai tree-sitter (lebih akurat) atau Highlightr (lebih cepat dipasang). Pilihan final ditentukan saat pengembangan.
- Jika link dengan nomor baris dipilih (misalnya `app.ts:42`), viewer langsung scroll ke baris itu dan menyorotnya sebentar.
- Pencarian teks di dalam file (⌘F).
- Tidak ada kemampuan mengedit. Kursor hanya untuk memilih dan menyalin teks. Teks dibuat non-editable.

**Batas ukuran**
- Teks: sampai **5 MB**. Di atas itu, viewer menampilkan pesan dan tombol "buka di Finder".
- Gambar dan PDF: sampai **20 MB**.
- Jenis lain: tidak dibuka sebagai teks.

**File non-teks**
- Gambar dan PDF ditampilkan sebagai pratinjau sederhana (`QuickLook` atau `PDFKit`/`NSImage`).
- Jenis file lain (biner) menampilkan pesan "tidak didukung" dan tombol "buka di Finder".

**Pembaruan**
- Jika file berubah di disk, viewer memuat ulang isinya otomatis.
- Jika file dihapus, tab tetap terbuka dengan pesan "file tidak ditemukan".

**Tombol tambahan**
- "Salin path", "Buka di Finder".

## 8. Panel Terminal

Terminal berada di area bawah setiap pane.

**Bar tab**
- Tombol **+** untuk tab baru.
- Tombol **×** di setiap tab untuk menutup.
- Area terminal selalu punya minimal satu tab. Jika tab terakhir ditutup, shell baru otomatis dibuka di folder repo.
- Tombol **+** membuka tab baru dengan shell baru di folder repo, dan langsung difokuskan.
- Tombol **×** menutup tab. Konfirmasi ditampilkan jika hook shell melaporkan ada command aktif; terminal yang idle di prompt dapat ditutup langsung.
- Ganti nama tab dengan double-click.
- Tooltip di setiap tab menampilkan folder kerja dan perintah yang sedang berjalan.
- Nama default mengikuti perintah yang sedang berjalan (misalnya `npm`, `claude`, `vim`), kecuali sudah diganti manual.

**Sesi shell**
- Setiap tab membuka shell asli (zsh atau shell default pengguna) di folder repo.
- Terminal memakai latar hitam, teks terang, dan palet ANSI berkontras tinggi yang konsisten dengan tema Codex; ANSI 256/truecolor dari aplikasi terminal tetap didukung. Untuk zsh, prompt bawaan menampilkan folder kerja hijau jika pengguna belum mengatur prompt sendiri; warna `ls` diaktifkan tanpa mengganti konfigurasi prompt atau variabel warna pengguna.
- Mendukung warna, scrollback, copy-paste, dan program interaktif (vim, htop, git rebase -i).
- Resize pane ikut mengubah ukuran terminal.
- Engine: **SwiftTerm**, yang menangani pseudo-terminal (pty) dan emulasi terminal.

**Persistensi sesi**
- Sesi terminal (proses shell, buffer scrollback, status) disimpan di model per repo, bukan di view. Menutup pane atau memindahkan fokus hanya menyembunyikan tampilan, tidak menghancurkan sesi.
- Saat aplikasi akan berhenti, Gridline secara eksplisit memanggil `terminate()` pada setiap shell PTY; melepas view atau model saja tidak dianggap cukup.
- Fokus keyboard hanya diberikan ke terminal di pane aktif; update SwiftUI pada pane lain tidak boleh memindahkan responder.
- Callback lifecycle terminal dipasang sebelum shell dijalankan. Jika PTY gagal dimulai, sesi harus tercatat gagal dan tidak dibiarkan berstatus berjalan.
- Repo yang sudah ditutup dari pane tetap punya sesi terminal yang berjalan. Saat repo dibuka lagi, semua tab dan isi scrollback-nya tetap utuh.
- Setiap tab dan urutannya dipertahankan per repo.
- Saat aplikasi ditutup (⌘Q, crash, atau restart), proses di dalam terminal ikut dihentikan. Saat dibuka ulang, setiap repo hanya memunculkan satu tab terminal baru, yaitu tab yang aktif saat aplikasi ditutup (lihat "Layar pertama dan pemulihan" di bagian 4).
- Proses yang tetap berjalan walaupun aplikasi ditutup tidak masuk versi awal. Jika dibutuhkan, perlu helper terpisah (mirip `tmux`) yang menjalankan proses dan aplikasi hanya sebagai klien.

**Notifikasi**
- Notifikasi macOS (`UserNotifications`) saat proses lama selesai, jika tab itu tidak sedang aktif.
- Klik notifikasi memfokuskan pane dan tab yang bersangkutan, bukan hanya membuka aplikasi.

## 9. Cmd+Klik: Membuka File dari Terminal

Ini fitur utama apps.

**Deteksi**
- Terminal mendeteksi pola path di output, misalnya:
  - `src/app.ts`
  - `src/app.ts:42`
  - `./README.md`
  - path dalam tanda kutip atau kurung, misalnya `"src/app.ts:42"` atau `(src/app.ts)`
- Saat Cmd ditekan dan kursor di atas path, path ditandai dengan garis bawah dan kursor berubah.
- Deteksi memakai regex yang dijalankan pada baris terlihat, lewat handler klik di SwiftTerm.

**Resolusi path**
- Path relatif diselesaikan terhadap folder kerja tab terminal (cwd).
- cwd dilacak lewat shell integration. Jika belum tersedia, pakai folder repo sebagai patokan.
- Path absolut dipakai apa adanya.

**Perilaku klik**
- Cmd+klik membuka file di tab viewer pada pane yang sama dengan terminal asalnya.
- Jika ada nomor baris, viewer scroll ke baris itu.
- Jika file sudah terbuka, tab yang ada dipilih. Tidak dibuat duplikat.
- Jika file tidak ditemukan, tampilkan pesan singkat. Tidak membuka tab kosong.
- Path di luar repo tetap bisa dibuka, dengan peringatan ringan.
- Jika nama file cocok dengan lebih dari satu file di repo, Cmd+klik menampilkan pilihan, bukan membuka file pertama yang ditemukan.

## 10. Pintasan Keyboard

| Pintasan | Fungsi |
|---|---|
| ⌘O | Buka repo ke pane aktif (atau pane baru jika pane aktif sudah terisi) |
| ⌘P | Quick switcher: buka file, atau pindah ke repo tersimpan dengan mengetik |
| ⌘T | Tab terminal baru di pane aktif |
| ⌘W | Tutup tab aktif (terminal atau viewer). Tidak pernah menutup pane atau repo |
| ⌘⇧W | Tutup repo dari pane aktif (dengan konfirmasi jika ada proses berjalan) |
| ⌘1 sampai ⌘4 | Fokus ke pane ke-n |
| ⌥⌘ + panah | Pindah fokus ke pane terdekat |
| ⌃⌘M | Maksimalkan atau kembalikan pane aktif |
| ⌥⌘M | Maksimalkan atau kembalikan area terminal di pane aktif |
| ⌃1 sampai ⌃9 | Pindah ke tab terminal ke-n di pane aktif |
| ⌘F | Cari teks di viewer atau diff |
| ⌘K | Bersihkan layar dan riwayat scrollback terminal aktif; shell menggambar ulang prompt |
| ↑ / ↓ di daftar file diff | File sebelumnya atau berikutnya |
| ⌥↑ / ⌥↓ di panel diff | Hunk sebelumnya atau berikutnya |
| Cmd+klik | Buka path di terminal |
| ⌘/ | Daftar semua pintasan |

Pintasan bisa diubah di pengaturan. Pintasan memakai `Commands` dan `keyboardShortcut` SwiftUI, supaya muncul di menu bar.

## 11. Pengaturan

Dibuka dengan ⌘, (Settings scene di SwiftUI).

- Font, ukuran font, dan tema terminal. Berlaku langsung tanpa restart.
- Tema terang atau gelap, mengikuti pengaturan macOS atau dipilih manual.
- Mode diff default (split atau unified).
- Pintasan keyboard.

## 12. Persistensi Sesi

Disimpan secara otomatis dan dipulihkan saat aplikasi dibuka:

- daftar repo tersimpan (path),
- susunan pane: jumlah pane, repo di tiap pane, dan pane yang aktif,
- posisi semua pembagi, baik antar-area maupun antar-pane,
- ukuran dan posisi jendela utama,
- status pane yang dimaksimalkan (jika ada),
- tab terminal yang aktif saat aplikasi ditutup (hanya satu per repo, dibuka sebagai shell baru),
- tab viewer yang terbuka per repo.

Konten terminal tidak disimpan. Tab terminal tambahan tidak dipulihkan. Shell baru dibuka di folder repo.

Penyimpanan memakai JSON di `~/Library/Application Support/<nama-apps>/`. Penulisan dilakukan atomik (tulis ke file sementara lalu ganti) supaya file tidak rusak jika aplikasi berhenti mendadak.

## 13. Pemulihan Error

- **Folder repo dipindah atau dihapus**: pane menampilkan ikon peringatan dan tombol "cari ulang folder".
- **Izin TCC ditolak** (folder Desktop, Documents, atau Downloads): pane menampilkan petunjuk untuk membuka Pengaturan Sistem > Privasi & Keamanan, dengan tombol untuk membukanya. Ini tetap berlaku walaupun App Sandbox tidak aktif.
- **Git tidak ditemukan**: panel diff menampilkan pesan dan petunjuk memasang Xcode Command Line Tools.
- **Shell gagal dibuka**: tab terminal menampilkan pesan error dan tombol "buka ulang".
- **File terlalu besar**: pesan sesuai batas di bagian 7.
- **Jendela terlalu kecil untuk jumlah pane**: pesan agar jendela diperbesar, dan pane digulir (bagian 4).

## 14. Pembaruan Aplikasi dan Versi

- **Pembaruan otomatis**: diusulkan memakai Sparkle untuk build di luar App Store. Jika rilis lewat App Store, pembaruan ditangani oleh App Store.
- **Versi format penyimpanan**: file state menyimpan nomor versi. Jika versi lebih baru dari yang didukung, apps tidak menimpa file itu dan memberi tahu pengguna.
- **Migrasi**: jika format berubah, apps mengubah state lama ke format baru sekali, dengan cadangan file lama.

## 15. Catatan Teknis

**Git dan konflik lock**
- Pemantauan diff memakai `git --no-optional-locks status` agar tidak mengambil lock index yang bisa bentrok dengan agen atau perintah lain yang sedang commit.
- Apps tidak pernah menulis ke `.git`. Semua operasi bersifat baca.

**Hemat RAM dan CPU (prinsip utama)**

Apps ini harus tetap ringan walaupun 4 repo, banyak tab terminal, dan beberapa agen AI berjalan bersamaan. Prinsipnya: yang tidak sedang terlihat tidak boleh memakan sumber daya.

- **Diff dan viewer**: hanya pane yang tampil yang merender diff dan teks. Pane tersembunyi menyimpan data mentah, bukan tampilan. Diff besar dirender per bagian (lazy), dan baris di luar layar tidak dihitung.
- **Terminal**: hanya terminal yang terlihat yang menggambar ulang layar. Terminal di tab atau pane tersembunyi tetap memproses output, tetapi tanpa menggambar. Ini membuat proses yang banyak mencetak output tidak membebani CPU.
- **Scrollback**: dibatasi per tab (misalnya 10.000 baris, bisa diatur di pengaturan). Melebihi batas ini, baris terlama dibuang.
- **Pembaruan file dan Git**: FSEvents digabung (debounce), dan `git status` hanya dijalankan ulang untuk repo yang berubah. Repo yang tidak tampil tidak diperbarui secara agresif, cukup dicek saat ditampilkan kembali atau saat ada penanda perhatian.
- **Antrean Git**: jumlah proses Git yang berjalan bersamaan dibatasi (misalnya 2), sisanya antre.
- **Pemakaian daya**: saat aplikasi tidak aktif atau jendela tersembunyi, pembaruan latar belakang dikurangi. Notifikasi dan penanda pane tetap berjalan.
- **Memori gambar dan PDF**: pratinjau dibuang dari memori saat tab ditutup atau pane tidak tampil.
- **Target**: aplikasi idle dengan 4 repo terbuka perlu diukur dan dibandingkan dengan target yang ditetapkan sebelum rilis. Angka targetnya perlu ditentukan saat pengujian.

**Anggaran performa**
- Scrollback per tab dibatasi (misalnya 10.000 baris, bisa diatur di pengaturan).
- Jumlah proses Git yang berjalan bersamaan dibatasi, dengan antrean untuk pembaruan dari beberapa repo.
- Pane yang tidak tampil (karena dimaksimalkan atau tidak fokus) tidak merender ulang diff, tetapi tetap mencatat status proses.
- Anggaran ini diuji dengan 4 pane aktif sekaligus sebelum rilis.

**Aksesibilitas**
- Seluruh navigasi grid bisa dilakukan dengan keyboard (bagian 4 dan 10).
- Header pane, tab, dan tombol diberi label untuk VoiceOver.
- Ukuran font terminal bisa diperbesar, dan layout tidak rusak pada ukuran besar.

**Diagnostik**
- Menu "Ekspor log" menyimpan log dan informasi versi (apps, macOS, dan Git).
- Pesan error menyertakan versi Git dan versi apps.
- Log tidak menyertakan isi file atau isi terminal, hanya metadata kejadian.

**Komponen utama**
- UI: SwiftUI, dengan AppKit (`NSViewRepresentable`, `NSSplitViewController`) untuk grid pane dan pembagi. `NSSplitViewController` bersarang dipakai untuk susunan 2 × 2, karena kontrol SwiftUI bawaan untuk pembagi di macOS masih terbatas.
- Terminal: SwiftTerm
- Link provider: handler klik dan regex di SwiftTerm
- Shell integration: script kecil untuk melacak cwd dan batas perintah
- Git: `Process` memanggil `git status` dan `git diff`
- File watcher: FSEvents
- Syntax highlighting: tree-sitter atau Highlightr
- Penyimpanan: JSON di Application Support, dengan penulisan atomik
- Akses folder: path tersimpan, tanpa App Sandbox
- Notifikasi: UserNotifications

**Model data**
- Repo: identitas, path, dan status (ada atau tidak ditemukan).
- Sesi repo: daftar tab terminal dan tab viewer, tidak terikat ke pane.
- Pane: referensi ke repo yang tampil, dan posisinya dalam grid.

Pemisahan ini penting: sesi terminal hidup di model repo, sehingga pane bisa ditutup atau dipindah tanpa mematikan proses.

**Aturan yang tidak boleh dilanggar saat implementasi**
- Menutup pane, menutup repo dari pane, memaksimalkan pane, atau memindahkan fokus **tidak pernah** menghentikan proses terminal.
- Proses hanya berhenti karena pengguna menutup tab terminalnya secara eksplisit, atau aplikasi ditutup.
- Repo yang tidak tampil di pane tetap menjalankan proses dan tetap mencatat status "selesai" atau "error" untuk penanda pane.

**Pengujian**
- Unit test untuk parser path (Cmd+klik) dan parser diff.
- Unit test untuk logika grid pane (batas 4, susunan 1 sampai 4 pane, dan pemindahan fokus).
- Test manual untuk terminal (vim, htop, resize) di setiap jumlah pane.
- Pengujian integrasi dengan repo contoh yang berisi perubahan staged, unstaged, dan untracked.
- Pengujian worktree: dua worktree dari repo yang sama berdampingan, dengan diff dan sesi terminal masing-masing.
- Pengujian konfirmasi ⌘Q: tombol default harus Batal, dan dialog menyebut jumlah proses yang berjalan.
- Pengujian izin TCC: akses ke folder Desktop, Documents, dan Downloads ditolak, lalu petunjuk muncul dengan benar.

## 15b. UI/UX

**Identitas dan orientasi**
- Setiap repo punya warna identitas kecil yang konsisten, dipakai di header pane dan di daftar repo tersimpan. Di grid 2 × 2, ini membantu mengenali pane tanpa membaca nama.
- Penanda pane (titik kuning dan merah) disertai ikon atau teks singkat, tidak hanya warna, supaya tetap terbaca oleh pengguna yang buta warna.

**Cmd+klik dan pencarian**
- Saat kursor di atas path yang bisa diklik, tampilkan tooltip dengan path absolut yang akan dibuka. Ini mengurangi kebingungan saat path relatif diselesaikan dari cwd.
- ⌘O membuka repo di pane aktif. Option+klik membuka repo di pane baru. Keduanya tidak bersaing karena aturannya jelas di bagian 5.
- Hasil ⌘P dipisah per jenis (repo dan file) dalam satu daftar, dengan label jenis di setiap baris.

**Pesan dan konfirmasi**
- Pesan error ditampilkan inline di area terkait, misalnya file tidak ditemukan atau Git tidak tersedia. Modal hanya dipakai untuk tindakan yang menghentikan proses.
- Dialog penutupan tab atau repo menyebut nama proses yang sedang berjalan, dan tombol default adalah Batal.
- Setelah repo ditutup dari pane, toast singkat "Repo ditutup · Buka lagi" muncul beberapa detik. Karena sesi tetap hidup, toast ini menegaskan bahwa tidak ada yang hilang.

**Pintasan dan bantuan**
- Semua pintasan di bagian 10 muncul di menu bar macOS.
- ⌘/ menampilkan daftar pintasan yang sama dalam bentuk overlay.
- Grid kosong menampilkan petunjuk singkat ("⌘O buka repo, ⌘P cari"), yang hilang setelah repo pertama dibuka.

**Tampilan diff dan viewer**
- Selain maksimalkan pane, ada mode fokus diff yang menyembunyikan daftar file dan menampilkan satu diff penuh. Berguna saat meninjau perubahan besar.
- Tab viewer kosong atau tab terminal baru menampilkan satu baris petunjuk, misalnya "⌘+klik path di terminal untuk membuka file di sini".

## 16. Urutan Pengerjaan (Milestone)

Setiap milestone bisa dipakai dan diuji sebelum lanjut ke berikutnya. Keputusan terkait ada di `DECISIONS.md`.

**M1: Satu repo, satu pane, dan terminal (bisa dipakai setiap hari)**
1. [x] Proyek Xcode, jendela utama, penyimpanan repo sebagai path, dan penanganan izin TCC.
2. [x] Satu pane dengan header (nama repo, branch, ahead/behind), area diff, dan area terminal.
3. [x] Terminal dasar dengan SwiftTerm, tab (+ dan ×), dan ganti nama tab.
4. [x] Panel diff dengan `git --no-optional-locks status`, `git diff`, dan FSEvents.
5. [x] Persistensi dasar: daftar repo, posisi pembagi, dan satu tab terminal saat dibuka ulang.

*Kriteria selesai*: buka satu repo, diff sesuai kondisi repo, `npm run dev` dan `vim` berjalan di terminal, dan repo terakhir tetap ada setelah aplikasi di-restart. **[x] Tercapai.**

**M2: Viewer dan Cmd+klik (fitur pembeda utama)**
6. [x] Viewer file read-only dengan tab, nomor baris, batas ukuran, dan pencarian ⌘F.
7. [x] Deteksi path dan Cmd+klik, termasuk resolusi path absolut/relatif, dedup tab, file tidak ditemukan, dan nama file ambigu. Tooltip path absolut saat hover ditunda (lihat TASK.md — dibatasi SwiftTerm, bukan terlewat).
8. [x] Pelacakan cwd lewat shell integration (zsh lewat OSC 7; shell lain fallback ke folder repo), dan muat ulang otomatis saat file berubah.
9. [x] Tombol **Salin perintah** di panel diff, serta salin diff dan salin path.

*Kriteria selesai*: Cmd+klik `src/app.ts:42` membuka viewer dan langsung ke baris 42, dan path di output berwarna tetap terdeteksi. **[x] Tercapai.**

**M3: Grid pane dan manajemen sesi**
10. [x] Grid pane: 2 pane, lalu 3 dan 4 pane, dengan pembagi, preset layout di toolbar, fokus (⌘1–⌘4 dan ⌥⌘ panah), dan batas ukuran minimum.

Tambahan 2026-10-24: menu **Layout** menyatukan tambah pane, preset, dan hitungan pane. Menu **•••** pada header menyediakan maksimalkan, mode terminal, tutup repo, dan tutup pane; pane terakhir tidak dapat ditutup, dan menutup pane tidak menghentikan sesi repo. Pane kosong menyediakan **Buka Repo…** serta menu repo terakhir. Status build/runtime tambahan dicatat di `TASK.md`.
11. [ ] Maksimalkan pane (⌃⌘M) dan maksimalkan terminal saja (⌥⌘M).
12. [ ] Penanda pane yang butuh perhatian: titik kuning untuk selesai, merah untuk error, dengan ikon atau teks.
13. [ ] Tutup repo dari pane (⌘⇧W) dengan toast "Repo ditutup · Buka lagi". Sesi tetap hidup.
14. [ ] Layar pertama: grid kosong, placeholder repo terakhir, dan pemulihan jendela dan susunan pane.
15. [ ] Worktree: dua worktree dari repo yang sama bisa berdampingan.

*Kriteria selesai*: empat pane aktif bersamaan, repo ditutup lalu dibuka lagi tanpa menghentikan proses, dan penanda muncul di pane yang tidak aktif. **[ ] Belum tercapai.**

**M4: Fitur tambahan dan pemakaian harian**
16. [ ] Viewer sebagai panel samping diff (default tetap tab, disimpan per pane).
17. [ ] Konfirmasi ⌘Q jika ada proses berjalan, dengan tombol default Batal.
18. [ ] Quick switcher (⌘P) dengan hasil dipisah per jenis, dan pencarian.
19. [ ] UI/UX dari bagian 15b: warna identitas repo, pesan inline, menu bar, overlay ⌘/, dan mode fokus diff.
20. [ ] Fitur tambahan dari 17a yang belum masuk: status kerja per repo, notifikasi dengan konteks, perbandingan dengan branch, filter file baru, sembunyikan file besar, dan seret folder dari Finder.
21. [ ] Pengaturan (⌘,), diagnostik, ekspor log, dan Sparkle (jika dikonfirmasi).

*Kriteria selesai*: pemakaian harian selama beberapa hari tanpa kehilangan sesi, dengan pemakaian memori dan CPU dalam target yang sudah diukur. **[ ] Belum tercapai.**

## 17. Keputusan

| Pertanyaan | Keputusan |
|---|---|
| Stack | SwiftUI native (AppKit bila perlu) |
| Arsitektur | Apple Silicon (arm64) saja |
| Sandbox dan distribusi | Tanpa App Sandbox, Hardened Runtime aktif, Developer ID dengan notarization. Untuk pemakaian pribadi, tidak untuk App Store |
| Sidebar | Tidak ada. Repo dibuka lewat toolbar, ⌘O, dan ⌘P |
| Layout | Grid pane, maksimal 4 (2 × 2) |
| Panel per repo | Diff dan viewer di atas, terminal di bawah |
| Membuka URL dari terminal | Tidak di versi awal |
| Batas ukuran file teks | 5 MB |
| Batas ukuran gambar dan PDF | 20 MB |
| Stage/unstage dari panel diff | Tidak. Bertentangan dengan tujuan read-only. Sebagai gantinya, tombol **Salin perintah** menyalin `git add <path>` atau `git restore --staged <path>` ke clipboard, dan pengguna menjalankannya sendiri di terminal. Aksi stage langsung bisa dipertimbangkan nanti sebagai opt-in dengan konfirmasi |
| Proses tetap jalan setelah aplikasi ditutup | Tidak di versi awal. Sebagai gantinya, ⌘Q menampilkan konfirmasi jika ada proses yang berjalan, dengan tombol default Batal. Untuk kebutuhan ini, pengguna bisa memakai `tmux` di dalam tab terminal |
| Aturan ⌘W | ⌘W hanya menutup tab. Penutupan repo dan pane memakai ⌘⇧W dan tombol × |
| Maksimalkan pane | Ada, lewat ⌃⌘M (pane) dan ⌥⌘M (terminal saja) |
| Penanda pane | Titik kuning (selesai) dan merah (error) di header pane yang tidak aktif |
| Nama branch dan ahead/behind | Masuk versi awal |
| Worktree dan viewer sebagai panel samping | Masuk versi awal |
| Tab saat repo dibuka ulang dalam sesi yang sama | Tab yang masih berjalan tetap utuh. Aturan satu tab hanya berlaku setelah aplikasi quit |

## 17a. Fitur Tambahan (Masuk Versi Awal)

Semua fitur di bagian ini masuk versi awal:

1. **Nama branch aktif dan indikator ahead/behind** di header pane. Masuk versi awal.
2. **Salin diff dan salin path** dari panel diff, untuk ditempel ke agen AI atau pesan commit.
3. **Deteksi path yang tahan ANSI** di terminal, termasuk path yang terpotong karena lebar layar. Ini penyebab umum Cmd+klik gagal.

4. **Status kerja per repo**: idle, proses berjalan, atau perlu perhatian (proses berhenti dengan error).
5. **Notifikasi dengan konteks**: menampilkan nama repo dan tab yang selesai.
6. **Bandingkan dengan branch lain** (misalnya `main`), selain perubahan yang belum di-commit.
7. **Filter file yang baru berubah** (misalnya 10 menit terakhir), berguna saat agen sedang bekerja.
8. **Sembunyikan file besar** di panel diff (lock file, file generated), dengan batas jumlah baris agar tetap responsif.
9. **Seret folder ke pane** dari Finder untuk membuka repo.

## 17b. Fitur Lanjutan (Masuk Versi Awal)

- **Worktree**: repo bisa dibuka sebagai worktree. Menu pane menyediakan **Buka Branch di Pane Baru** untuk memilih branch lokal dan membuka atau membuat worktree terisolasi. Dua worktree dari repo yang sama bisa berdampingan di pane masing-masing, dengan diff dan sesi terminal sendiri. Daftar repo tersimpan menampilkan worktree sebagai item terpisah dengan nama repo dan branch. Worktree baru dikelola di `~/Library/Application Support/Gridline/Worktrees/`; menutup pane tidak menghapusnya.
- **Viewer sebagai panel samping diff**: tombol di tab viewer mengubah viewer dari tab di area atas menjadi panel samping diff. Default tetap tab, dan pilihan ini disimpan per pane.

## 18. Pertanyaan yang Masih Terbuka

- Minimum macOS: macOS 26 (Tahoe). Sudah ditetapkan, tetapi perlu dicek ulang jika ada kebutuhan dukungan versi lama.
- Distribusi: pemakaian pribadi dengan Developer ID dan notarization. Sudah diputuskan.
- Pembaruan otomatis: Sparkle diusulkan untuk versi awal, karena Developer ID mendukungnya. Perlu dikonfirmasi.
- Nama apps: Gridline (nama kerja). Perlu dicek ketersediaannya di App Store dan sebagai merek dagang sebelum rilis.
- Ukuran minimum di bagian 4 adalah perkiraan awal dari kebutuhan isi. Angka final perlu diuji di layar nyata saat implementasi.
- Layar pertama dan pemulihan saat dibuka ulang: sudah ditetapkan di bagian 4 (grid kosong saat pertama kali, susunan terakhir dengan satu tab terminal saat dibuka ulang).
- Saat repo dibuka ulang dalam sesi yang sama, termasuk setelah ditutup dari pane, semua tab terminal yang masih berjalan tetap utuh. Aturan satu tab hanya berlaku setelah aplikasi ditutup dan dibuka ulang.
