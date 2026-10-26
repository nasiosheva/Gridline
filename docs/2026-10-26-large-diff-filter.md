# Perilaku filter file besar

Filter daftar diff kini menyaring pilihan dan preview secara bersamaan, termasuk filter perubahan terbaru dan **Sembunyikan File Besar**. Jika pilihan aktif tidak lolos filter, Gridline berpindah ke file pertama yang terlihat. Jika daftar tidak memiliki hasil, pilihan dan preview dibersihkan agar isi panel tidak lagi menunjukkan file yang disembunyikan.

Filter dipusatkan sebagai state `RepoDiffStore.visibleEntries`, sehingga refresh otomatis juga memilih hanya file yang lolos dan tidak memulai pemuatan baru untuk file tersembunyi. Jika filter berubah saat file dipilih, rekonsiliasi di `DiffAreaView` ditunda hingga pembaruan SwiftUI selesai. ID daftar terbaru diperiksa lagi sebelum state diubah supaya perubahan filter yang cepat tidak menggunakan hasil lama. Mengganti pilihan membersihkan preview lama dan menolak hasil load yang sudah kedaluwarsa; proses Git yang sedang berjalan sendiri belum bisa dibatalkan.

Tooltip disesuaikan dalam bahasa Indonesia dan English. Kontrak pengguna dicatat sebagai D41 di `DECISIONS.md` dan ditambahkan ke bagian panel diff di `apps-spec.md`. Catatan performa lama tentang Quick Switcher juga diperbarui: jumlah pane tidak dibatasi empat.

Verifikasi build dan GUI masih pending. Belum ada pengukuran Instruments; perintah Git yang sudah dimulai tidak dijamin dapat dibatalkan, jadi perubahan ini memastikan preview mengikuti filter tetapi belum membuktikan penghematan CPU/RAM.
