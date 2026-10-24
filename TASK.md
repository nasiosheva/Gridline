# TASK.md — Pelacak Tugas Implementasi Gridline

Dokumen ini melacak progres implementasi terhadap milestone di `apps-spec.md` bagian 16, dengan detail file per tugas. Tujuannya supaya agent/engineer lain (manusia atau AI) yang melanjutkan pekerjaan ini tidak perlu membaca ulang seluruh kode untuk tahu apa yang sudah dan belum selesai.

**Update dokumen ini setiap kali sebuah tugas selesai atau status berubah.** Jangan hapus baris yang sudah selesai — biarkan tercentang sebagai riwayat, mengikuti gaya `DECISIONS.md` (append, bukan timpa).

Legenda: `[x]` selesai dan sudah diverifikasi build sukses · `[~]` sedang dikerjakan / sebagian selesai · `[ ]` belum dikerjakan.

---

## M1 — Satu repo, satu pane, dan terminal

- [x] **1. Proyek Xcode, jendela utama, penyimpanan repo sebagai path, izin TCC**
  - `Gridline/Models/Repo.swift`, `Gridline/Support/AppStateStore.swift`, `Gridline/Support/RepoOpener.swift`, `Gridline/Support/TCCPermission.swift`
  - Sandbox dimatikan di `project.pbxproj` (`ENABLE_APP_SANDBOX = NO`, `ENABLE_HARDENED_RUNTIME = YES`) sesuai D16.
- [x] **2. Satu pane dengan header (nama, branch, ahead/behind), area diff, area terminal**
  - `Gridline/Views/RepoPaneView.swift`, `Gridline/Views/RepoPaneHeaderView.swift`, `Gridline/Support/GitService.swift`
- [x] **3. Terminal dasar SwiftTerm, tab (+ dan ×), ganti nama tab**
  - `Gridline/Models/TerminalTab.swift`, `Gridline/Models/RepoSession.swift`, `Gridline/Support/RepoSessionStore.swift`, `Gridline/Views/TerminalHostView.swift`, `Gridline/Views/TerminalAreaView.swift`
  - Dependency SPM: SwiftTerm 1.20.0 (dipin — versi 1.99.x butuh plugin build tambahan, lihat catatan di bawah).
- [x] **4. Panel diff (`git status`/`git diff` + FSEvents)**
  - `Gridline/Models/DiffModels.swift`, `Gridline/Support/GitProcess.swift`, `Gridline/Support/GitDiffService.swift`, `Gridline/Support/RepoFileWatcher.swift`, `Gridline/Models/RepoDiffStore.swift`, `Gridline/Support/RepoDiffStoreRegistry.swift`, `Gridline/Views/DiffAreaView.swift`
  - Bug off-by-one di parsing rename/copy (`"2 "` porcelain v2) ditemukan lewat code review dan sudah diperbaiki.
- [x] **5. Persistensi dasar (daftar repo, posisi pembagi, satu tab terminal saat restart)**
  - `AppState.paneSplitTopFraction` di `AppStateStore.swift`, `Gridline/Views/PersistedVSplit.swift`, `Gridline/Support/WindowConfigurator.swift`
  - "Satu tab setelah restart" otomatis terpenuhi karena `RepoSessionStore` selalu mulai kosong tiap peluncuran aplikasi (tidak ada persistensi sesi terminal, sesuai desain).

**Kriteria selesai M1: TERCAPAI.** Build sukses lewat `xcodebuild`, satu repo bisa dibuka, diff & terminal berfungsi, repo aktif tetap ada setelah restart.

---

## M2 — Viewer dan Cmd+klik (fitur pembeda utama)

