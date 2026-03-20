# EksaServer

**EksaServer** adalah server web Ruby asinkron berperforma tinggi. Dibangun di atas `nio4r`, server ini dirancang untuk menangani ribuan koneksi secara efisien dengan dukungan multithreading dan multiprocess (cluster mode).

## Fitur Utama

- 🚀 **Performa Tinggi**: Menggunakan `nio4r` untuk event loop non-blocking.
- 🧵 **Multithreading Dinamis**: Thread pool yang menskalakan secara otomatis sesuai beban.
- 🏗️ **Cluster Mode**: Memanfaatkan multi-core CPU dengan worker process.
- 🔄 **Phased Restarts**: Update kode aplikasi tanpa downtime (Zero Downtime).
- 🛠️ **Konfigurasi DSL**: Pengaturan mudah melalui file `server.rb`.
- 🔌 **Rack Compliant**: Mendukung semua framework Ruby berbasis Rack (Rails, Sinatra, EksaFramework, dll).
- 🛡️ **Premium Error Page**: Halaman error *glassmorphism* yang elegan.

## Instalasi

Tambahkan baris ini ke Gemfile aplikasi Anda:

```ruby
gem 'eksa_server'
```

Lalu jalankan:

```bash
bundle install
```

Atau instal langsung melalui terminal:

```bash
gem install eksa_server
```

## Penggunaan Cepat

Cukup jalankan perintah berikut di direktori proyek Anda yang memiliki file `config.ru`:

```bash
eksa-server
```

Anda juga bisa menentukan file rack secara spesifik:

```bash
eksa-server app/config.ru -p 4000
```

## Konfigurasi

Buat file `config/eksa_server.rb` untuk pengaturan tingkat lanjut:

```ruby
threads 5, 20      # Min, Max threads
workers 2          # Aktifkan Cluster Mode
bind "tcp://0.0.0.0:3000"
# bind "unix:///tmp/eksa.sock"

on_worker_boot do |index|
  puts "Worker #{index} siap melayani!"
end
```

## Dokumentasi Lengkap

Untuk melihat panduan lengkap dan fitur interaktif, silakan kunjungi repositori resmi di GitHub atau jalankan secara lokal dari source code:
[https://github.com/IshikawaUta/eksa-server](https://github.com/IshikawaUta/eksa-server)

## Lisensi

Proyek ini dirilis di bawah [Lisensi MIT](LICENSE).
