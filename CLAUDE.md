# Toko — Aplikasi Kasir (POS) Desktop

Aplikasi kasir offline untuk toko retail kecil, pengganti iPOS. Target utama
Windows desktop; struktur disiapkan untuk Android/tablet.

## Menjalankan

Flutter dipin lewat fvm (`.fvmrc` → stable, saat ini 3.47.5). Selalu pakai `fvm flutter`.

```bash
fvm flutter pub get
fvm flutter run -d macos      # development di Mac
fvm flutter analyze && fvm flutter test
```

Build Windows **tidak bisa dari macOS**. `.exe` dibuat oleh GitHub Actions
(`.github/workflows/build-windows.yml`) setiap push ke `main`; hasilnya di-download
dari artifact `toko-windows` lalu dites di PC Windows.

## Arsitektur

- Feature-first: `lib/features/<fitur>/{data,domain,presentation}`.
  Fitur: auth, dashboard, products, import, sales, reports, settings.
- `lib/core/`: `theme/`, `widgets/` (komponen reusable), `router/`, `utils/`,
  `database/` (drift: tabel, DAO, seed), `security/` (bcrypt).
- Aturan: logika bisnis di repository/service (`data`/`domain`), bukan di widget.
  Widget hanya membaca provider Riverpod.
- State: Riverpod 3 (`Notifier`/`NotifierProvider`).
- Routing: go_router. `ShellRoute` + `AppShell` (sidebar) membungkus semua halaman
  utama; path di `core/router/routes.dart`.
- Database: drift, satu `AppDatabase` dibuat di `main()` lalu di-seed dan
  disuntikkan lewat `appDatabaseProvider.overrideWithValue`. File:
  `toko.sqlite` di `getApplicationSupportDirectory()` (Windows: `%APPDATA%\id.toko\toko`).
  Setelah mengubah tabel/DAO: `fvm dart run build_runner build`.
  Perubahan skema = naikkan `schemaVersion` + langkah di `onUpgrade`.

## Login & peran

- `UserRole` (`features/auth/domain/user_role.dart`) adalah sumber tunggal hak
  akses: `canAccess(path)` dan `homePath`. Router (`redirect`) dan sidebar
  sama-sama memakainya.
- Admin: semua halaman, mulai di Dashboard. Kasir: hanya halaman Kasir
  (tanpa Dashboard, permintaan user). URL terlarang dialihkan ke halaman awal peran.
- Sesi hanya di memori (`authControllerProvider`); aplikasi dibuka = login lagi.
- Layar login: ketik username + password (Enter pindah/masuk). Sengaja tidak
  menampilkan daftar akun atau petunjuk akun. Pesan gagal sama untuk user tidak
  ada / password salah: "Username atau password salah."
- Warna peran (admin biru, kasir hijau) dipakai di avatar/badge sidebar dan Kelola Akun.
- Password: bcrypt cost 10 di `Isolate.run` (`PasswordHasher`). Tes memakai cost 4.
- Akun seed: `admin / admin123`, `kasir / kasir123`. Tidak ditampilkan di
  aplikasi; harus diganti sebelum dipakai di toko.
- Menu user di bawah sidebar: Ganti Password, Keluar.

### Kelola akun (Pengaturan › Kelola Akun, `/pengaturan/akun`, khusus admin)

- `UserRepository` (`features/auth/data/user_repository.dart`): tambah, ubah
  (nama/peran/aktif; username tetap), reset password, ganti password sendiri,
  hapus. Melempar `AccountFailure` dengan pesan siap tampil.
- Aturan pengaman (di repository, bukan UI): hanya admin yang mengelola akun;
  admin tidak bisa menonaktifkan/menurunkan/menghapus diri sendiri; minimal
  satu admin aktif.
- Validasi isian di `AccountRules` (dipakai form dan repository): username
  3–32 karakter `[a-z0-9._]`, disimpan huruf kecil; password minimal 6.
- Akun nonaktif tidak bisa login.
- User yang sudah punya transaksi tidak bisa dihapus (harus dinonaktifkan).

## Kasir (`features/sales`)

Tata letak mengikuti layar iPOS yang diminta user, dengan gaya iOS:
tab **Transaksi Baru** dan **Hari Ini**.

- Transaksi Baru: kolom Jumlah + Kode/Barcode (selalu fokus kembali untuk
  scanner USB; Enter = cari persis kode/barcode, jika tidak ketemu → sheet cari),
  tabel keranjang (No, Kode, Nama, Jumlah ±, Satuan, Harga, Total), panel kanan:
  total besar, subtotal, voucher, Bayar.
- Tidak ada potongan manual (dihapus atas permintaan user). Satu-satunya
  potongan = **voucher** (F4 → popup kode). Keranjang hanya cek minimal belanja;
  status/tanggal/kuota dicek saat pasang (`findUsable`) dan ulang saat checkout.
