# Catatan Keputusan: Gridline

Setiap keputusan penting dicatat dengan tanggal dan alasan, supaya tidak perlu diingat ulang. Keputusan yang berubah ditulis sebagai entri baru, bukan dihapus.

## 2026-10-22

**D1. Stack: SwiftUI native, dengan AppKit bila perlu.**
Alasan: terasa seperti apps macOS asli dan ringan. Electron ditolak karena jejak memori lebih besar, dan 4 pane aktif harus tetap hemat.

**D2. Arsitektur: Apple Silicon (arm64) saja.**
Alasan: pemakaian pribadi di Mac sendiri. Build Intel atau universal tidak diperlukan.

**D3. Minimum macOS: macOS 26 (Tahoe).**
Alasan: memakai API SwiftUI dan AppKit terbaru. Perlu dicek ulang jika ada kebutuhan dukungan versi lama.

**D4. Tanpa sidebar. Layout berupa grid pane, maksimal 4 (2 × 2).**
Alasan: mengikuti gaya jendela merge di IntelliJ, sehingga beberapa repo terlihat bersamaan. Batas 4 menjaga layar tetap terbaca dan konsumsi sumber daya terkendali.

**D5. Setiap pane berisi satu repo: diff dan viewer di area atas, terminal di area bawah.**
Alasan: diff dan file adalah bahan review, terminal adalah tempat menjalankan proses. Keduanya perlu terlihat bersamaan.

**D6. Sesi terminal disimpan di model repo, bukan di view.**
Alasan: menutup pane, memindahkan fokus, atau memaksimalkan pane tidak boleh menghentikan proses. Ini aturan yang paling mudah dilanggar saat implementasi.

**D7. Read-only. Tidak ada stage atau unstage langsung.**
Alasan: menjaga janji bahwa melihat diff itu aman. Menulis ke index bisa bentrok dengan agen atau perintah lain. Sebagai gantinya, tombol **Salin perintah** menyalin `git add` atau `git restore --staged`, dan pengguna menjalankannya sendiri. Aksi langsung bisa dipertimbangkan nanti sebagai opt-in.

**D8. Pemantauan Git memakai `git --no-optional-locks status`.**
Alasan: tidak mengambil lock index yang bisa bertabrakan dengan commit dari agen atau perintah lain.

**D9. Tidak ada helper untuk menjaga proses tetap hidup setelah aplikasi ditutup.**
Alasan: helper dengan launchd dan XPC menambah banyak kompleksitas (siklus hidup, kompatibilitas pembaruan, keamanan). Sebagai gantinya, ⌘Q menampilkan konfirmasi jika ada proses berjalan, dan pengguna bisa memakai `tmux`.

**D10. Saat aplikasi dibuka ulang, setiap repo hanya memunculkan satu tab terminal, yaitu tab yang aktif saat quit.**
Alasan: menjaga aplikasi tetap ringan dan tidak memulihkan proses yang sudah berhenti. Tab tambahan tidak dipulihkan.

**D11. Dalam sesi yang sama, repo yang dibuka ulang mempertahankan semua tab yang masih berjalan.**
Alasan: prosesnya belum berhenti, jadi tidak ada alasan untuk menutupnya. Aturan satu tab hanya berlaku setelah quit.

**D12. ⌘W hanya menutup tab. Penutupan repo memakai ⌘⇧W atau tombol ×, dan tidak pernah menutup pane.**
Alasan: ⌘W adalah pintasan yang paling sering dipakai. Jika bisa berarti beberapa hal, pengguna bisa kehilangan pekerjaan.

**D13. Nama branch dan indikator ahead/behind masuk versi awal di header pane.**
Alasan: untuk repo yang dipakai banyak agen atau banyak branch, ini informasi yang paling sering dicari.

**D14. Worktree masuk versi awal. Dua worktree dari repo yang sama bisa berdampingan.**
Alasan: unit yang dibuka adalah worktree, bukan folder. Ini mengubah model data, jadi harus dimasukkan sejak awal.

**D15. Viewer bisa diubah menjadi panel samping diff. Default tetap tab.**
Alasan: tab di area atas terasa sempit saat membuka file sambil melihat diff.

**D16. Tanpa App Sandbox. Hardened Runtime aktif. Distribusi Developer ID dengan notarization, untuk pemakaian pribadi.**
Alasan: aplikasi harus menjalankan shell dan `git` di folder mana pun. Sandbox membatasi proses anak dan akses seperti `~/.gitconfig`. Konsekuensinya, aplikasi tidak bisa masuk App Store, dan itu tidak menjadi tujuan.

**D17. Repo disimpan sebagai path biasa, tanpa security-scoped bookmark.**
Alasan: konsekuensi dari D16. Izin TCC (Desktop, Documents, Downloads) tetap ditangani dengan petunjuk di pane.

**D18. Batas ukuran file: 5 MB untuk teks, 20 MB untuk gambar dan PDF.**
Alasan: cukup untuk membaca file kode dan dokumen pendukung, tanpa membebani memori.

