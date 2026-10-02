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
  Fitur: auth, dashboard, products, import, sales, reports, settings,
  stores (toko & cakupan toko), stock (halaman Stok), receipt (struk & printer),
  backup.
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
- Tiga peran (permintaan user): **Admin** (tidak terikat toko, semua halaman,
  mulai di Dashboard), **Supervisor** (terikat 1 toko: Kasir + Stok), **Kasir**
  (terikat 1 toko: hanya Kasir). Beda supervisor & kasir hanya hak ubah stok
  (`UserRole.canAdjustStock`, `AppUser.canAdjustStockAt`). URL terlarang
  dialihkan ke halaman awal peran.
- `users.store_id` wajib untuk supervisor/kasir, `null` untuk admin (dicek di
  `UserRepository._storeFor`). Akun dari toko nonaktif tidak bisa login.
- Sesi hanya di memori (`authControllerProvider`); aplikasi dibuka = login lagi.
- Layar login: ketik username + password (Enter pindah/masuk). Sengaja tidak
  menampilkan daftar akun atau petunjuk akun. Pesan gagal sama untuk user tidak
  ada / password salah: "Username atau password salah."
- Warna peran (admin biru, supervisor ungu `AppColors.purple`, kasir hijau) dipakai di avatar/badge sidebar dan Kelola Akun.
- Password: bcrypt cost 10 di `Isolate.run` (`PasswordHasher`). Tes memakai cost 4.
- Akun seed: `admin / admin123`, `kasir / kasir123`. Tidak ditampilkan di
  aplikasi; harus diganti sebelum dipakai di toko.
- Menu user di bawah sidebar: Ganti Password (admin saja), Keluar.
- **Password hanya bisa diganti admin** (keputusan user): kasir tidak punya menu
  ganti password dan `UserRepository.changeOwnPassword` menolak non-admin.
  Kasir minta admin mereset lewat Kelola Akun › Reset password.

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

## Multi-toko (`features/stores`, `features/stock`)

- Toko dikelola admin di Pengaturan › Kelola Toko (`/pengaturan/toko`,
  `StoreRepository`): nama unik, alamat, aktif; minimal satu aktif; toko yang
  sudah dipakai hanya dinonaktifkan. Data lama dipindah ke "Toko Utama" (v6).
- **Toko mengikuti akun** (keputusan user): komputer tidak terikat toko.
- **Stok per toko** dan **harga per toko** (keputusan user): `store_products`
  (store_id, product_id, stock, selling_price null = harga default
  `products.selling_price`). Baris dibuat saat dibutuhkan (`StoresDao.changeStock`
  / `setPrice`, upsert). `products.stock` tidak dipakai lagi sejak v6.
- `storeScopeProvider` (`stores/presentation/store_scope.dart`) = toko yang
  dipakai semua halaman. Supervisor/kasir: tokonya (tetap). Admin: dipilih di
  header sidebar (`pickStoreScope`), `null` = semua toko, disimpan di settings
  `admin.store_scope`; belum memilih + satu toko aktif = toko itu.
- Query barang menerima `storeId` (`ProductFilter.storeId`, `_StoreCols` di
  `ProductsDao`: subquery + `watchedTables`); `null` = stok dijumlah, harga default.
  `Product.sellingPrice` = harga toko, `defaultSellingPrice` = default.
- Kasir wajib satu toko (admin di "semua toko" diminta memilih); keranjang
  kosong saat toko berganti; `CheckoutService` menolak kasir dari toko lain.
  Faktur, riwayat stok (+ `user_id`), dan transaksi tertahan menyimpan store_id.
- Halaman **Stok** (`/stok`, admin & supervisor): daftar stok toko, popup
  Barang Masuk / Barang Keluar / Stok Opname + catatan + riwayat 20 terakhir
  (`StockRepository`, type `adjust`, catatan diawali nama mode).
- Form barang admin: harga jual = default; bagian "Stok & harga per toko".
  Import: harga jual = default, kolom Stok masuk ke satu toko tujuan (dipilih
  di langkah Periksa). Export: stok & harga toko yang dipilih.
- Laporan & dashboard mengikuti toko yang dipilih (`ReportRepository.storeId`,
  filter `?3` di `ReportsDao`); bagian "Per toko" + sheet Toko bila > 1 toko.