- Bayar → **popup** (bukan bottom sheet, permintaan user) berisi pilihan metode
  bayar aktif. Tunai: uang diterima + chip Uang Pas & pecahan + kembalian.
  Non-tunai: dibayar pas + no. referensi opsional. `CheckoutService` menyimpan
  faktur, item, pemakaian voucher (`tryConsume` atomik terhadap kuota), stok,
  dan riwayat stok dalam satu transaction → popup sukses.
- Cari barang (F3 / kode tidak ketemu): pencarian per kata (urutan bebas; nama
  mengandung kata, atau kode/barcode diawali kata; `%`/`_` di-escape). Jika
  kosong → saran nama mirip (`FuzzyMatch` di `products/domain/fuzzy_match.dart`:
  jarak edit Damerau per kata, awalan kata, tanpa spasi; skor ≥ 0,7; maks 8)
  dengan keterangan "Mungkin maksud Anda:". Saran dihitung di Dart dari
  id+nama semua barang aktif.
- Hari Ini: hanya tabel faktur hari ini (tanpa kartu ringkasan/angka di label
  tab, permintaan user); klik = rincian.
- Shortcut: F2 / End = bayar, F3 = cari barang, F4 = voucher, ↑↓ + Enter di
  sheet cari, Esc menutup popup.
- Logika di domain murni (`cart.dart`, `invoice_number.dart`, `cash_suggestions.dart`,
  `vouchers/domain/voucher.dart`) dan `CheckoutService`; widget hanya memanggil
  `cartControllerProvider`.
- Pembulatan: total baris = round(qty × harga); potongan voucher tidak pernah
  melebihi subtotal (persen dibatasi `max_discount`).
- Stok boleh minus (penjualan tidak diblokir); baris diberi tanda bila qty > stok tercatat.
- Keranjang tetap ada saat pindah halaman, kosong otomatis saat ganti user.
- Belum ada (di luar tahap 1): pelanggan, sales, PPN, biaya lain, pending,
  buka laci, split payment (satu faktur dua metode), cetak struk (Langkah 6).

## Voucher & metode pembayaran (admin, Pengaturan › Penjualan)

- `/pengaturan/voucher`: daftar dikelompokkan Bisa dipakai / Terjadwal / Tidak
  berlaku; form: kode, keterangan, persen|nominal, maks potongan, min belanja,
  masa berlaku (tanggal, berlaku s.d. akhir hari), kuota, aktif. Kode yang sudah
  dipakai tidak bisa diubah; voucher terpakai tidak bisa dihapus.
- `/pengaturan/pembayaran`: tambah/ubah/aktif-nonaktif metode (jenis Tunai atau
  Non-tunai). Minimal satu aktif; yang sudah dipakai transaksi tidak bisa dihapus.
- Aturan ditegakkan di `VoucherRepository` / `PaymentMethodRepository` (hanya admin).

## Design system (gaya Apple / iOS)

- Warna: `AppColors` (ThemeExtension), akses via `context.colors`. Terang: latar
  #F2F2F7 + kartu putih; gelap: latar hitam + kartu #1C1C1E. Aksen #007AFF,
  status hijau/merah/oranye sistem Apple.
- Teks: `AppTypography` (Inter, di-bundle di `assets/fonts/Inter` agar offline),
  hierarki iOS: largeTitle 34, title1 28, title2 22, title3 20, headline/body 17,
  subheadline 15, footnote 13, caption 12. `displayAmount` untuk total kasir.
- Ukuran: `AppSpacing` (kelipatan 4), `AppRadius` (12–16 untuk kartu),
  `AppSizes.touchTarget` 48 / `buttonLarge` 56 (ramah layar sentuh).
- Animasi: `SpringCurve.smooth` (transisi halaman, sheet, sidebar) dan
  `SpringCurve.bouncy` (elemen kecil, item keranjang).
- Keputusan: kerangka `MaterialApp.router` (lokalisasi, scrollbar desktop), tetapi
  komponen yang tampil memakai Cupertino + widget sendiri. Tanpa splash Material.

### Komponen reusable (`lib/core/widgets/`)

| Widget | Kegunaan |
|---|---|
| `PressableScale` | Umpan balik tekan (mengecil) + hover + kursor tangan; dasar semua elemen yang bisa diklik |
| `AppButton` / `AppIconButton` | Tombol filled/tinted/gray/plain, ukuran small/medium/large, loading |
| `AppCard`, `GlassPanel` | Kartu membulat; panel kaca buram (BackdropFilter) |
| `InsetGroupedSection` / `InsetGroupedTile` / `TileIcon` | List bergaya Pengaturan iOS |
| `LargeTitlePage` | Halaman dengan large title + toolbar kaca saat digulir; `backLabel`/`onBack` untuk sub-halaman |
| `AppSidebar` | Sidebar kaca yang bisa diciutkan |
| `AppDialogs` | `alert`, `confirm`, `promptNumber`, `popup` (dialog tengah, Esc menutup), `pickDate`, `actionSheet`, `sheet` (bottom sheet dengan handle) |
| `EmptyState`, `LoadingState`, `SkeletonBox`, `ErrorBanner` | State kosong/loading/error |
| `StatCard` | Kartu angka ringkasan (dashboard, kasir) |
| `AppTextField` | Input dengan label, helper/error, mode password |
| `Shake` | Animasi getar untuk input salah |

