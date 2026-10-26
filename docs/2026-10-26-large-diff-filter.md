# Perilaku filter file besar

Filter daftar diff kini menyaring pilihan dan preview secara bersamaan, termasuk filter perubahan terbaru dan **Sembunyikan File Besar**. Jika pilihan aktif tidak lolos filter, Gridline berpindah ke file pertama yang terlihat. Jika daftar tidak memiliki hasil, pilihan dan preview dibersihkan agar isi panel tidak lagi menunjukkan file yang disembunyikan.

Filter dipusatkan sebagai state `RepoDiffStore.visibleEntries`, sehingga refresh otomatis juga memilih hanya file yang lolos dan tidak memulai pemuatan baru untuk file tersembunyi. Jika filter berubah saat file dipilih, rekonsiliasi di `DiffAreaView` ditunda hingga pembaruan SwiftUI selesai. ID daftar terbaru diperiksa lagi sebelum state diubah supaya perubahan filter yang cepat tidak menggunakan hasil lama. Mengganti pilihan membersihkan preview lama dan menolak hasil load yang sudah kedaluwarsa; proses Git yang sedang berjalan sendiri belum bisa dibatalkan.

Tooltip disesuaikan dalam bahasa Indonesia dan English. Kontrak pengguna dicatat sebagai D41 di `DECISIONS.md` dan ditambahkan ke bagian panel diff di `apps-spec.md`. Catatan performa lama tentang Quick Switcher juga diperbarui: jumlah pane tidak dibatasi empat.

Nama repo kini memakai teks tebal dengan warna identitas repo di atas latar lembut berwarna sama. Nama branch aktif memakai teks cyan terang di header pane. Kontrol Diff menampilkan pasangan branch aktif dan branch pembanding dengan warna berbeda; mode perbandingan dua branch menampilkan dasar → target. Label aksesibilitas tetap memakai wording terlokalisasi agar arti perbandingan tidak bergantung pada warna.

Tombol panah kiri-kanan di antara nama branch kini benar-benar menukar arah perbandingan. Pada mode branch aktif dibanding branch pilihan, aksi beralih ke mode dasar → target dengan arah terbalik; pada mode dua branch, aksi menukar dasar dan target. Kontrol swap terpisah dari tombol nama branch yang membuka picker, dan keduanya memuat ulang daftar serta isi diff. Label bantuan dan aksesibilitas dilokalisasi untuk Indonesia dan English.

Tab bar area atas disembunyikan saat belum ada file viewer terbuka. Diff memakai ruang itu langsung; tab bar tetap muncul saat ada file viewer agar pengguna dapat berpindah antara Diff dan file.

Pilihan dan arah perbandingan branch dipulihkan dari state repo saat aplikasi dibuka kembali. Callback persistensi dipasang di composition root sebelum view pane dapat membuat store diff, sehingga perubahan awal tidak dapat mendahului callback.

Penulisan state aplikasi kini memakai penulisan atomik langsung setelah memastikan direktori tersedia. Kegagalan encode atau tulis dicatat ke diagnostics dengan kode error, dan penentuan lokasi Application Support memiliki fallback tanpa force unwrap.

Struktur kode dipisah berdasarkan tanggung jawab dalam target Xcode yang sama: model domain dan kebijakan diff di `Core`, helper stateless di `Reusable`, state runtime di `Models`, integrasi di `Support`, dan UI di `Views`. Lokalisasi label grup diff dipindahkan keluar dari model; clamp nilai batas yang sama kini memakai satu helper generik.

Indikator jumlah commit behind di header kini membuka konfirmasi Pull untuk upstream yang terdeteksi. Aksi dijalankan melalui service Git terpisah dengan `git pull --ff-only`, menampilkan spinner selama proses dan hasil lokal dalam alert, lalu memuat ulang status. Kegagalan dicatat di diagnostics; output remote mentah tidak ditampilkan. Jika branch tidak bisa fast-forward, Gridline tidak membuat merge atau membuang perubahan lokal. Angka behind dapat stale karena status Git tidak melakukan fetch otomatis.

Verifikasi build dan GUI masih pending. Belum ada pengukuran Instruments; perintah Git yang sudah dimulai tidak dijamin dapat dibatalkan, jadi perubahan ini memastikan preview mengikuti filter tetapi belum membuktikan penghematan CPU/RAM.