## Kasir (`features/sales`)

Tata letak mengikuti layar iPOS yang diminta user, dengan gaya iOS:
tab **Transaksi Baru** dan **Hari Ini**.

- Transaksi Baru: kolom Jumlah + Kode/Barcode (selalu fokus kembali untuk
  scanner USB; Enter = cari persis kode/barcode, jika tidak ketemu → sheet cari),
  tabel keranjang (No, Kode, Nama, Jumlah ±, Satuan, Harga, Total), panel kanan:
  total besar, Bayar, Batalkan.
- **Tidak ada potongan sama sekali**: potongan manual dihapus, lalu fitur voucher
  juga dihapus (keputusan user, Okt 2026). Total = subtotal.
- Bayar → **popup** (bukan bottom sheet, permintaan user) berisi pilihan metode
  bayar aktif. Tunai: uang diterima + chip Uang Pas & pecahan + kembalian.
  Non-tunai: dibayar pas + no. referensi opsional. `CheckoutService` menyimpan
  faktur (uuid, kode terminal), item, stok, riwayat stok, dan antrian
  `sync_outbox` dalam satu transaction → popup sukses.
- Cari barang (F3 / kode tidak ketemu): pencarian per kata (urutan bebas; nama
  mengandung kata, atau kode/barcode diawali kata; `%`/`_` di-escape). Jika
  kosong → saran nama mirip (`FuzzyMatch` di `products/domain/fuzzy_match.dart`:
  jarak edit Damerau per kata, awalan kata, tanpa spasi; skor ≥ 0,7; maks 8)
  dengan keterangan "Mungkin maksud Anda:". Saran dihitung di Dart dari
  id+nama semua barang aktif.
- **Tahan transaksi** (F4, permintaan user): pelanggan masih lihat-lihat →
  keranjang disimpan + catatan opsional, lalu dikosongkan untuk antrian
  berikutnya. Tombol Tertahan (F5, lencana jumlah) membuka daftar hari ini
  (catatan, jam, kasir, barang, total) → Lanjutkan / Hapus. Melanjutkan saat
  keranjang terisi = keranjang itu ditahan dulu (tanpa catatan). Disimpan di
  tabel `held_carts` (lokal, tidak disinkron, semua user di komputer ini
  melihatnya); harga mengikuti harga terbaru saat dilanjutkan, barang nonaktif
  dilewati dan diberi tahu. Hanya berlaku hari itu: yang lama tidak tampil dan
  dihapus `purgeExpired()` di `main()`. Logika di `HeldCartRepository`.
- Hari Ini: hanya tabel faktur hari ini (tanpa kartu ringkasan/angka di label
  tab, permintaan user); klik = rincian.
- Shortcut: F2 / End = bayar, F3 = cari barang, F4 = tahan, F5 = daftar
  tertahan, ↑↓ + Enter di sheet cari, Esc menutup popup.
- Logika di domain murni (`cart.dart`, `invoice_number.dart`, `cash_suggestions.dart`)
  dan `CheckoutService`; widget hanya memanggil `cartControllerProvider`.
- Pembulatan: total baris = round(qty × harga).
- Stok boleh minus (penjualan tidak diblokir); baris diberi tanda bila qty > stok tercatat.
- Keranjang tetap ada saat pindah halaman, kosong otomatis saat ganti user.
- Belum ada (di luar tahap 1): pelanggan, sales, PPN, biaya lain,
  split payment (satu faktur dua metode).

## Struk & printer (`features/receipt`, Pengaturan › Struk & Printer, `/pengaturan/struk`, admin)

- **Bentuk struk = template HTML + CSS yang diketik admin** (keputusan user:
  HTML/CSS sungguhan, bukan tag khusus). Variabel Mustache (`mustache_template`,
  lenient, nilai di-escape): `{{toko.nama}}`, `{{faktur.no}}`,
  `{{#barang}}…{{/barang}}`, `{{#kembali}}`, `{{#cetak_ulang}}`, dll. Daftar
  lengkap di `ReceiptVariables`; nilai dari `ReceiptData.toTemplateValues`
  (angka sudah diformat, kosong = `null`). Template bawaan:
  `default_receipt_html.dart`.