- [x] **6. Viewer file read-only (tab, nomor baris, batas ukuran, pencarian ⌘F)**
  - `Gridline/Support/FileLoader.swift` (muat teks/gambar/PDF, batas 5 MB teks / 20 MB media), `Gridline/Views/LineNumberRulerView.swift` (gutter nomor baris `NSRulerView`, indeks baris di-cache per perubahan teks), `Gridline/Views/ReadOnlyTextView.swift` (`NSTextView` read-only, `usesFindBar` untuk ⌘F, scroll-to-line + `showFindIndicator` untuk highlight sebentar), `Gridline/Views/PDFKitView.swift`, `Gridline/Views/FileViewerContentView.swift` (switch semua `FileContent` case + tombol "Salin Path"/"Buka di Finder"), `Gridline/Models/FileViewerTab.swift` (reload otomatis lewat `RepoFileWatcher` pada folder induk), `Gridline/Models/TopAreaStore.swift` + `Gridline/Support/TopAreaStoreRegistry.swift` (tab "Diff" tidak bisa ditutup + tab file bisa ditutup), `Gridline/Views/TopAreaView.swift` (tab bar area atas, menggantikan pemanggilan langsung `DiffAreaView` di `RepoPaneView`).
  - Command global ⌘F (`GridlineApp.swift`) memicu `performFindPanelAction:` lewat responder chain ke `NSTextView` yang fokus.
  - Entry point sementara untuk membuka file (sebelum Cmd+klik di langkah 7 ada): **double-click** baris file di `DiffFileListView` (`DiffAreaView.swift`) memanggil `onOpenFile(absolutePath)`.
  - Build diverifikasi: `BUILD SUCCEEDED`.
- [x] **7. Deteksi path & Cmd+klik dari terminal**
  - Deteksi regex path tidak ditulis sendiri — SwiftTerm 1.20.0 sudah punya implicit-link matcher bawaan gaya Ghostty (`Terminal.linkMatch`/`ghosttyImplicitLinkRegex`) yang berjalan di baris terlihat dan sudah membuang tanda kutip/kurung pembungkus. `linkHighlightMode = .hoverWithModifier` (default SwiftTerm, tidak diubah) sudah memberi garis bawah saat hover+Cmd dan memanggil `TerminalViewDelegate.requestOpenLink` otomatis saat Cmd+klik.
  - `Gridline/Views/GridlineTerminalView.swift` (baru): subclass `LocalProcessTerminalView`, override `requestOpenLink` → meneruskan teks link mentah ke `onOpenLink` closure, kecuali teks itu URL beraneka skema (http/https/mailto/dll, daftar sama dengan regex SwiftTerm) yang tetap dibuka lewat `openLink` default.
  - `Gridline/Support/TerminalLinkResolver.swift` (baru): `parse(_:)` memisahkan sufiks `:baris`/`:baris:kolom`; `resolve(raw:cwd:repoPath:)` mengecek keberadaan file (`FileManager`), dan untuk nama file polos (tanpa `/`) yang tidak ketemu langsung, mencari di seluruh repo (`findFiles`) — 0 hasil → `.notFound`, 1 hasil → `.file`, >1 → `.ambiguous` (bagian 9 apps-spec.md: "jangan buka file pertama yang ditemukan").
  - `Gridline/Models/TerminalTab.swift`: tipe `terminalView` jadi `GridlineTerminalView`; `onOpenLink` memanggil `TerminalLinkResolver.resolve` lewat `Task.detached` (I/O di luar main thread) lalu melempar hasil ke `onOpenPath` closure di `MainActor`.
  - `Gridline/Models/RepoSession.swift`: `openFileHandler` diteruskan ke tiap `TerminalTab` (lama & baru lewat `addTab()`).
  - `Gridline/Views/RepoPaneView.swift`: menyambungkan `session.openFileHandler` ke `TopAreaStore.openFile(path:scrollToLine:)`, plus `PaneToast` (file tidak ditemukan / dibuka di luar repo) dan `AmbiguousFilePickerView` (sheet pilihan saat nama file ambigu).
  - `Gridline/Views/PaneToastView.swift`, `Gridline/Views/AmbiguousFilePickerView.swift` (baru): komponen UI pendukung di atas.
  - **Ditunda, dengan alasan spesifik** (bukan lupa): tooltip path absolut saat hover (bagian 15b) dan kursor pointer kustom saat hover+Cmd (bagian 9) — SwiftTerm menyegel `flagsChanged`, `mouseMoved`, dan `cursorUpdate` sebagai `public` (bukan `open`), jadi tidak bisa di-override dari modul app ini. Jalan lain yang sudah terverifikasi API publiknya tersedia (jika mau dikerjakan nanti): pasang `NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .mouseMoved])` sendiri di `GridlineTerminalView` (bukan override, jadi legal lintas modul), hitung posisi sel dari `bounds`/`terminal.cols`/`terminal.rows` (karena `cellDimension` privat), lalu panggil `terminal.link(at: .screen(Position(col:row:)), mode: .explicitAndImplicit)` (API publik) untuk tahu teks link di bawah kursor, dan `NSCursor.pointingHand.push()/.pop()` + overlay `NSTextField` sendiri untuk tooltip-nya. Saat ini pengguna masih dapat underline hover+Cmd dan preview teks mentah (bukan path absolut) bawaan SwiftTerm di pojok kiri bawah — cukup untuk fungsi, kurang presisi di visual.
  - Build diverifikasi: `BUILD SUCCEEDED`.
