# Tes refresh metadata Git

Ditambahkan target unit test `GridlineTests` dengan tiga kasus integrasi berbasis repo Git sementara:

- Perubahan index saja melalui `git update-index --chmod=+x` harus memperbarui daftar staged di `RepoDiffStore` tanpa mengubah file kerja.
- Perubahan ref branch aktif harus terdeteksi walau isi `.git/HEAD` tetap sama.
- Perubahan ref branch perbandingan harus memicu watcher walau branch itu bukan branch aktif.
- Perubahan ref perbandingan yang mengganti teks diff dengan jumlah baris tambahan/penghapusan yang sama harus memuat ulang diff file terpilih.

Tes menjaga pemeriksaan metadata Git tetap terarah ke `HEAD`, index, dan ref yang relevan. Tes tidak memantau seluruh direktori `.git`.

Probe Swift mandiri pada implementasi `GitMetadataWatcher` berhasil untuk perubahan index saja, ref branch aktif dengan `.git/HEAD` tetap, dan ref branch perbandingan. Suite XCTest lulus 4/4 lewat Xcode GUI pada 2026-10-25, termasuk integrasi yang memastikan isi diff terpilih diperbarui setelah ref comparison berubah dengan jumlah baris tetap.

Verifikasi CLI `xcodebuild test` sebelumnya belum mencapai kompilasi. Sandbox mencegah SwiftPM menulis file diagnostik manifest ke cache pengguna di luar workspace; percobaan memakai lokasi package checkout yang sudah ada tetap berhenti pada batas akses tersebut. Percobaan awal yang memakai cache package sementara juga tidak dapat mengambil dependency dari GitHub karena jaringan tidak tersedia. Run lewat Xcode GUI berhasil. Swift source lolos parse, project file lolos `plutil -lint`, dan scheme lolos parse XML.
