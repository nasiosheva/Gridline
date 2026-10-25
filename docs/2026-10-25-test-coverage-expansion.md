# Perluasan unit test (2026-10-25)

Scheme `Gridline` mengaktifkan code coverage dan target `GridlineTests` diperluas untuk menguji jalur logika yang sebelumnya belum tercakup. Test baru meliputi:

- Parsing dan resolusi link terminal, termasuk path di luar repo, basename ambigu, suffix baris/kolom, dan file tersembunyi.
- `FileLoader`, `FileViewerTab`, status isi viewer, kebijakan ukuran diff, status Git, serta preferensi terminal/diff.
- Bentuk grid, operasi slot, assignment repo, fokus, mode pane, divider, dan kompatibilitas Codable pada `PaneLayout`.
- Pemulihan/persistensi `AppStateStore`, recent repo, pemilihan pane, comparison selection, dan debounce penyimpanan divider.
- Status staged/unstaged/untracked, pemilihan file, perbandingan branch, dan callback konsumsi branch awal pada `RepoDiffStore`.
- Batas path TCC, pesan error pembukaan repo, dan konstruksi body view untuk jalur viewer/picker tanpa menekan aksi UI eksternal.

Verifikasi Xcode GUI terakhir menjalankan seluruh 48 test dengan 0 kegagalan. Snapshot coverage Xcode yang terukur sebelum delapan test model/viewer terakhir ditambahkan menunjukkan `Gridline.app` 51,8% dari 10.429 executable lines. Coverage belum diukur ulang untuk suite 48 test, sehingga 51,8% dicatat sebagai snapshot, bukan angka final. Target coverage 100% belum tercapai; view/AppKit yang perlu interaksi runtime, notifikasi, clipboard, atau izin sistem belum seluruhnya diuji.

Percobaan `xcodebuild test` dari CLI masih berhenti saat SwiftPM menulis cache/diagnostik di luar workspace. Hasil 48/48 berasal dari scheme Xcode GUI pada destination My Mac.