- [x] **8. Pelacakan cwd lewat shell integration** (reload otomatis saat file berubah sudah ada sejak langkah 6)
  - `Gridline/Support/ShellIntegration.swift` (baru): untuk shell zsh, menulis 4 file `ZDOTDIR` pengganti (`~/Library/Application Support/Gridline/shell-integration/zsh/.zshenv|.zprofile|.zshrc|.zlogin`) yang (a) selalu men-`source` dotfile ASLI pengguna lewat `GRIDLINE_USER_ZDOTDIR` (jadi PATH Homebrew dari `.zprofile` dkk tetap jalan — tidak ada regresi), (b) `.zshrc` mendaftarkan fungsi `precmd_functions+=(__gridline_report_cwd)` yang mengirim OSC 7 (`\e]7;file://host/path\a`, `PWD` dipersen-encode supaya path berspasi/unicode aman), lalu (c) mengembalikan `ZDOTDIR` ke nilai asli di baris terakhir `.zshrc` supaya shell/proses anak berikutnya (`zsh`/`ssh` bersarang) tidak ikut memakai dotfile Gridline. Diverifikasi manual lewat `zsh -c` dengan dotfile tiruan: passthrough dotfile pengguna ✓, `ZDOTDIR` terkembalikan ✓, output OSC 7 dengan path berspasi ter-percent-encode benar (`My%20Projects`) ✓.
  - `TerminalTab.swift`: `startProcess` sekarang mengirim `environment` eksplisit (`Terminal.getEnvironmentVariables(...)` + override `ZDOTDIR`/`GRIDLINE_USER_ZDOTDIR`) kalau shell-nya zsh; shell lain tetap `environment: nil` seperti sebelumnya (tidak ada perubahan perilaku untuk non-zsh). `LocalProcessDelegateProxy.hostCurrentDirectoryUpdate` sekarang mem-parsing payload lewat `ShellIntegration.parseOSC7` dan memperbarui `TerminalTab.currentDirectory` (`@Published`, default = `workingDirectory`). `onOpenLink` di `TerminalTab` kini memakai `currentDirectory` (bukan `workingDirectory`) sebagai `cwd` saat memanggil `TerminalLinkResolver.resolve` — jadi Cmd+klik sekarang resolve relatif ke folder tempat user benar-benar berada (hasil `cd`), bukan selalu folder akar repo.
  - Shell selain zsh (bash/fish/dll) belum didukung — `ShellIntegration.environmentOverrides` mengembalikan `[]` untuk shell itu, jadi `currentDirectory` tetap diam di `workingDirectory` (fallback folder repo, sesuai yang didokumentasikan di `apps-spec.md` bagian 9).
  - Build diverifikasi: `BUILD SUCCEEDED`.