- `ReceiptHtml.render` → isi variabel → `inlineCss`: aturan `<style>` ditempel ke
  `style=""` (perender hanya baca inline; selector lewat `querySelectorAll`,
  `body` = pembungkus, at-rule diabaikan, inline paling kuat) + perbaikan ala
  browser (anak `display:flex` di-blockify, elemen kosong ber-border tetap
  digambar).
- Perender: `flutter_widget_from_html_core` di `ReceiptView` (kertas putih
  selebar titik: 58 mm = 384, 80 mm = 576; font Inter 20px). `ReceiptWidgetFactory`:
  gambar `data:` di-cache (logo), gambar internet tidak dimuat, baris flex
  diganti `ShrinkRow` (meniru `flex-shrink`: lebar intrinsik, menyusut
  sebanding bila kepanjangan). Border dashed tergambar solid.
- Cetak: `WidgetReceiptRasterizer` merender `ReceiptView` di luar layar
  (`renderWidgetToImage`: RenderView + BuildOwner sendiri) → `MonoBitmap`
  (ambang 160, baris putih bawah dibuang) → ESC/POS raster `GS v 0` per 128
  baris. Pratinjau di layar memakai widget yang sama = hasil cetak.
- Logo **per toko** (keputusan user): unggah PNG/JPG ≤ 5 MB → `logoToDataUri`
  (diperkecil ke lebar 576 titik bila lebih lebar, disimpan PNG data URI) →
  `{{logo}}` di template.
- **Bentuk struk per toko** (keputusan user): `ReceiptTemplate` (html, logo) =
  JSON di `stores.receipt_template` (v7; `null` = bawaan), ikut data toko supaya
  nanti tersinkron. Hanya admin. Struk faktur memakai template toko faktur
  (`ReceiptData.storeId`). Halaman admin: pilih toko → editor; "Terapkan ke Semua
  Toko" (`applyHtmlToAllStores`: hanya HTML, logo tiap toko tetap). Editor: simpan + pratinjau setelah jeda
  400 ms (disimpan dulu sebelum pindah toko); template rusak → pesan error,
  pratinjau terakhir tetap.
- **Printer per komputer, diatur dari layar Kasir** (keputusan user, semua peran):
  `PrinterConfig` (sambungan tidak ada / terpasang (USB) / jaringan IP:9100 /
  **Bluetooth-serial** (port COM + baud 9600–115200), **lebar
  kertas** 58/80, cetak otomatis, potong, buka laci saat tunai, pin 2/5, baris
  kosong akhir) = JSON di `settings` `printer.config`. Tombol "Printer Nota" /
  "Atur Printer" di header Kasir → `showPrinterSettingsDialog`; widget yang sama
  (`PrinterSettingsSection`) dipakai di halaman admin. Tes cetak memakai bentuk
  struk toko yang sedang dipakai. "Cek Sambungan" (`PrinterTransport.check`)
  menghubungi printer tanpa mencetak.
- Pengiriman (`PrinterTransport`): Windows = spooler RAW lewat FFI `win32`
  (`windows_spooler.dart`, `Isolate.run`), macOS/Linux = `lp -o raw`, jaringan =
  socket TCP, Bluetooth/serial = Windows `CreateFile(\\.\COMx)` + DCB 8-N-1
  lewat FFI (`windows_serial.dart`; daftar port dari registry SERIALCOMM),
  macOS/Linux `stty` + tulis ke `/dev/…`. macOS: entitlement `network.client` + `print`.
- Alur: popup Transaksi Berhasil → `ReceiptPrinter.afterCheckout` (cetak + laci
  satu pekerjaan, atau laci saja bila cetak otomatis mati) + status; gagal cetak
  tidak membatalkan transaksi. Ctrl+P cetak (ulang); rincian faktur "Cetak Ulang
  Struk"; tombol Buka Laci (F6) di kasir bila printer diatur (semua peran).
- Tes: `FakeTransport` + `FakeRasterizer` (`test/helpers/fake_printer.dart`);
  render sungguhan hanya di `render_preview_test.dart` (`runAsync`, memuat font
  Inter dulu karena font tes lebih lebar → flex meluap).

