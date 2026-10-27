# Sinkron Antar Komputer Kasir

Satu **komputer server** di toko utama menyimpan data pusat. Komputer kasir
lain (cabang, maks. ±10) tetap bisa berjualan walau internet putus; datanya
dikirim otomatis ke server saat tersambung lagi.

```
 Komputer server (toko utama)            Komputer cabang
 ┌──────────────────────────┐            ┌──────────────────┐
 │ toko_server (selalu nyala)│◄── VPN ───│ Aplikasi Toko     │
 │ Aplikasi Toko = MASTER    │           │ (cabang)          │
 └──────────────────────────┘            └──────────────────┘
```

- **Master** (aplikasi di komputer server): satu-satunya tempat mengubah
  barang, harga, kategori, akun, toko, metode bayar, voucher, hak akses,
  dan bentuk struk.
- **Cabang**: berjualan, retur, ubah stok. Barang & akun diambil dari server.
- Faktur & riwayat stok semua komputer terkumpul di server dan ikut
  terkirim ke semua komputer (laporan di master mencakup semua cabang).
- Sinkron otomatis tiap 30 detik; atau Pengaturan › Terminal &
  Sinkronisasi › **Sinkron Sekarang**.

## 1. Pasang server (sekali, di komputer server)

1. Download artifact **toko-server-windows** dari GitHub Actions, ekstrak.
2. Klik kanan **PowerShell › Run as Administrator**, masuk ke folder itu:
   `powershell -ExecutionPolicy Bypass -File .\pasang-server.ps1`
3. Server berjalan otomatis setiap komputer menyala. Kode pairing ada di
   `C:\ProgramData\TokoServer\KODE-PAIRING.txt`.

Perintah lain (di folder `C:\Program Files\TokoServer\bin`):

| Perintah | Guna |
|---|---|
| `toko_server --code` | Lihat kode pairing |
| `toko_server --new-code` | Ganti kode pairing (setelah semua komputer tersambung) |
| `toko_server --terminals` | Daftar komputer yang tersambung |
| `toko_server --revoke K02` | Cabut komputer berkode K02 (mis. hilang/dicuri) |

**Backup**: salin folder `C:\ProgramData\TokoServer` (termasuk
`toko-server.key`; tanpa file kunci, database server tidak bisa dibuka).

## 2. Sambungkan komputer server (master)

Di aplikasi Toko pada komputer server, login admin:

1. Pengaturan › Terminal & Sinkronisasi › **Server pusat**.
2. Alamat: `127.0.0.1`, kode pairing, pilih **Komputer server (master)**.
3. Semua data komputer ini dikirim ke server.

## 3. Sambungkan komputer cabang

Pakai **instalasi baru** (belum ada transaksi).

1. Pengaturan › Terminal & Sinkronisasi: ganti **Kode terminal**
   (mis. `K02`, `CBG1`). Setiap komputer harus berbeda.
2. **Server pusat** → alamat server (IP VPN, lihat bagian 4), kode
   pairing, pilih **Komputer kasir cabang**.
3. Data barang & akun diambil dari server, lalu login lagi dengan akun dari
   server.

## 4. Cabang di lokasi lain: VPN (Tahap D)

Komputer cabang di luar jaringan toko butuh jalur aman ke server. Paling
mudah **Tailscale** (gratis untuk usaha kecil, tanpa setting router):

1. Buat akun di tailscale.com, pasang Tailscale di komputer server dan
   setiap komputer cabang, login dengan akun yang sama.
2. Di komputer server, lihat alamat Tailscale-nya (mis. `100.101.102.103`).
3. Di komputer cabang, isi alamat server dengan alamat itu.

Server **jangan** dibuka langsung ke internet (port forwarding) tanpa VPN.

## Catatan

- Jam komputer harus benar (tanggal faktur & laporan).
- Restore backup di komputer yang tersambung: putuskan sambungan dulu, lalu
  sambungkan ulang setelah restore.
- Stok di server dihitung dari riwayat stok. Saat master pertama kali
  tersambung, stok yang belum punya riwayat dicatat sebagai
  "Saldo awal sinkron".