- [x] **9. Tombol "Salin perintah" di panel diff, salin diff, salin path**
  - `Gridline/Support/Clipboard.swift` (baru): `NSPasteboard.copyString(_:)`, dipakai di semua titik salin (termasuk refactor "Salin Path" viewer yang sudah ada di `FileViewerContentView.swift`).
  - `Gridline/Support/GitDiffService.swift`: `toggleStageCommand(for:)` — `git add <path>` untuk unstaged/untracked, `git restore --staged <path>` untuk staged (path di-quote shell-safe). Apps tidak menjalankan ini sendiri, hanya menyalin ke clipboard (bagian 17a apps-spec.md).
  - `Gridline/Models/DiffModels.swift`: `FileDiff` dapat field `rawText` (output `git diff` mentah) supaya "Salin Diff" identik dengan yang Git tampilkan, bukan rekonstruksi dari `hunks` yang sudah di-parse.
  - `Gridline/Views/DiffAreaView.swift`: context menu klik-kanan per baris file ("Salin Path", "Salin Perintah") di `DiffFileRow`, plus tombol toolbar "Salin Path"/"Salin Perintah"/"Salin Diff" di `DiffContentView` untuk file yang sedang dipilih.
  - Build diverifikasi: `BUILD SUCCEEDED`.

**Kriteria selesai M2: TERCAPAI.** Cmd+klik `src/app.ts:42` membuka viewer dan scroll ke baris 42 (diuji manual: resolusi path, dedup tab, file tidak ditemukan, nama ambigu, dan cwd lewat `cd` di shell zsh semua berfungsi); langkah 6-9 semua `[x]`. Catatan: tooltip path absolut saat hover (bagian 15b) sengaja ditunda — lihat catatan di langkah 7 di atas, bukan bagian dari kriteria selesai M2 yang ditulis di bagian 16 apps-spec.md.

---

## M3 — Grid pane dan manajemen sesi

Sedang berjalan. Catatan desain dan verifikasi per langkah ada di bawah:
- [x] **10. Grid pane (1/2/3-4 pane), pembagi, preset layout toolbar, fokus ⌘1–⌘4 / ⌥⌘ panah, batas ukuran minimum**
  - `apps-spec.md` bagian 15 eksplisit minta `NSSplitViewController` **bersarang** untuk grid 2×2 (bukan `HSplitView`/`VSplitView` SwiftUI bawaan). `PersistedVSplit.swift` (dibuat di M1 langkah 5) sengaja hanya untuk pembagi atas/bawah **dalam satu pane** — jangan dipakai ulang untuk pembagi antar-pane.
  - `AppStateStore` saat ini hanya punya `activeRepoID` tunggal (bukan array pane). Perlu model `PaneLayout`/`PaneSlot` baru menggantikan asumsi "satu repo aktif" di `ContentView.swift` (`repoSwitcher` adalah pengganti sementara yang harus dibongkar di sini).
  - Implementasi 2026-10-23: `Gridline/Models/PaneLayout.swift` menambah model slot/fokus/preset dengan batas 4 pane; `AppStateStore.swift` memigrasikan state M1 dan menyimpan layout, split per-pane, serta tiga divider grid.
  - `Gridline/Views/NestedPaneSplitView.swift` memakai `NSSplitViewController` bersarang untuk 2 kolom dan grid 2×2. `GridToolbarView.swift` menyediakan Buka Repo, Tambah Pane, indikator jumlah, dan preset 1/2/4. `ContentView.swift` sekarang merender slot grid, garis fokus, placeholder, scroll + peringatan ukuran minimum, dan tidak lagi memakai `repoSwitcher` global.
  - Menu Pane di `GridlineApp.swift` menyediakan ⌘1–⌘4 dan ⌥⌘+panah. Sesi terminal/diff/viewer tetap dimiliki registry per repo; mengganti preset atau repo pane tidak menghentikan proses.
  - Verifikasi: seluruh file Swift lolos `swiftc -typecheck -disable-sandbox`; pemeriksaan executable model layout dan migrasi/persistensi state lolos; build Xcode GUI sukses (`Gridline Build Succeeded`, 2026-10-23 11:29 WIB). Smoke test runtime memverifikasi layout 2 kolom, preset 4 pane, batas `4 / 4` yang men-disable Tambah Pane, placeholder, dan pemulihan kembali ke 2 kolom. Callback divider ditunda satu run loop setelah smoke test awal menemukan peringatan re-entrant SwiftUI; run ulang tidak lagi menghasilkan `Publishing changes from within view updates`. Build CLI di environment agent tetap tidak dapat melewati resolver SwiftPM karena nested `sandbox-exec` ditolak sandbox induk, jadi build GUI dipakai untuk bukti build penuh.