## Backup (`features/backup`, Pengaturan › Backup, admin)

- **Otomatis tiap N hari, simpan N terbaru per jenis** (permintaan user; bisa
  diatur admin: 1–30 hari, bawaan 7; 1–10 file, bawaan 2; settings
  `backup.interval_days` / `backup.keep`, nilai di luar batas dipotong). Backup
  baru menggantikan yang paling lama; jumlah dikurangi berlaku saat backup
  berikutnya (`BackupPolicy`, nama file memuat waktu
  `yyyyMMdd-HHmmss` → urutan nama = urutan waktu).
- Isi: `toko-database-*.sqlite` (salinan lengkap lewat `VACUUM INTO`, aman saat
  aplikasi dipakai) + `toko-barang-*.xlsx` (`exportProductsWorkbook`: satu sheet
  per toko, stok & harga toko itu, kolom sama dengan export → bisa di-import).
- `BackupScheduler` dimulai di `main()`: cek 30 detik setelah buka lalu tiap
  jam; jalan bila aktif dan backup terakhir ≥ jarak hari yang diatur. Gagal (mis. flashdisk
  dicabut) dicatat di `backup.last_error` dan tampil di Pengaturan.
- Settings: `backup.dir` (kosong = `Documents/Toko Backup`), `backup.enabled`,
  `backup.last_at`. Per komputer. Tombol Backup Sekarang & Buka Folder.
- Excel < 1.000 baris ditulis langsung; lebih besar lewat `Isolate.run`.
- Belum ada: pulihkan (restore) dari aplikasi.
- Tes widget: `pumpApp` mengarahkan backup ke folder sementara; status/backup
  memakai I/O sungguhan → tunggu dengan `runAsync` + `pump` bergantian.

## Arsitektur online/offline (disepakati, bertahap)

- **Tanpa layanan database cloud** (keputusan user 2026-10-01): server milik sendiri.
- Satu **komputer server** di toko (selalu nyala) menyimpan data pusat; komputer
  kasir lain (< 10, di lokasi lain via internet/VPN) memakai pola
  **offline-first**: database lokal + sinkron. Semua komputer, termasuk aplikasi
  di komputer server (lewat localhost), memakai alur yang sama.
- Server berjalan sebagai **layanan terpisah** (Windows service, Dart), bukan di
  dalam aplikasi kasir, supaya tetap jalan saat aplikasi ditutup.
- Turun (server → kasir): data master (barang, kategori, satuan,
  metode bayar, akun) per perubahan (nomor urut), dicek berkala + saat login +
  tombol manual. Naik (kasir → server): faktur lewat `sync_outbox`, dikirim
  segera jika tersambung, kirim ulang otomatis; server harus idempotent (uuid).
- **Data master hanya diubah admin di komputer server** (satu penulis, tanpa
  konflik). Stok di server dihitung dari `stock_movements`, bukan angka stok.
- Tahap: **A** fondasi lokal (selesai: terminal, uuid, outbox, nomor faktur
  `INV-<kode>-YYYYMMDD-0001`) → **B** layanan server + backup → **C** mesin
  sinkron + pairing + kunci edit master di komputer non-server → **D** VPN.
- Identitas terminal di `settings` (`terminal.id/code/mode`), dibuat oleh
  `TerminalRepository.ensureInitialized()` di `main()`. Pengaturan › Terminal &
  Sinkronisasi: kode (admin), ID, peran, jumlah antrian.

## Master barang (`/produk`, admin)

- Daftar: cari per kata (+ saran nama mirip bila kosong), filter status
  (Aktif/Nonaktif/Semua), kategori, stok menipis (stok ≤ stok minimum), urutan
  (nama, kode, stok terkecil, harga tertinggi, terakhir diubah), 50 per halaman.
- Form (sheet): nama, kode, barcode, kategori & satuan (`showOptionPicker`, bisa
  buat baru; satuan disimpan huruf besar), harga beli/jual (+ info untung atau
  peringatan rugi), stok, stok minimum, aktif.
- Aturan di `ProductRepository.save` (`ProductRules`): kode & barcode unik (kode
  tanpa peduli huruf besar), barcode tanpa spasi, harga ≥ 0. Kategori/satuan
  dibuat otomatis berdasarkan nama. Selisih stok → `stock_movements` jenis
  `adjust` ("Stok awal" / "Penyesuaian manual").
