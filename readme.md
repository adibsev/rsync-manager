
---

# 📦 Rsync Manager (Enterprise CLI Sync Tool)

Rsync Manager adalah tool CLI berbasis Bash untuk mengelola sinkronisasi folder menggunakan `rsync` dengan konsep **1 source = 1 destination**. Tool ini mendukung mode sinkronisasi multi-arah, manipulasi *ownership* lokal otomatis, dukungan password SSH, serta dilengkapi dengan script terpisah untuk otomatisasi via Crontab.

---

# 🚀 Fitur

* ✔ 1 Source → 1 Destination mapping
* ✔ Support local & SSH remote sync (via SSH Key atau Password/`sshpass`)
* ✔ Mode Sinkronisasi:
* **oneway** (source → destination)
* **twoway** (bidirectional sync berdasarkan *timestamp* terbaru)
* **mirror** (source dominant, menghapus file di tujuan yang tidak ada di sumber)


* ✔ **Smart Timestamp & FAT32 Support:** Menggunakan `--modify-window=2` untuk sinkronisasi akurat ke sistem file Android/FAT32/exFAT.
* ✔ **Auto Local Ownership:** Otomatis menyesuaikan *owner* dan *group* file lokal setelah sinkronisasi (mencegah *permission denied*).
* ✔ **Cron-Ready:** Dilengkapi script khusus (`rsync_cron.sh`) yang aman dijalankan di *background* via crontab tanpa interaksi.
* ✔ Config manager interaktif (add / delete / list)
* ✔ Logging otomatis (memisahkan log manual dan log cron)

---

# ⚙️ Requirement

Pastikan paket berikut terinstal di sistem Anda:

```bash
sudo apt update
sudo apt install rsync sshpass

```

Untuk sinkronisasi *remote*:

```bash
sudo apt install openssh-client

```

---

# 📥 Instalasi

```bash
git clone https://github.com/username/rsync-manager.git
cd rsync-manager

```

---

# 🔐 Keamanan & Hak Akses (Wajib)

Karena konfigurasi dapat menyimpan password SSH (opsional), sangat disarankan untuk membatasi hak akses file. Jalankan perintah berikut:

```bash
# Beri hak eksekusi pada script
chmod +x rsync_manager.sh
chmod +x rsync_cron.sh

# Amankan file konfigurasi dan log agar hanya bisa dibaca oleh Anda/Root
touch rsync_manager.conf rsync_manager.log
chmod 600 rsync_manager.conf
chmod 600 rsync_manager.log

```

---

# ▶️ Menjalankan CLI Mode (Manual)

Gunakan ini untuk menambah, menghapus, melihat konfigurasi, dan menjalankan sinkronisasi secara manual:

```bash
./rsync_manager.sh

```

---

# 🤖 Menjalankan via Crontab (Otomatis)

Gunakan script `rsync_cron.sh` untuk otomatisasi. Script ini berjalan tanpa *output* ke layar (silent) dan menggunakan *path absolute* sehingga sangat aman untuk Cron.

Buka konfigurasi crontab (gunakan `sudo` jika butuh akses `chown` root):

```bash
sudo crontab -e

```

Tambahkan baris berikut untuk sinkronisasi otomatis setiap 30 menit:

```bash
*/30 * * * * /path/lengkap/ke/rsync-manager/rsync_cron.sh >/dev/null 2>&1

```

---

# 📁 Struktur

```text
rsync-manager/
├── rsync_manager.sh      # Main CLI & Config Manager (Interaktif)
├── rsync_cron.sh         # Worker script untuk Crontab (Silent)
├── rsync_manager.conf    # File konfigurasi utama
└── rsync_manager.log     # Catatan aktivitas (Manual & CRON)

```

---

# ⚙️ Config Format

Konfigurasi menggunakan format 5 kolom yang dipisahkan oleh simbol `|`:

```text
source|mode|destination|password|owner_group

```

*(Catatan: `password` dan `owner_group` bersifat opsional, kosongkan saja jika menggunakan default SSH Key atau Owner bawaan).*

**Contoh isi `rsync_manager.conf`:**

```ini
[SYNC]
# 1. Sync lokal ke hardisk eksternal (Tanpa password, tanpa custom owner)
/home/user/Documents|twoway|/mnt/backup/Documents||

# 2. Sync ke server SSH menggunakan Password & mengubah owner lokal menjadi yourlocaluser:yourlocaluser
/home/yourlocaluser/Data|oneway|root@192.168.1.10:/backup/Data|P@ssw0rd123|yourlocaluser:yourlocaluser

# 3. Sync ke HP Android via SSH Key & Custom Owner (Mirror)
/home/user/Music|mirror|user@192.168.1.20:/sdcard/Music||user:user

```

---

# 📊 LOG

Aktivitas akan dicatat di `rsync_manager.log`. Log dari eksekusi crontab akan memiliki tag `[CRON]`.

```text
[2026-06-21 14:10:00] LOCAL OWNER FIX /home/yourlocaluser/Data -> yourlocaluser:yourlocaluser
[2026-06-21 14:10:01] ONEWAY /home/yourlocaluser/Data -> /backup/Data
[2026-06-21 14:30:00] [CRON] STARTING CRON SYNC
[2026-06-21 14:30:05] [CRON] LOCAL OWNER FIX /home/yourlocaluser/Data -> yourlocaluser:yourlocaluser
[2026-06-21 14:30:05] [CRON] SUCCESS ONEWAY: /home/yourlocaluser/Data -> /backup/Data
[2026-06-21 14:30:06] [CRON] FINISHED CRON SYNC

```

---

# 🧠 Use Case

* Backup data dari/ke Android (Termux/PPSSPP folder) menggunakan `--modify-window=2`.
* Sinkronisasi data game yang butuh perbaikan `chown` otomatis agar tidak bentrok akses *permission*.
* Sinkronisasi otomatis di latar belakang server via crontab tanpa intervensi manual.
* Alternatif Syncthing / Nextcloud CLI yang sangat ringan.

---

# ⚠️ WARNING

Mode `twoway` tidak memiliki resolusi konflik (*conflict resolution*) tingkat lanjut. Rsync hanya akan menimpa file berdasarkan *timestamp* modifikasi terbaru. Pastikan Anda memahami struktur data Anda sebelum menggunakan mode ini..