- [ ] **11. Maksimalkan pane (⌃⌘M) dan maksimalkan terminal saja (⌥⌘M)** *(implementasi siap; verifikasi build pending)*
  - `PaneLayout` menyimpan mode pane maksimum dan terminal-only secara Codable, dengan aturan kedua mode saling eksklusif.
  - `ContentView` hanya merender pane maksimum; registry sesi repo lain tetap hidup. `RepoPaneView` menyembunyikan area atas saat terminal-only.
  - Header pane menyediakan tombol pulihkan/maksimalkan dan `GridlineApp` menyediakan shortcut ⌃⌘M serta ⌥⌘M.
  - Verifikasi: pemeriksaan executable model layout/migrasi state berhasil. Build penuh Xcode GUI belum dapat dijalankan ulang pada perubahan langkah 11 karena sesi Computer Use dihentikan user; build CLI terhalang resolver SwiftPM/sandbox.
- [ ] **12. Penanda pane butuh perhatian (titik kuning/merah + ikon/teks)** *(implementasi siap; verifikasi build pending)*
  - `TerminalTab` meneruskan exit code ke `RepoSession`; sesi menyimpan status selesai atau gagal sejak terakhir difokuskan.
  - Header pane menampilkan ikon/teks kuning untuk selesai dan merah untuk gagal. Fokus pane menghapus status tersebut.
  - Toolbar menampilkan jumlah pane yang butuh perhatian; sesi repo tetap hidup di registry.
  - Verifikasi: typecheck Swift berhasil; build penuh dan smoke test runtime menunggu Xcode GUI.
- [ ] **13. Tutup repo dari pane (⌘⇧W) + toast "Repo ditutup · Buka lagi"** *(implementasi siap; verifikasi build pending)*
  - Tombol × dan shortcut ⌘⇧W melepas repo dari pane aktif tanpa menghentikan `RepoSession` di registry.
  - Toast sementara menyediakan aksi **Buka lagi** untuk mengembalikan repo ke pane asal.
  - Verifikasi: typecheck Swift berhasil; build penuh dan smoke test runtime menunggu Xcode GUI.
- [ ] **14. Layar pertama (grid kosong, placeholder repo terakhir, pemulihan jendela+pane)** *(implementasi siap; verifikasi build pending)*
  - Pane kosong menampilkan hingga tiga repo terakhir sebagai tombol, selain tombol Buka Repo.
  - Pane dengan path yang sudah dipindah/dihapus menampilkan peringatan dan tombol cari ulang folder.
  - Susunan pane, repo, pane aktif, divider, dan frame jendela tetap dipulihkan melalui state JSON/autosave yang sudah ada.
  - Saat preset layout diperkecil, pane aktif dipertahankan sehingga branch worktree yang sedang dibuka tidak kembali ke repo dasar.
  - Verifikasi: typecheck Swift berhasil; build penuh dan smoke test restart menunggu Xcode GUI.
- [ ] **15. Worktree (dua branch repo yang sama berdampingan)** *(aksi buka branch dan worktree terkelola diimplementasikan; verifikasi build/runtime pending)*
  - Pane dapat membuka branch lokal lain di worktree terpisah dari menu pane; sesi terminal, diff, dan viewer tetap terisolasi per worktree.
  - Worktree baru disimpan di `~/Library/Application Support/Gridline/Worktrees/`; menutup pane tidak menghapus folder atau perubahan pengguna.
  - Pane worktree menyimpan referensi repo sumber dan branch. Jika foldernya hilang, aksi **Pilih Branch Lagi…** membuka pemilih dari repo sumber dan mengganti pane yang sama; metadata worktree Git stale dipruning sebelum pembuatan ulang.
  - Verifikasi executable model untuk identitas worktree sudah berhasil; build penuh dan smoke test dua pane masih pending.

Permintaan tambahan 2026-10-24 (di luar 21 checklist): menu **Layout** menggabungkan tambah pane, preset, dan hitungan; menu **•••** per pane menggabungkan maksimalkan, mode terminal, tutup repo, dan tutup pane. Pane kosong memakai tombol utama **Buka Repo…** dan menu **Repo Terakhir**. Tutup pane menghapus slot, memilih pane tetangga bila pane aktif ditutup, melindungi pane terakhir, dan membiarkan repo beserta sesi terminalnya tetap hidup. Typecheck seluruh source Swift berhasil; build GUI dan smoke test masih pending.