**D19. Scrollback dibatasi 10.000 baris per tab, bisa diatur.**
Alasan: menjaga pemakaian memori saat banyak terminal berjalan. Angka ini perlu diuji.

**D20. Antrean Git dibatasi, misalnya 2 proses bersamaan.**
Alasan: mencegah lonjakan CPU dan konflik saat banyak repo diperbarui sekaligus.

**D21. Ukuran minimum jendela dan pane dihitung dari kebutuhan isi.**
Alasan: terminal 80 × 12 dengan font 13 pt dan diff split yang masih terbaca. Angka final tetap perlu diuji di layar nyata.

**D22. Tidak membuka URL dari terminal pada versi awal.**
Alasan: fokus pada path file lokal. URL bisa ditambahkan nanti tanpa mengubah model dasar.

**D23. Nama kerja: Gridline.**
Alasan: menggambarkan layout grid. Belum dicek ketersediaannya di App Store atau sebagai merek dagang. Wajib dicek sebelum rilis, meskipun pemakaian pribadi.

**D24. Pembaruan otomatis dengan Sparkle.**
Status: **diusulkan, belum dikonfirmasi.**

## 2026-10-22 (v0.18)

**D25. Di daftar file diff, ↑/↓ memilih file. ⌥↑/⌥↓ pindah antar-hunk.**
Alasan: sebelumnya ↑/↓ dipakai untuk dua hal sekaligus, dan pengguna akan mengharapkan ↑/↓ menggerakkan daftar.

**D26. Tab yang tidak muat masuk menu overflow, dan ⌘P bisa pindah ke file yang sudah terbuka.**
Alasan: pane 680 pt tidak cukup untuk banyak tab. Overflow menjaga tampilan tetap rapi tanpa membatasi jumlah file yang bisa dibuka.

**D27. Preset layout (1 pane, 2 kolom, 2 × 2) di toolbar. Default 2 kolom.**
Alasan: memilih susunan lebih cepat daripada menambah pane satu per satu. Default 2 kolom lebih cocok untuk laptop, sehingga grid 2 × 2 dipilih secara sadar.

**D28. Tooltip tab terminal menampilkan folder kerja dan perintah yang sedang berjalan.**
Alasan: pengguna tidak perlu membuka tab hanya untuk tahu isinya.

**D29. Klik notifikasi memfokuskan pane dan tab yang bersangkutan. Cmd+klik pada nama ambigu menampilkan pilihan.**
Alasan: notifikasi yang hanya membuka aplikasi memaksa pengguna mencari sendiri. Membuka file pertama yang cocok bisa membuka file yang salah tanpa disadari.

## 2026-10-24

**D30. Grid pane tidak memiliki batas tetap empat; jumlah pilihan mengikuti repo tersimpan dan jumlah terakhir yang dipulihkan.**
Susunan memakai grid seimbang dengan kolom `ceil(sqrt(jumlah pane))`; baris terakhir dapat memiliki slot kosong setelah pane terakhir, dan area yang melewati ukuran jendela dapat digulir. Slot pane tidak dihapus saat jumlah tampilan dikurangi; pilihan hanya membatasi pane yang terlihat, sementara pane lain dan sesi repo tetap siap ditampilkan kembali. Menu menyediakan jumlah 1 hingga jumlah repo tersimpan, atau jumlah pane saat ini bila lebih tinggi. Saat grid diperbesar, slot kosong diisi repo tersimpan terbaru yang belum terlihat. D30 menggantikan batas empat pada D4 dan preset tetap 1/2/4 pada D27.
Alasan: pengguna ingin mengelola banyak repo dalam satu jendela seperti multi-view CCTV. Batas tetap empat membuat repo tambahan tidak bisa ditampilkan berdampingan; grid dinamis mengikuti jumlah repo yang benar-benar tersedia.

**D31. Jumlah pane yang ditampilkan terpisah dari jumlah pane yang tersimpan.**
Pilihan Single View atau Grid hanya mengubah pane yang sedang tampak. Pane lain, hosting view yang sudah dibuat, repo, dan sesi terminalnya tetap tersedia; grid besar dapat digulir. Pane hanya dilepas dari workspace lewat aksi tutup pane/repo yang eksplisit.
Alasan: berpindah mode tampilan tidak boleh membuat workspace kehilangan pane yang sudah dibuka.

**D32. Repo yang tampil pada slot dapat dipilih langsung dari header pane.**
Jika repo pilihan sudah punya slot, slot tersebut dipindahkan ke posisi tampilan tanpa mengganti identitas pane atau menghentikan sesi. Jika belum punya slot, pane saat ini disimpan sebagai pane tersembunyi dan slot baru menampilkan repo pilihan.
Alasan: pengguna perlu memilih repo mana yang tampil dalam grid kecil sambil mempertahankan pane lain agar dapat ditampilkan kembali.

