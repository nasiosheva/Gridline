# Kontrak output dan baseline performa — 2026-10-27

PERF-01 menambahkan pembanding output untuk optimasi berikutnya. Sembilan test baru berada dalam dua file test existing; kode produksi aplikasi tidak diubah.

- `PerformanceOutputContractTests` (7 test): status/counts/order, nama file khusus, raw diff dan line numbers, semantic model dengan UUID baru, merge-base branch divergen, invalidasi diff saat ukuran/mtime sama, refresh serentak, selection sesudah filter, dan payload command copy.
- `PerformancePolicyOutputContractTests` (2 test): compact folders/natural sort/urutan tree serta tie-breaking LCS dan rentang Character Unicode.
- Helper repo Git sementara yang sudah ada diberi metode tulis file, sehingga fixture baru memakai setup dan cleanup yang sama. Fixture tidak memakai repo pengguna.

## Verifikasi akhir

Native XCTest pada 2026-10-27 07:23 WIB lulus **25 test, 0 gagal**, termasuk sembilan test baru dan 16 test Git/parser/watcher/policy existing. Durasi suite 15,545 detik; ini bukan benchmark performa aplikasi. Modul runner mengompilasi 14 file produksi relevan langsung dari source pada baseline `280f158`, dengan Swift language mode 5, default MainActor, fitur approachable concurrency terkait, SDK macOS 27.0, dan target `arm64-apple-macos27.0` sesuai deployment target aktual project. Hash source/test cocok setelah eksekusi.

Run awal pada 26 Oktober menggunakan target macOS 26.0 dan lulus 25/25. Satu run bertarget 27.0 yang berlangsung ketika sesi terputus kemudian mencatat satu timeout pada watcher test existing; suite berjalan 986,313 detik dengan jeda panjang di log. Penyebab tidak dipastikan. Run aktif akhir lulus seluruhnya, dan kedua hasil tetap disimpan di bukti lokal.

Percobaan `xcodebuild test` penuh terhenti sebelum kompilasi oleh pembatasan cache/resolver SwiftPM sandbox. Hasil di atas berasal dari native XCTest terhadap subset source tanpa app host, bukan build/test penuh scheme Gridline. Warning isolasi baseline pada `flatMap(leafEntries)` di `DiffFileTreePolicy` tidak diperbaiki dalam perubahan ini.

Kedua file test lengkap lolos `swiftc -typecheck` terhadap modul Debug Gridline/SwiftTerm cached dengan target macOS 27.0, exit 0. Ini tidak membangun ulang aplikasi penuh; stderr masih memuat pesan sandbox dari pemuatan tool/plugin.

Test baru terpasang di target existing dan dapat dijalankan dari checkout normal dengan:

```sh
xcodebuild \
  -project Gridline.xcodeproj \
  -scheme Gridline \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -skipPackagePluginValidation \
  -only-testing:GridlineTests/PerformanceOutputContractTests \
  -only-testing:GridlineTests/PerformancePolicyOutputContractTests \
  test
```

## Batas hasil

UI test tetap dihentikan. Visual, fokus, scroll anchor, clipboard sistem, host aplikasi penuh, FPS, CPU, dan memory leak belum diverifikasi ulang. Snapshot parser mencatat perilaku context line kosong dari newline raw diff yang sudah ada; perilaku itu tidak diubah sebagai bagian dari persiapan optimasi. Payload Copy Diff tetap dibandingkan dengan Git langsung, dan payload command dengan literal acuan.

Checklist, baseline lingkungan, manifest source, runner fallback, serta log sukses/gagal tersimpan di `personal-docs/` dan tetap untracked. PERF-01 menyiapkan pengaman output; belum ada klaim aplikasi lebih cepat atau perubahan coverage.

## PERF-02: instrumentasi development dan baseline source

`Support/PerformanceTrace.swift` menambah collector opt-in yang hanya aktif pada DEBUG dengan `GRIDLINE_PERF_TRACE=1`; default mati dan Release tetap mati. Span memakai nama tahap bertipe, durasi, indikator thread, dan jumlah item opsional. Counter mencatat peluncuran Git, penggabungan refresh, cache hit/miss, hasil stale, pembatalan persistensi, dan kegagalan startup watcher. Data tidak memuat path, argumen, isi file, output terminal, atau credential, dan tidak diekspor otomatis. Ring buffer menyimpan 4.096 sample terbaru dengan penghitung drop; lock melindungi mutable storage.

Pengukuran dipasang pada Git, parsing/metadata, refresh/publish, loader/viewer, cache persiapan diff, tree presentation, persistensi, dan update/rebuild host pane. Integrasi tidak mengganti scheduler, parser, token invalidasi, batas ukuran/highlight, atau alur UI. Helper tree presentation hanya membungkus operasi existing agar trace tidak menjadi ekspresi Void dalam ViewBuilder.

Pada fixture 1.400 file dan 1/4/8 **model repo tanpa GUI**, median refresh model-cold sekitar 373/1.225/2.427 ms. Fase sinkron `statusMetadata` sekitar 245 ms median pada main thread; compare working-tree metadata sekitar 253 ms pada main thread meskipun layanan compare ditandai `nonisolated`. Persiapan highlight dingin sekitar 57 ms pada main thread; viewer mendekati 5 MiB sekitar 313 ms berjalan di worker. Lima repetisi pemilihan cepat 20 file meluncurkan 100 request Git, dengan 95 hasil stale dibuang. Ini baseline DEBUG source, bukan latensi klik/FPS atau benchmark Release.

Terkumpul 86 pengukuran valid dengan raw data, median/p95, CPU proses sendiri, high-water RSS sepanjang umur proses, FD akhir, dan request Git in-flight. Lima burst divider grid masing-masing membatalkan 19 persist task dan menghasilkan satu write akhir; setter top splitter per pane yang langsung persist diukur terpisah. Workload FSEvents tidak tersedia karena `FSEventStreamStart` mengembalikan false; tidak dibuat klaim bug produksi dari kondisi ini.

Verifikasi: **43 test terarah lulus**, termasuk kontrak output sebelumnya dan tiga test collector baru; smoke gating Release berhasil, serta 67 file Swift produksi lolos parse sintaks. Full-source typecheck dicoba namun tertahan macro SwiftUI `StateMacro`/plugin server dalam sandbox. Modul native mengompilasi 22 file produksi relevan dan memakai deklarasi persiapan diff asli; build penuh aplikasi dan kesetaraan visual belum dibuktikan ulang. Source/test hash cocok dengan artefak pengukuran.

PERF-02 tetap **parsial, dua dari empat subchecklist selesai**: instrumentasi dan baseline source tersedia, sedangkan pengukuran UI nyata/busy main thread menyeluruh serta event burst watcher masih terbuka. UI test tidak dilanjutkan. Pekerjaan berhenti pada PERF-02 sesuai permintaan pengguna; PERF-03 belum diimplementasikan. Checklist dan seluruh bukti lokal tetap untracked di `personal-docs/`.