---

## M4 — Fitur tambahan dan pemakaian harian

Sedang berjalan:
- [ ] **16. Viewer sebagai panel samping diff (default tetap tab, disimpan per pane)** *(implementasi siap; verifikasi build pending)*
  - `PaneSlot.viewerAsSidePanel` menyimpan preferensi per pane, default `false`. Saat file dipilih, panel samping menampilkan diff dan viewer berdampingan; mode tab tetap default.
- [ ] **17. Konfirmasi ⌘Q jika ada proses berjalan, dengan tombol default Batal** *(implementasi siap; verifikasi build pending)*
  - Menu Quit/⌘Q menghitung proses terminal hidup. Jika ada, dialog menyebut jumlah proses dengan Batal sebagai default; tanpa proses, aplikasi keluar langsung.
- [ ] **18. Quick switcher (⌘P) dengan hasil dipisah per jenis, dan pencarian.** *(implementasi siap; verifikasi build pending)*
  - Sheet ⌘P mengelompokkan repo tersimpan dan file viewer yang sudah terbuka, menyediakan pencarian nama/path, dan memilih hasil dengan mengarahkan pane aktif ke repo terkait.
- [ ] **19. UI/UX dari bagian 15b: warna identitas repo, pesan inline, menu bar, overlay ⌘/, dan mode fokus diff.** *(implementasi siap; verifikasi build pending)*
  - Warna identitas stabil diturunkan dari ID repo dan dipakai header/quick switcher. Pesan inline/toast yang sudah tersedia tetap digunakan.
  - Menu Repo, Pane, dan Bantuan merangkum tindakan utama; ⌘/ membuka overlay pintasan.
  - Fokus diff menyembunyikan daftar file dan dapat dipulihkan lewat tombol atau menu Pane.
- [ ] **20. Fitur tambahan dari 17a yang belum masuk.** *(implementasi siap; verifikasi build/runtime pending)*
  - Status kerja repo kini menunjukkan idle, jumlah terminal berjalan, atau perlu perhatian. Proses selesai mengirim notifikasi lokal dengan nama repo/tab setelah izin notifikasi diberikan.
  - Panel diff menyediakan filter perubahan 10 menit terakhir dan opsi menyembunyikan file besar berdasarkan ukuran/volume perubahan.
  - Folder repo dapat diseret ke jendela untuk dibuka pada pane aktif.
  - Panel diff dapat menampilkan perubahan working tree terhadap branch lokal lain, termasuk daftar file dan isi diff; mode perubahan lokal tetap tersedia.
  - Pilihan perbandingan branch per repo kini disimpan di state dan dipulihkan saat app dibuka lagi; branch yang telah dihapus mengembalikan panel ke Local Changes.
  - Saat jendela dibuka kembali tanpa menghentikan proses app, status Git dan daftar branch di-refresh walaupun repo yang terlihat tetap sama.
  - Pemantau ringan pada Git `HEAD` mendeteksi checkout bersih di repo biasa dan worktree selama pane terlihat, tanpa memantau seluruh isi `.git`.
  - Semua subfitur checklist 20 sudah diimplementasikan. Checklist tetap pending sampai build dan smoke test GUI berhasil.