- Hapus: belum pernah terjual → hapus permanen (+ riwayat stoknya); sudah
  terjual → dinonaktifkan (hilang dari kasir, faktur lama utuh).

## Import & export barang

- Kolom file = `ProductField` (label: Kode, Barcode, Nama, Kategori, Satuan,
  Harga Beli, Harga Jual, Stok, Stok Minimum, Aktif). Export dan template memakai
  label ini → hasil export bisa langsung di-import ulang.
- `product_file_io.dart`: baca .xlsx/.csv (di `Isolate.run`; baris judul = baris
  pertama dengan ≥ 2 kolom terisi; delimiter CSV dideteksi otomatis), tulis
  .xlsx/.csv (BOM), template .xlsx (sheet Barang + Petunjuk). .xls lama tidak
  didukung (minta simpan ulang sebagai .xlsx).
- `guessMapping`: cocokkan judul kolom dengan sinonim (termasuk istilah iPOS:
  Kode Item, Nama Item, Jenis, Harga Pokok, Harga Jual 1, Stok Min). Bisa diubah
  manual di layar.
- `validateImport`: wajib kode/nama/harga jual, format angka Indonesia, kode &
  barcode duplikat di file, barcode milik barang lain. Baris error dilewati dan
  dilaporkan dengan nomor baris Excel.
- Kode yang sudah ada: Lewati / Timpa semua data (hanya kolom yang terisi di
  file) / Update stok & harga saja.
- `ProductImportService.run`: satu transaction, progress tiap 100 baris,
  kategori/satuan baru dibuat otomatis, perubahan stok → `stock_movements` jenis
  `import`. ±430 ms untuk 3.000 baris di tes (DB memori).
- UI: Produk › Export (popup: format, semua/sesuai filter, unduh template),
  Produk › Import (`/produk/import`, wizard 4 langkah). Pemilih file lewat
  `pickImportFileProvider` (di-override di tes).
- macOS butuh entitlement `files.user-selected.read-write` (sudah ditambahkan).

## Dashboard & laporan (admin)

- Data dari `ReportsDao` (SQL agregat; tanggal/jam memakai waktu lokal via
  `'unixepoch','localtime'`) → `ReportRepository` → model di
  `reports/domain/report_models.dart`. Nilai SUM dibaca dari `row.data` sebagai
  `num` (bisa INTEGER/REAL). Alias kolom kelompok = `grp` (hindari bentrok `name`).
- Definisi: omzet = Σ sales.total; harga pokok = Σ qty × purchase_price
  (snapshot di sale_items); laba kotor = omzet − pokok.
- Dashboard (`watch*`, otomatis terbarui): omzet hari ini vs kemarin, laba kotor
  & margin, transaksi & rata-rata belanja, stok menipis, grafik omzet 7 hari,
  terlaris hari ini, daftar stok menipis.
- Laporan: satu filter rentang (Hari Ini/7/30 Hari/Bulan Ini/pilih tanggal) +
  pembanding periode sebelumnya; bagian Ringkasan, Tren (harian omzet vs laba,
  per jam, per hari), Produk (ABC Pareto berdasarkan laba), Kategori, Stok (nilai
  persediaan, perkiraan habis = stok ÷ rata-rata 30 hari, tidak laku 30 hari),
  Pembayaran, Kasir & Terminal, Faktur. `ReportBundle` dimuat sekali
  per rentang; data lama tampil samar saat memuat rentang baru.
