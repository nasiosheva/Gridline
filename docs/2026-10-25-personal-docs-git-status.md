# Status Git `personal-docs` — 2026-10-25

Aturan `personal-docs/` dihapus dari `.gitignore` agar dokumen di folder tersebut terlihat sebagai file **untracked** dalam `git status`. Isi folder tidak termasuk dalam tree `main` dan tetap disimpan lokal.

Status yang diharapkan pada checkout yang memiliki catatan lokal adalah `?? personal-docs/`. Jangan stage, commit, atau push isinya; pilih file lain secara eksplisit saat menyiapkan commit. Karena folder ini tidak diabaikan Git, `git add -A` dapat memasukkannya tanpa sengaja.

Verifikasi: `git ls-tree -r main -- personal-docs` tidak menghasilkan file, sedangkan file catatan lokal tetap ada dan untracked. Perubahan aturan Git ini tidak memerlukan build atau test aplikasi.