- [ ] **21. Pengaturan (⌘,), diagnostik, ekspor log, dan Sparkle (jika dikonfirmasi).** *(implementasi dasar siap; verifikasi build/runtime pending)*
  - Settings ⌘, menyediakan batas scrollback 1.000, 5.000, 10.000, atau 25.000 baris. Perubahan langsung diterapkan ke tab aktif dan tab baru.
  - `DiagnosticLog` menyimpan hingga 500 kejadian metadata di memori dan OSLog; tidak mencatat path repo, isi file, atau isi terminal. Menu Bantuan > Ekspor Log menyertakan kejadian, versi Gridline, macOS, dan Git.
  - Sparkle tidak ditambahkan karena D24 di `DECISIONS.md` masih berstatus diusulkan/belum dikonfirmasi.
  - Kompilasi dan link executable arm64 dari seluruh 48 file Swift berhasil lewat `swiftc -emit-executable -disable-sandbox`, dengan object SwiftTerm yang sudah dibangun sebelumnya. Ini belum mengemas asset app atau membuktikan perilaku runtime.
  - Build Xcode penuh masih terhalang SwiftPM (penulisan manifest diagnostic di luar workspace atau penerapan sandbox bersarang); komponen Metal Toolchain juga belum terpasang (`xcrun` meminta `xcodebuild -downloadComponent MetalToolchain`). Smoke test GUI belum dilakukan.
  - Percobaan menjalankan bundle terisolasi juga belum memberi bukti GUI: Launch Services mengembalikan `kLSNoExecutableErr` walau binary ada; eksekusi binary langsung berakhir `SIGABRT` di AppKit `___RegisterApplication`. UI dan perilaku aplikasi belum tervalidasi.

---

## Utang teknis & keputusan sementara yang perlu ditinjau ulang

Hal-hal berikut **sengaja** disederhanakan di M1–M2 awal karena bergantung pada milestone berikutnya. Jangan dianggap bug kecuali diminta memperbaikinya di luar urutan milestone:

1. **Overflow menu untuk tab yang tidak muat** — `OpenTabsView` menyediakan pencarian/pilihan tab file, dan `TerminalAreaView` kini beralih ke menu tab saat strip tidak cukup lebar.
2. **`RepoPaneView`/`ContentView` memakai satu repo aktif global** — sudah digeneralisasi pada M3 langkah 10 menjadi slot `PaneLayout`; registry sesi tetap per repo.
3. **SwiftTerm dipin ke versi 1.20.0** (bukan `upToNextMajorVersion`) di `project.pbxproj` karena versi 1.99.x butuh `SwiftTermBuildInfoPlugin` yang perlu persetujuan interaktif Xcode ("Trust & Enable") dan `xcodebuild` CLI perlu flag `-skipPackagePluginValidation`. Jangan naikkan versi tanpa mengecek ulang apakah plugin masih dibutuhkan.
4. **`DEVELOPMENT_TEAM = ""`** di `project.pbxproj` ditambahkan otomatis oleh Xcode GUI (bukan oleh agent) — perlu diisi sebelum code signing Developer ID untuk distribusi (D16).
5. **Window frame & split position** — frame memakai autosave native; split atas/bawah dan divider grid kini disimpan per pane/layout oleh `PaneLayout`.

---

## Build & verifikasi

Perintah build (CLI, tanpa Xcode GUI):
```bash
xcodebuild -project Gridline.xcodeproj -scheme Gridline -configuration Debug -skipPackagePluginValidation build
```
`-skipPackagePluginValidation` wajib karena dependency SwiftTerm punya build plugin (`SwiftTermBuildInfoPlugin`) yang butuh persetujuan. Build pertama di mesin baru juga butuh Metal Toolchain (`xcodebuild -downloadComponent MetalToolchain`) untuk compile shader `.metal` milik SwiftTerm.

**Setiap selesai satu tugas**: jalankan build di atas, pastikan `BUILD SUCCEEDED`, baru tandai `[x]` di sini dan di `apps-spec.md` bagian 16.


## Lokalisasi (permintaan tambahan 2026-10-24)

- [x] Copy UI dipusatkan dalam `Gridline/Localizable.xcstrings`, dengan kunci `LocalizedStringResource` di `Gridline/Support/L10n.swift`.
- [x] Bahasa Indonesia (`id`) dan English (`en`) tersedia dan mengikuti preferensi bahasa macOS; belum ada pemilih bahasa di dalam aplikasi.
- [x] Nama repo, path, branch, perintah terminal, dan keluaran terminal tetap menjadi data pengguna/teknis, bukan copy UI.
- [x] Seluruh source Swift lolos typecheck; JSON katalog dan placeholder English/Indonesia cocok.
- [x] Katalog ikut terkompilasi lewat build dan launch Xcode GUI. Pemilihan bahasa dan seluruh UI lokalisasi belum diverifikasi runtime; build CLI masih gagal saat SwiftPM menulis cache di luar workspace.