- Export Excel: satu file, satu sheet per bagian (`report_export.dart`).
- Grafik mengikuti skill dataviz: garis 2px, area 10% hanya satu seri, batang
  ≤ 24px ujung 4px, satu sumbu Y, kisi tipis, tooltip semua seri, legenda bila
  ≥ 2 seri, tabel sebagai versi non-grafik. Warna seri: `accent` lalu
  `chart2` (#D55181) — divalidasi `validate_palette.js` terang (#007AFF) dan
  gelap (#0A84FF). Oranye/hijau/merah = status, jangan dipakai untuk seri.

## Metode pembayaran (admin, Pengaturan › Penjualan)

- `/pengaturan/pembayaran`: tambah/ubah/aktif-nonaktif metode (jenis Tunai atau
  Non-tunai). Minimal satu aktif; yang sudah dipakai transaksi tidak bisa dihapus.
- Aturan ditegakkan di `PaymentMethodRepository` (hanya admin).

## Voucher — DIHAPUS (keputusan user, Okt 2026)

- Semua fitur voucher dihapus dari aplikasi: kasir (tombol/F4/popup), checkout,
  halaman admin, laporan & export. Folder `features/vouchers` dan `VouchersDao`
  sudah tidak ada.
- Yang **sengaja dipertahankan**: tabel `vouchers` (+ enum `VoucherType` di
  `tables/vouchers.dart`) dan kolom `sales.voucher_id/voucher_code/discount`,
  agar skema tidak berubah (tanpa migrasi) dan fitur bisa dihidupkan lagi dari
  riwayat git (commit sebelum penghapusan: `94be0cd`).
- Faktur lama yang punya potongan tetap tampil "Potongan" di rincian faktur dan
  di Ringkasan laporan (hanya jika > 0).

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
| `StatCard` | Kartu angka ringkasan + perubahan vs periode lalu (panah + %) |
| `TrendLineChart`, `ColumnChart`, `ChartLegend`, `ShareMeter` | Grafik garis/batang dan meter porsi (`charts.dart`) |
| `DataTableCard` / `CellText` | Tabel ringkas dalam kartu (versi tabel untuk setiap grafik) |
| `AppTextField` | Input dengan label, helper/error, mode password |
| `Shake` | Animasi getar untuk input salah |
| `showOptionPicker` | Popup pilih satu opsi dengan pencarian, opsi "buat baru" dan "tanpa …" |

Format angka/tanggal: `Fmt` di `core/utils/formatters.dart` (`Fmt.rupiah(10000)` → `Rp 10.000`,
`Fmt.compact` → `1,25 jt`, `Fmt.percent`, `Fmt.dayShort`). Simpan file: `saveFileAs`
di `core/utils/save_file.dart`.
Input angka: `parseIdNumber` (`1.500` → 1500, `0,5` → 0.5) dan `RupiahInputFormatter`
di `core/utils/number_input.dart`.

## Catatan tes widget

- Isolate (bcrypt) tidak jalan di fake async → tes memakai `_SyncHasher`.
- Kursor berkedip → pakai `settle()` bukan `pumpAndSettle()`.
- Akhiri setiap `testWidgets` dengan `unmount(tester)` agar stream drift tertutup.
- Tes yang memformat tanggal Indonesia perlu `initializeDateFormatting('id_ID')`.
- Kerja di isolate (baca file) butuh `tester.runAsync(() => Future.delayed(...))`.
- Tombol di halaman panjang: pakai `tapVisible` (ensureVisible dulu).
- Teks yang juga ada di sidebar (mis. "Produk"): batasi dengan
  `find.descendant(of: find.byType(LargeTitlePage), ...)`.
- Tampilan kosong di dalam kartu: pakai tinggi minimal (`BoxConstraints(minHeight)`),
  bukan `SizedBox(height)`, agar tidak meluap.
- `Override` Riverpod 3 diimpor dari `package:flutter_riverpod/misc.dart`.

### Shortcut keyboard

- Ctrl+1..6: pindah halaman (Dashboard, Kasir, Produk, Stok, Laporan, Pengaturan; sesuai menu peran)
- Ctrl+\\: ciutkan/tampilkan sidebar
- Kasir: F2 / End bayar, F3 cari barang, F4 tahan transaksi, F5 daftar tertahan,
  F6 buka laci; popup sukses: Enter transaksi baru, Ctrl+P cetak (ulang) struk

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
- v4: kolom `uuid` (nullable di skema, selalu terisi via `clientDefault(newUuid)`
  + backfill; indeks unik `idx_<tabel>_uuid`) di users, categories, units,
  products, vouchers, payment_methods, sales, sale_items, stock_movements.
  `sales.terminal_code`. Tabel `settings` (key/value) dan `sync_outbox`.
  Faktur lama otomatis diantrikan. Kolom voucher `quota`/`used_count` dihapus
  dari definisi (DB lama masih punya kolomnya, tidak dipakai).
- v5: `held_carts` (id, user_id, note, items JSON `[{id,code,name,qty}]`,
  item_count, total, created_at). Lokal saja, tanpa uuid.
- v6: `stores`, `store_products` (uuid, unik store+product); `store_id` di
  users, sales, stock_movements, held_carts; `stock_movements.user_id`.
  `_assignDefaultStore()` (onCreate & upgrade): buat "Toko Utama", isi
  store_id yang kosong, pindahkan `products.stock` ke store_products.
- v7: `stores.receipt_template` (TEXT null, JSON bentuk struk toko).
- Langkah `from < 4` idempoten (`_ensureColumn` cek `PRAGMA table_info`) karena
  bisa dicapai dari v1/v2/v3 yang tabelnya berbeda-beda.
- PENTING migrasi: `createTable` memakai definisi TERBARU, jadi cabang `from < 2`
  membuat semua tabel baru sekaligus dan cabang `else if (from < 3)` hanya
  menambah yang belum ada. Pola ini harus dijaga untuk v4 dst.
- Tes migrasi (`checkout_service_test.dart`): v1 manual, v2–v6 dari
  `test/fixtures/schema_v{2,3,4,5,6}.sql` (skema asli DB user) → versi terbaru.
  Saat menaikkan versi lagi: simpan skema DB sekarang sebagai fixture baru dulu.
- Data contoh (`sample_products.dart`) dimasukkan di onCreate/onUpgrade, bukan di
  seeder start-up, supaya tidak muncul lagi jika user menghapusnya.

Rencana berikutnya: settings.

## Keputusan bisnis yang dipakai

- Tidak ada potongan harga (potongan manual dan voucher dihapus, keputusan user).
- Metode bayar diatur admin (bawaan: Tunai, QRIS, Transfer Bank, Kartu).
- PPN: tidak dihitung (belum dikonfirmasi user).
- Laba = laba kotor (omzet − harga beli saat terjual). Laba bersih butuh fitur
  pengeluaran (belum ada).

## Progres

- [x] Langkah 0 — Setup project, fvm, CI build Windows
- [x] Langkah 1 — Design system + app shell (sidebar, halaman kosong) — menunggu review tampilan
- [x] Langkah 2a — Database (drift) + tabel users, seed admin/kasir, login + role
- [x] Kelola akun + ganti password (permintaan tambahan)
- [x] Langkah 2b — 20 barang contoh (migrasi v2)
- [x] Langkah 5 — Transaksi penjualan + daftar transaksi hari ini (dikerjakan lebih dulu atas permintaan user)
- [x] Metode pembayaran, popup pembayaran, potongan manual dihapus (permintaan user)
- [x] Fitur voucher dihapus seluruhnya (permintaan user; tabel DB dipertahankan)
- [x] Kasir tanpa Dashboard; tab Hari Ini tanpa ringkasan (permintaan user)
- [x] Tahan transaksi + catatan (F4/F5, berlaku hari itu; permintaan user)
- [x] Multi-toko: peran supervisor, stok & harga per toko, halaman Stok, Kelola Toko (permintaan user)
- [x] Saran nama barang mirip (FuzzyMatch) + pencarian per kata
- [x] Sinkron Tahap A — fondasi lokal (terminal, uuid, outbox, nomor faktur per terminal); kuota voucher dihapus

- [x] Langkah 3 — Master barang (daftar, filter, form, hapus/nonaktif)
- [x] Langkah 4 — Import barang (Excel/CSV, termasuk gaya iPOS) + Export + template
  (contoh file iPOS asli belum diberikan; pemetaan kolom berdasarkan nama kolom umum)
- [x] Langkah 6 — Struk dari template HTML + CSS (dicetak sebagai gambar ESC/POS 58/80 mm) + logo + buka laci, pratinjau langsung
- [x] Langkah 7 — Dashboard + laporan keuangan (8 bagian + export Excel)
- [ ] Sinkron Tahap B/C/D — server, mesin sinkron & pairing, VPN (**ditunda ke paling akhir**, keputusan user 2026-10-01; fokus fitur dulu)

## Catatan

- `design_reference/` dan `sample_data/` belum diberikan user.