**D33. Tutup semua repo dari pane memproses pane satu per satu dan meminta konfirmasi untuk sesi terminal yang aktif.**
Pilihan **Hentikan dan Tutup** menghentikan seluruh tab terminal milik repo itu lalu menutupnya dari pane. **Jangan Tutup** mempertahankan repo dan prosesnya, kemudian antrean berlanjut ke pane berikutnya. Pane tanpa perintah aktif ditutup tanpa konfirmasi; sesi idle tetap hidup sesuai perilaku dasar. Repo tersimpan dan file worktree tidak dihapus.
Alasan: pengguna dapat membersihkan workspace sekaligus tanpa menghentikan proses yang sedang berjalan tanpa persetujuan per pane.

**D34. Menghapus repo dari Gridline hanya menghapus entri tersimpan, bukan folder di disk.**
Kelola Repo Tersimpan memungkinkan penghapusan satu entri atau pembersihan entri dengan path yang tidak tersedia. Aksi selalu meminta konfirmasi dan menghentikan sesi terminal terkait agar proses tidak tertinggal tanpa pane. File repo/worktree tetap aman di disk.
Alasan: daftar repo perlu bisa dirapikan tanpa menghapus pekerjaan pengguna secara permanen.

**D35. Tutup pane memakai tombol × langsung di pojok kanan atas dengan target klik 32×32 pt.**
Tombol tersedia pada pane berisi repo, pane kosong, dan pane dengan repo yang hilang. Menutup pane hanya melepas tampilan; sesi repo tetap hidup. Pane terakhir tidak dapat ditutup.
Alasan: aksi tutup pane harus terlihat dan mudah dijangkau tanpa membuka menu tindakan.

**D36. Konfirmasi penutupan repo memakai status perintah aktif, bukan status shell hidup.**
Tutup satu repo dan tutup semua repo sama-sama meminta konfirmasi hanya jika ada perintah terminal aktif. Prompt zsh idle tidak memicu konfirmasi; konfirmasi tetap menjelaskan bahwa sesi dipertahankan bila repo hanya dilepas dari pane.
Alasan: shell terminal yang hidup di prompt idle bukan proses kerja yang perlu konfirmasi, dan dua cara menutup repo harus memberi hasil yang sama.

**D37. Memilih repo untuk pane yang dituju memakai perilaku swap yang konsisten dari semua entry point.**
Pemilih header, repo terbaru, quick switcher, dan pemulihan worktree mengarahkan repo terpilih ke pane tujuan. Jika repo sudah berada pada pane lain, penempatan ditukar agar repo sebelumnya tetap berada di workspace.
Alasan: aksi yang dimulai dari pane tertentu harus memberi hasil di pane itu tanpa menduplikasi repo atau menyembunyikan slot secara tak terduga.

**D38. Toolbar menyediakan menu Aksi Workspace untuk pemilihan repo dan pengelolaan pane.**
Aksi **Tampilkan Satu Repo…** mengubah layout ke satu pane lalu membuka Quick Switcher. Jika perubahan menyembunyikan perintah terminal aktif, konfirmasi ditampilkan dahulu dan Quick Switcher dibuka hanya setelah pengguna menyetujui. Menu juga menyediakan pemilih repo pane aktif, pengelolaan repo tersimpan, dan tutup semua repo dari pane.
Alasan: pemilihan repo utama harus mudah ditemukan di toolbar, termasuk ketika repo yang diinginkan sedang tersembunyi di grid.

**D39. Kontrol workspace tidak memakai baris toolbar di dalam jendela.**
Aksi buka/pilih repo berada di menu bar **Repository**, dan pilihan jumlah pane berada di menu bar **Pane**. Menu aksi satu repo tetap membuka Quick Switcher dan mempertahankan konfirmasi untuk perintah aktif yang akan tersembunyi. Grid mengisi seluruh tinggi area konten jendela; pane kosong tetap menyediakan tombol **Buka Repo…**.
Alasan: menghilangkan chrome kontrol dari area jendela memberi ruang vertikal lebih besar untuk repo tanpa menghilangkan fungsi navigasi.

**D40. Tombol panah ditangani sesuai fokus keyboard.**
Jika daftar file diff fokus, ↑/↓ memilih file dan ⌥↑/⌥↓ memilih hunk. Jika terminal fokus, ↑/↓ tetap menjalankan history shell. Navigasi file hanya mencakup entri yang lolos filter yang terlihat.
Alasan: pintasan diff tidak boleh mengambil alih navigasi terminal, dan fokus visual harus menentukan konteks tombol panah.

**D41. Filter daftar diff menyaring pilihan dan preview secara bersamaan.**
Jika file terpilih tidak lolos filter aktif (file baru atau file besar), pilih file pertama yang lolos. Jika tidak ada file yang lolos, kosongkan pilihan dan preview. Perubahan ini menyelaraskan isi panel dengan daftar yang terlihat; pembatalan proses Git yang sudah berjalan tidak dijamin.
Alasan: menyembunyikan baris tetapi membiarkan preview file tersembunyi membuat hubungan pilihan dan isi panel membingungkan. Pengurangan CPU/RAM perlu diukur terpisah.