Permintaan tambahan 2026-10-24: prompt zsh bawaan ditampilkan berwarna bila pengguna belum mengatur prompt sendiri, dan `CLICOLOR` dinyalakan agar keluaran `ls` dapat memakai warna. Prompt kustom pengguna tetap dipertahankan.

Permintaan tambahan 2026-10-24: lifecycle terminal diperkuat dengan memasang callback sebelum PTY dimulai, merekam kegagalan start, membatasi pemindahan fokus otomatis ke pane aktif, dan memanggil `terminate()` untuk setiap shell saat aplikasi ditutup. Typecheck source lolos; smoke test output 5.000 baris dan 2.000 baris dengan resize pane berhasil. Uji salinan build baru mengeluarkan 2.000 baris bertahap dalam 12,32 detik dan menerima perpindahan tab saat output berjalan; pengukuran latensi murni, memori, dan durasi panjang masih pending.

Permintaan tambahan 2026-10-24: pintasan ⌘K membersihkan riwayat scrollback tab terminal aktif; Ctrl+L hanya dikirim di buffer shell biasa agar prompt digambar ulang, bukan saat TUI memakai alternate screen. Label menu dan bantuan pintasan tersedia dalam bahasa Indonesia dan English. Uji GUI pada prompt zsh berhasil. Uji Codex TUI menemukan tampilan kosong pada build lama; guard alternate screen lolos build Xcode GUI dan uji GUI pada salinan build terpisah: TUI tetap tampil, `/exit` bekerja, dan prompt zsh tetap ada setelah ⌘K.

Permintaan tambahan 2026-10-24: hapus ikon dan mekanisme jalankan ulang command terakhir dari tab terminal agar tombol tab tidak mengeksekusi command secara tidak terduga. Shell integration tidak lagi merekam command ke file sementara.

Permintaan tambahan 2026-10-24: tombol **×** menampilkan konfirmasi hanya saat shell hook melaporkan command aktif. Status memakai marker `preexec`/`precmd` tanpa menyimpan teks command; shell yang idle pada prompt langsung ditutup tanpa konfirmasi. Smoke test GUI dengan `sleep 45`, Batal, lalu Ctrl+C berhasil; probe PTY zsh terpisah juga menunjukkan `running` saat program interaktif aktif dan `idle` setelah keluar normal. Uji langsung di Gridline dengan TUI Codex juga berhasil: **×** meminta konfirmasi selama Codex aktif, lalu menutup tab tanpa dialog setelah `/exit` mengembalikan prompt.

Permintaan tambahan 2026-10-24: setelah menambah tab terminal, input langsung masuk ke terminal baru. Smoke test GUI dengan `echo GRIDLINE_FOCUS_OK` berhasil tanpa klik terminal tambahan.

Permintaan tambahan 2026-10-24: terminal memakai latar hitam, teks terang, palet ANSI berkontras tinggi, dan warna folder kerja hijau pada prompt zsh bawaan. Palet 16 warna dipasang lewat SwiftTerm; ANSI 256/truecolor tetap ditangani engine, sedangkan preferensi prompt dan `LSCOLORS` milik pengguna dipertahankan.

Permintaan tambahan: menu **Repo Terakhir** punya aksi **Clear Recent** dengan copy Indonesia dan English. Riwayat tiga repo terakhir disimpan terpisah dari daftar repo tersimpan; clear hanya mengosongkan shortcut recent dan tidak menghapus repo, pane aktif, atau berkas di disk. State lama dimigrasikan dengan memakai tiga repo terakhir dari daftar tersimpan.

Permintaan tambahan 2026-10-24: tinjauan performa menghilangkan proses Git per file untracked, mengecualikan `.git` dari FSEvents, menyatukan debounce ke latency native, menghentikan watcher repo/viewer saat pane tidak terlihat tanpa mematikan sesi terminal, serta melazy-render baris diff dan menghitung filter file sekali per body. Daftar branch pada pemilih Local Changes juga memiliki pencarian inline. Build dan verifikasi GUI untuk perubahan ini masih pending.