Format angka/tanggal: `Fmt` di `core/utils/formatters.dart` (`Fmt.rupiah(10000)` → `Rp 10.000`).
Input angka: `parseIdNumber` (`1.500` → 1500, `0,5` → 0.5) dan `RupiahInputFormatter`
di `core/utils/number_input.dart`.

## Catatan tes widget

- Isolate (bcrypt) tidak jalan di fake async → tes memakai `_SyncHasher`.
- Kursor berkedip → pakai `settle()` bukan `pumpAndSettle()`.
- Akhiri setiap `testWidgets` dengan `unmount(tester)` agar stream drift tertutup.
- Tes yang memicu pesan voucher perlu `initializeDateFormatting('id_ID')`.

### Shortcut keyboard

- Ctrl+1..5: pindah halaman (Dashboard, Kasir, Produk, Laporan, Pengaturan)
- Ctrl+\\: ciutkan/tampilkan sidebar
- Kasir: F2 / End bayar, F3 cari barang, F4 voucher

## Skema database

Uang = INTEGER Rupiah; stok = REAL (mendukung kg/liter).

- v1 `users`: id, username (unik, huruf kecil), full_name, password_hash (bcrypt),
  role (`admin`|`kasir`, textEnum), is_active, created_at, last_login_at
- v2 (migrasi `from < 2` + 20 barang contoh, sekali saja):
  - `categories` (id, name unik), `units` (id, name unik)
  - `products`: code (unik), barcode (unik, null), name, category_id, unit_id,
    purchase_price, selling_price, stock (REAL), min_stock, is_active, created/updated_at
  - `sales`: invoice_no (unik), sale_date, user_id, item_count, subtotal,
    discount_percent (null), discount, total, paid, change_amount, payment_method
  - `sale_items`: snapshot product_code/name/unit_name, qty, price,
    discount_percent, purchase_price, subtotal
  - `stock_movements`: product_id, type (sale|import|adjust), qty_change (negatif
    = keluar), ref_id, note
- v3: `vouchers` (code unik huruf besar, name, type percent|amount, value,
  max_discount, min_purchase, start_date, end_date, quota, used_count, is_active),
  `payment_methods` (name unik, kind cash|nonCash, is_active, sort_order; 4 bawaan:
  Tunai, QRIS, Transfer Bank, Kartu Debit/Kredit). `sales` + voucher_id,
  voucher_code, payment_method_id, payment_ref. Faktur lama → Tunai.
  `sales.discount_percent` dan `sale_items.discount_percent` tidak diisi lagi
  (sisa potongan manual v2), tetap ada untuk faktur lama.
- PENTING migrasi: `createTable` memakai definisi TERBARU, jadi cabang `from < 2`
  membuat semua tabel baru sekaligus dan cabang `else if (from < 3)` hanya
  menambah yang belum ada. Pola ini harus dijaga untuk v4 dst.
- Tes migrasi (`checkout_service_test.dart`): v1 manual → v3, dan v2 dari
  `test/fixtures/schema_v2.sql` (skema asli DB user) → v3.
- Data contoh (`sample_products.dart`) dimasukkan di onCreate/onUpgrade, bukan di
  seeder start-up, supaya tidak muncul lagi jika user menghapusnya.

Rencana berikutnya: settings.

## Default yang dipakai (belum dikonfirmasi user)

- Diskon per transaksi: nominal (Rp) dan persen
- Metode bayar: tunai saja
- PPN: tidak dihitung

## Progres

- [x] Langkah 0 — Setup project, fvm, CI build Windows
- [x] Langkah 1 — Design system + app shell (sidebar, halaman kosong) — menunggu review tampilan
- [x] Langkah 2a — Database (drift) + tabel users, seed admin/kasir, login + role
- [x] Kelola akun + ganti password (permintaan tambahan)
- [x] Langkah 2b — 20 barang contoh (migrasi v2)
- [x] Langkah 5 — Transaksi penjualan + daftar transaksi hari ini (dikerjakan lebih dulu atas permintaan user)
- [x] Voucher + metode pembayaran, popup pembayaran, potongan manual dihapus (permintaan user)
- [ ] Langkah 3 — Master barang
- [ ] Langkah 4 — Import iPOS (butuh `sample_data/ipos_export.xlsx`)
- [ ] Langkah 6 — Struk 58 mm (PDF preview)
- [ ] Langkah 7 — Dashboard + laporan

## Catatan

- `design_reference/` dan `sample_data/` belum diberikan user.
- Bagian "Pratinjau Komponen" di halaman Pengaturan hanya untuk review desain; hapus setelah disetujui.
