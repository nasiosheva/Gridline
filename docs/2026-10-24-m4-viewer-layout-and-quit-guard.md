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
- Ikon aplikasi memakai AppIcon macOS dengan 10 ukuran raster dari set ikon yang diberikan.
- `GitProcess` membaca stdout/stderr secara paralel selama proses Git berjalan; ini mencegah pipe penuh menahan proses. `RepoDiffStore` menyatukan refresh yang bertumpuk, menyimpan cache branch selama 15 detik, dan menghindari pemuatan diff ulang jika entri terpilih tidak berubah.
- Tab file menyediakan pencarian overflow saat lebih dari tiga tab terbuka dan aksi untuk menutup tab lain; semua label baru ada di katalog Indonesia/English.
- Tab terminal memakai `ViewThatFits`: strip chip tetap dipakai saat muat, lalu menampilkan chip aktif dan menu pemilih semua tab ketika ruang horizontal menyempit.
- Panel Diff kini bisa memilih branch dasar dan branch tujuan. Daftar file dan isi diff memakai `git diff <base>...<target>`, sehingga hanya perubahan di branch tujuan sejak titik percabangan bersama yang ditampilkan. Pemilihan branch lokal satu arah untuk membandingkan working tree tetap tersedia. Filter waktu sepuluh menit disembunyikan pada mode branch-to-branch karena timestamp working tree tidak mewakili waktu perubahan pada branch tersebut.
- Pemilih branch **Local Changes** di panel Diff memakai popover dengan kolom pencarian selalu terlihat, filter tanpa membedakan huruf besar/kecil, dan aksi × untuk mengosongkan query. Copy pencarian dipakai bersama pemilih worktree dalam katalog lokal.
- Pilihan perbandingan Diff terakhir (working tree terhadap satu branch atau dua branch) kini disimpan per repo dan dipulihkan saat app dibuka lagi. Jika branch yang disimpan sudah dihapus, panel kembali ke Local Changes dan state lama dibersihkan. Default perbandingan awal worktree juga dicatat saat pertama kali dipakai.
- Mengubah layout menjadi lebih sedikit pane kini mempertahankan pane aktif. Sebelumnya `setPreset` selalu menyimpan slot awal, sehingga pane worktree aktif pada slot berikutnya hilang dan repo dasar tampak kembali setelah reopen.
- Saat jendela muncul kembali dalam proses app yang sama, registry memaksa refresh status Git dan daftar branch untuk repo yang masih terlihat. Ini menangani checkout bersih yang hanya mengubah `.git/HEAD` dan tidak memicu watcher direktori repo.
- Selama pane terlihat, `GitHEADWatcher` memantau direktori metadata Git dan hanya meminta refresh bila isi `HEAD` berubah. File `.git` pada worktree diikuti ke gitdir yang sebenarnya; watcher berhenti saat pane tidak terlihat. Ini memperbarui branch setelah checkout bersih tanpa pemindaian Git pada setiap prompt terminal.
- Pemeriksaan lokal `GitHEADWatcher` menangkap checkout bersih pada repo utama dan linked worktree sementara; perubahan metadata `.git` yang tidak mengubah `HEAD` tidak memicu refresh, dan watcher yang dihentikan tidak mengirim event lagi. Pengujian memakai repo sementara dan tidak mengubah checkout pengguna.
- Untuk perbaikan restore pilihan branch, typecheck seluruh source Swift berhasil; pembacaan state lama, roundtrip tiga mode perbandingan pada salinan state sementara, dan retensi pane branch aktif saat layout menjadi satu pane juga berhasil. Build Xcode penuh berhenti saat mengunduh dependency karena DNS GitHub tidak tersedia; perilaku reopen di GUI belum diuji.
- Menu tindakan pane menyediakan **Buka Branch di Pane Baru** dengan pencarian branch yang langsung memfilter daftar. Gridline memakai atau membuat Git worktree terpisah di `~/Library/Application Support/Gridline/Worktrees/`; sesi terminal dan diff mengikuti path worktree masing-masing. Folder tidak dihapus saat pane ditutup agar perubahan pengguna tetap aman.
- Panel worktree kini menyimpan ID repo sumber dan nama branch. Jika folder worktree hilang, panel menampilkan **Pilih Branch Lagi…** dan membuka pemilih branch dari repo sumber, lalu mengganti isi pane yang sama. Worktree lama yang ditemukan dalam metadata Git tetapi path-nya hilang dipruning sebelum membuat ulang worktree; entri repo lama tanpa metadata sumber dicoba dipetakan dari nama tampilannya.
- Saat pane worktree dibuka, header menampilkan indikator inline hingga status branch dan refresh awal panel diff selesai. Status header dan panel diff berbagi satu pemindaian `git status`; pemeriksaan daftar worktree/common directory dan refresh daftar file/branch pembanding juga berjalan bersamaan.
- File untracked dihitung dengan pembacaan `FileHandle` per chunk, bukan satu proses Git per file. Pembacaan dibatasi empat file bersamaan; file biner tidak dihitung, dan baris terakhir tanpa newline tetap dihitung.
- `RepoFileWatcher` mengecualikan direktori `.git` dan hanya memakai coalescing latency FSEvents, tanpa debounce manual kedua. Registry menghentikan watcher diff dan viewer saat repo/pane tidak terlihat, lalu menyambungkannya kembali dan merefresh saat tampil lagi; `RepoSession` dan proses terminal tetap hidup.
- Diff file list menghitung filter utamanya sekali per evaluasi `body`. Baris diff unified dan split memakai `LazyVStack` agar view per baris dibuat sesuai kebutuhan scroll.
- Viewer menghitung indeks nomor baris di worker dan menyimpannya secara kompak per file; pembaruan AppKit memakai versi konten agar tidak membandingkan seluruh teks saat view diperbarui. Event folder tetap dipantau untuk delete/rename, tetapi fingerprint file mencegah baca ulang saat hanya sibling yang berubah; reload bersamaan digabung.
- Pemeriksaan source untuk fitur perbandingan branch, pane worktree, viewer, indikator/pencarian branch, dan overflow tab: Swift parser, JSON katalog, dan `git diff --check` berhasil.
- Build CLI pada versi sebelum perubahan review performa terakhir berhenti saat resolusi SwiftPM: sandbox menolak penulisan Swift module cache dan manifest diagnostics di `~/Library/Caches` (`Operation not permitted`, exit 74). Pemeriksaan source untuk perubahan setelahnya perlu dicatat terpisah; checklist build/runtime tetap pending.
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
