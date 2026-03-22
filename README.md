# EksaServer

**EksaServer** adalah server web Ruby asinkron berperforma tinggi yang dirancang untuk keandalan dan kecepatan. Dibangun di atas `nio4r`, server ini mampu menangani ribuan koneksi secara efisien melalui model multithreading dan multiprocess (cluster mode).

## Fitur Utama

- 🚀 **Performa Tinggi**: Event loop non-blocking berbasis `nio4r`.
- 🧵 **Auto-Scaling Threads**: Thread pool yang menyesuaikan diri dengan beban request.
- 🏗️ **Cluster Mode**: Worker process mandiri untuk memanfaatkan multi-core CPU.
- 🔐 **SSL/HTTPS Native**: Dukungan enkripsi SSL yang mudah via CLI atau config.
- 🔄 **Auto-Reload**: Pemuatan ulang otomatis saat ada perubahan kode (`--reload`).
- 📊 **Control Server**: API statistik real-time (memory, workers, threads).
- 🛠️ **Fleksibilitas Konfigurasi**: Mendukung DSL Ruby, variabel lingkungan (`.env`), dan opsi CLI.
- 🛡️ **Premium Error Page**: Tampilan error *glassmorphism* yang elegan dan informatif.

## Instalasi

Tambahkan ke Gemfile Anda:

```ruby
gem 'eksa-server'
```

Atau instal langsung:

```bash
gem install eksa-server
```

## Penggunaan Cepat

Jalankan di direktori aplikasi Rack Anda:

```bash
eksa-server
```

### Opsi CLI yang Berguna

| Opsi | Deskripsi |
|------|-----------|
| `-p, --port` | Port server (default: 3000 atau dari `.env`) |
| `-o, --host` | Host untuk bind (default: 0.0.0.0) |
| `-b, --bind URL` | Tambahkan bind (tcp://host:port atau unix://path). Bisa dipanggil berkali-kali. |
| `-R, --reload` | Aktifkan auto-reload saat file `.rb` berubah |
| `-c, --control` | Port untuk Control Server (statistik) |
| `-D, --daemonize` | Berjalan di latar belakang (Daemon Mode) |
| `-L, --log PATH` | Simpan log ke file tertentu |
| `--ssl-cert PATH` | Path ke sertifikat SSL (.crt) |
| `--ssl-key PATH` | Path ke private key SSL (.key) |

Contoh penggunaan lengkap:
```bash
eksa-server config.ru -p 443 --ssl-cert server.crt --ssl-key server.key -w 4 -R
```

## Konfigurasi

EksaServer otomatis memuat file `.env` jika tersedia. Anda juga bisa menggunakan file `config/eksa_server.rb`:

```ruby
# config/eksa_server.rb
threads 5, 20      # Min, Max threads
workers 2          # Jumlah worker
control_port 3001  # API Statistik

# SSL (Opsional)
ssl true
cert "path/to/cert.crt"
key "path/to/key.key"

on_worker_boot do |index|
  puts "Worker #{index} siap beraksi!"
end
```

## Statistik (Control Server)

Jika Control Server aktif, Anda bisa memantau kesehatan server via JSON:
`curl http://localhost:3001`

```json
{
  "workers": 2,
  "uptime": 3600,
  "version": "1.1.1",
  "memory_kb": 45120,
  "threads": { "spawned": 10, "waiting": 8 }
}
```

## Lisensi

Proyek ini dirilis di bawah [Lisensi MIT](LICENSE).
