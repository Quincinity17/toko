# Toko — Aplikasi Kasir (POS) Desktop

Aplikasi kasir offline untuk toko retail kecil, pengganti iPOS. Target utama
Windows desktop; juga Android (HP & tablet, APK).

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

APK Android: `fvm flutter build apk --release --split-per-abi` (HP umumnya
`app-arm64-v8a-release.apk`), juga GitHub Actions `build-android.yml` →
artifact `toko-android`. Kunci rilis: `android/upload-keystore.jks` +
`android/key.properties` (alias `toko`), **tidak di-commit** (.gitignore) —
wajib dibackup user; hilang = APK baru tidak bisa meng-update yang terpasang.
Tanpa key.properties rilis ditandatangani kunci debug. CI memakai secrets
`ANDROID_KEYSTORE_BASE64` + `ANDROID_KEYSTORE_PASSWORD` bila ada.
Emulator lokal: AVD `Pixel_9a` (`adb exec-out screencap -p` untuk cek tampilan).
Ikon Android dibuat kode: `fvm flutter test tool/generate_app_icon.dart`.

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
- **Pengaturan versi ringkas untuk supervisor & kasir** (permintaan user):
  hanya `/pengaturan` (bukan sub-halamannya) berisi Terminal & Sinkronisasi,
  Backup, Tampilan, Tentang. Kode terminal & pengaturan backup hanya dilihat
  (diubah admin; repository tetap menolak non-admin), tetapi Backup Sekarang
  dan Buka Folder bisa dipakai semua peran.
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
- **Retur / batal faktur** (permintaan user; `ReturnService`,
  `sales/data/return_service.dart`, domain `sale_return.dart`): rincian faktur
  › "Retur / Batalkan" (admin & supervisor toko faktur itu =
  `ReturnService.canReturn`; kasir tidak) → popup: jumlah per baris (± atau
  ketik, maks sisa), "Batalkan Semua", alasan wajib, tombol "Kembalikan Rp X".
  Disimpan sebagai **nota retur** `RET-<terminal>-YYYYMMDD-0001` = baris
  `sales` negatif (`return_of_id` = faktur asal, `return_reason`), baris
  qty/subtotal negatif (`return_of_item_id`), harga beli disalin; faktur asal
  TIDAK diubah. Laporan otomatis terpotong pada tanggal retur; jumlah
  transaksi (`ReportsDao._txCount/_txDistinct`) dan "terakhir terjual"
  mengabaikan nota retur; terlaris dashboard hanya qty bersih > 0. Uang
  kembali: sisa penuh = sisa subtotal persis, sebagian = round(qty × harga);
  faktur lama berpotongan hanya bisa batal semua (uang = total). Stok kembali
  (`StockMovementType.saleReturn`), outbox ikut. Tunai + printer/laci diatur →
  laci dibuka. Daftar Hari Ini: "Nota retur" (total merah) / "Dibatalkan"
  (dicoret) / "Diretur sebagian"; rincian menampilkan banner + "Sudah
  diretur"; nota retur tidak bisa dicetak ulang/diretur lagi.
- Belum ada (di luar tahap 1): pelanggan, sales, PPN, biaya lain,
  split payment (satu faktur dua metode), cetak struk retur.

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
- **Pulihkan (restore)** (admin; `RestoreService`, `backup/data/restore_service.dart`):
  ketuk file backup database di daftar, atau "Pulihkan…" → pilih backup /
  "Pilih file lain…" (flashdisk). `inspect` (sqlite3 langsung, read-only):
  header SQLite, `quick_check`, `user_version` 1..`AppDatabase.currentSchemaVersion`
  (lebih baru = tolak), ada tabel users+products, ada admin aktif → ringkasan
  (jumlah barang/transaksi, transaksi terakhir) → konfirmasi. `stage`: data
  sekarang disalin dulu (`VACUUM INTO` → `toko-sebelum-pulih-*.sqlite` di
  folder backup, tidak ikut dipangkas), backup disalin ke
  `toko.sqlite.restore` (+ `.json` nama sumber) di folder database.
  `RestoreService.applyPending()` di `main()` SEBELUM `AppDatabase` dibuka:
  hapus `toko.sqlite`(-wal/-shm/-journal), tukar; lalu settings
  `backup.last_restore` = "waktu|file" (tampil "Terakhir dipulihkan").
  Backup versi lama dimigrasi seperti biasa. Popup "Tutup Aplikasi"
  (`exitAppProvider`, di-override di tes); "Pemulihan menunggu" + Batalkan.
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

- **Di layar, `products.code` bernama "Barcode"** (wajib, unik, mis.
  BMM0000001) dan `products.barcode` bernama **"Barcode bawaan"** (opsional,
  barcode pabrik). Keputusan user: barang toko hanya pakai barcode. Nama di
  kode/database tetap `code`/`barcode`; kasir mencocokkan keduanya.
- **Barcode otomatis** (form barang baru, centang "Otomatis (+1 dari barcode
  terakhir)"): `CodeSequence` (`products/domain/code_sequence.dart`): awalan
  mengikuti barang terbaru (id terbesar) yang barcodenya berakhiran angka,
  angka terbesar di seri itu + 1, digit nol dipertahankan, dilewati bila
  bentrok; kode angka saja (EAN pabrik) dipakai hanya bila tidak ada seri
  berawalan huruf. Dihitung ulang saat simpan. Pilihan centang diingat di
  settings `products.auto_code`.

- Daftar: cari per kata (+ saran nama mirip bila kosong), filter status
  (Aktif/Nonaktif/Semua), kategori, stok menipis (stok ≤ stok minimum), urutan
  (nama, kode, stok terkecil, harga tertinggi, terakhir diubah), 50 per halaman.
- Form (sheet): nama, barcode (+ otomatis), barcode bawaan, satuan (`showOptionPicker`, bisa buat
  baru; disimpan huruf besar), kategori (banyak, lihat "Kategori barang"),
  harga beli/jual (+ info untung atau peringatan rugi), stok, stok minimum, aktif.
- Aturan di `ProductRepository.save` (`ProductRules`): kode & barcode unik (kode
  tanpa peduli huruf besar), barcode tanpa spasi, harga ≥ 0. Kategori (tag) &
  satuan dibuat otomatis berdasarkan nama. Selisih stok → `stock_movements` jenis
  `adjust` ("Stok awal" / "Penyesuaian manual").
- **Untung %** (permintaan user): isian "Untung (%)" di antara harga beli dan
  harga jual. `PriceMarkup` (`products/domain/price_markup.dart`): harga jual
  = beli × (1 + %), **dibulatkan ke atas ke Rp 100**; persen = 1 desimal.
  Isi % → harga jual dihitung (dan ikut berubah saat harga beli diubah);
  ketik harga jual → % menyesuaikan. Nonaktif bila harga beli kosong.
- **Input Tabel** (`/produk/tabel`, tombol di Produk; permintaan user: tanpa
  buka Excel): tabel ketik banyak barang baru (Barcode, Barcode bawaan, Nama,
  Kategori, Satuan (kosong = PCS), Harga beli, Untung %, Harga jual, Stok).
  Tab = kolom, Enter = baris bawah (baris baru otomatis), mulai 10 baris.
  "Barcode Otomatis" mengisi barcode kosong berurutan (`CodeSequence`, ikut
  barcode di tabel). Simpan: `BulkEntry.validate` (`products/domain/bulk_entry.dart`
  → `validateImport`; barcode yang sudah ada = error, tabel hanya barang baru)
  → `ProductImportService.run`; baris valid tersimpan & hilang dari tabel,
  baris error tetap merah dengan pesannya. Stok masuk ke toko yang dipilih
  (sama dengan import). Garis pemisah tipis antar kolom.
- **Peringatan nama sama/mirip** (permintaan user; dicek **sekali saat
  Simpan**, bukan sambil mengetik): `SimilarNames` (`products/domain/similar_names.dart`)
  = nama dinormalkan sama persis, atau `FuzzyMatch.score` **dua arah** ≥ 0,7,
  maks 2 per nama; juga antar baris di tabel. Pembanding: barang aktif
  (`ProductRepository.similarNames`, isolate bila baris × barang > 100.000).
  Popup `showSimilarNamesConfirm` (Periksa Lagi / Tetap Simpan) — peringatan,
  bukan larangan. Dipakai form Barang Baru (bukan ubah barang) dan Input
  Tabel (baris diberi catatan oranye). Nama yang sudah diperingatkan lalu
  "Periksa Lagi" tidak diperingatkan lagi bila disimpan tanpa diubah.
  Import Excel: daftar "Nama sama / mirip barang lain (tetap di-import)" di
  langkah Periksa (hanya baris barang baru). Kecepatan: kata dipecah sekali
  (`FuzzyMatch.scoreTokens`), pasangan disaring lewat kunci 2-huruf terjarang
  tiap nama (±2,7 dtk untuk 3.000 × 3.000 di tes).
- **Draf Input Tabel** (permintaan user): tombol kembali dengan isian → pilihan
  "Simpan sebagai Draf" / "Buang Isian". Keluar lewat sidebar = otomatis
  disimpan sebagai draf (`dispose`). Draf = JSON baris terisi
  (`BulkEntry.encodeDraft`) di settings `products.bulk_draft` (per komputer,
  bertahan setelah aplikasi ditutup); dibuka lagi → dimuat + keterangan
  "Melanjutkan draf (N baris)" dan tombol Buang Draf.
- **Ubah barang → konfirmasi perubahan** (permintaan user): `productChanges`
  (`products/domain/product_changes.dart`, fungsi murni) membandingkan barang
  lama + stok/harga per toko dengan isian baru → daftar "lama → baru" di popup
  (Periksa Lagi / Simpan). Tanpa perubahan = form langsung tertutup. Tag
  dibandingkan tanpa peduli huruf besar; harga toko = harga default dianggap
  "Harga default" (sama seperti cara menyimpannya).
- Hapus: belum pernah terjual → hapus permanen (+ riwayat stoknya); sudah
  terjual → dinonaktifkan (hilang dari kasir, faktur lama utuh).

## Kategori barang (= "tag" di kode; `products`: `tag.dart`, `TagRepository`, `/pengaturan/kategori`)

- **Kategori dan tag adalah SATU konsep, di layar bernama "Kategori"**
  (keputusan user): bisa lebih dari satu per barang dan berwarna. Contoh:
  Mainan, Boneka, Alat Tulis. Di kode/database tetap bernama tag (`Tag`,
  `tags`, `product_tags`, `Product.tags`, `ProductFilter.tagId`,
  `ProductDraft.tagNames`) — jangan buat konsep kategori kedua.
- Kategori lama (`categories`, `products.category_id`, satu per barang)
  dipindah jadi tag oleh migrasi v10 (`_categoriesToTags`, juga di onCreate):
  nama yang sudah ada dipakai ulang tanpa peduli huruf besar, warna
  bergiliran. Tabel/kolom lama tetap di skema tetapi **tidak dibaca/ditulis
  lagi** (seperti voucher).
- Tabel v8: `tags` (nama unik tanpa peduli huruf besar, `color` = nama
  `TagColor`, uuid) dan `product_tags` (PK product+tag, uuid, cascade).
  `TagsDao`: daftar + jumlah barang, `setProductTags` (ganti semua),
  `idsForNames` (buat yang belum ada).
- `Product.tags` diisi subquery `group_concat` (pemisah char 30/31) di
  `ProductsDao._tagList` + `watchedTables`, jadi daftar barang ikut terbarui
  saat tag diubah. Filter `ProductFilter.tagId` (EXISTS).
- `ProductDraft.tagNames`: `null` = kategori tidak diubah, `[]` = lepas semua.
  `TagRules`: nama 1–30 huruf, tanpa koma; `split` memecah "A, B; C".
- **Warna = penanda cepat** (permintaan user): `TagColor` = class nilai (bukan
  enum): 15 preset (`TagColor.values`, disimpan per nama) **atau warna bebas
  hex** (`TagColor.custom`, disimpan `#RRGGBB`; sama dengan preset → preset).
  Form tag: lingkaran pelangi "kustom" → `showColorWheelPicker`
  (`core/widgets/color_wheel.dart`: roda HSV sudut = hue, jarak = saturasi,
  slider kecerahan, kolom hex, pratinjau chip). Chip diisi warna penuh dengan
  teks `onColor` (gelap untuk warna terang); kotak inisial barang di daftar
  diisi warna tag pertama.
- Tag contoh (`insertSampleTags` di `sample_products.dart`: Laris, Promo,
  Anak-anak, Sarapan, Kebutuhan Pokok, Dingin, Mandi & Cuci) dipasang ke barang
  contoh saat onCreate dan migrasi v9 — hanya bila belum ada tag sama sekali.
  Tes yang butuh mulai tanpa tag memanggil `clearSampleTags(db)`.
- Kelola Kategori (admin): tambah/ubah nama & warna/hapus (kategori dilepas,
  barang tetap). Form barang: baris Kategori (chip + ×) → `showTagPicker`
  (pilih banyak, cari, Enter/"Buat kategori" membuat yang baru dengan warna
  bergiliran). Daftar barang & sheet cari kasir: chip/nama kategori; satu
  filter "Semua kategori".
- Import/export: kolom **Kategori** ("Mainan, Boneka"; sinonim termasuk
  Jenis/Tag/Label). Import: kategori baru dibuat (dihitung "kategori baru");
  mode Timpa mengganti kategori bila kolom terisi; Update stok & harga tidak
  menyentuh kategori.
- Laporan › Kategori (`ReportsDao.categorySales` dari tag): barang
  berkategori banyak dihitung di setiap kategori, tanpa kategori = "Tanpa
  kategori", porsi terhadap omzet total. Kolom kategori di tabel Produk =
  semua kategori barang (group_concat).

## Import & export barang

- Kolom file = `ProductField` (label: Barcode (= kode), Barcode Bawaan, Nama, Kategori (bisa
  "A, B"), Satuan, Harga Beli, Harga Jual, Stok, Stok Minimum, Aktif). Export dan template memakai
  label ini → hasil export bisa langsung di-import ulang.
- `product_file_io.dart`: baca .xlsx/.csv (di `Isolate.run`; baris judul = baris
  pertama dengan ≥ 2 kolom terisi; delimiter CSV dideteksi otomatis), tulis
  .xlsx/.csv (BOM), template .xlsx (sheet Barang + Petunjuk). .xls lama tidak
  didukung (minta simpan ulang sebagai .xlsx).
- Kolom "Barcode" di file menjadi kode hanya bila tidak ada kolom kode (Kode,
  Kode Item, …); jika ada, "Barcode" menjadi barcode bawaan (urutan sinonim).
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
- **Harga beli opsional** (permintaan user: sering lupa): kosong = 0 = "belum
  diisi" (tanpa perubahan skema). Form menampilkan kosong + "untung belum bisa
  dihitung"; konfirmasi perubahan "Belum diisi". Laporan: `no_cost_revenue`
  (`SalesSummary.revenueWithoutCost`, sale_items.purchase_price = 0) → baris
  peringatan "Omzet tanpa harga beli" di Rincian laba dan keterangan di kartu
  Laba kotor dashboard (laba terhitung terlalu tinggi).
- Dashboard (`watch*`, otomatis terbarui): omzet hari ini vs kemarin, laba kotor
  & margin, transaksi & rata-rata belanja, stok menipis, grafik omzet 7 hari,
  terlaris hari ini, daftar stok menipis.
- Filter toko di Dashboard (permintaan user): chip "Semua toko" + tiap toko aktif
  (hanya bila > 1 toko aktif), menulis ke `storeScopeProvider` (sama dengan
  pemilih di sidebar). Saat "Semua toko": kartu "Per toko hari ini" (omzet,
  transaksi, laba; `watchStoreSales`), ketuk = dashboard toko itu.
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

## Keamanan (permintaan user: mencegah kecurangan karyawan)

- **Database terenkripsi** (SQLite3MultipleCiphers via `hooks: user_defines:
  sqlite3: source: sqlite3mc` di pubspec; ChaCha20). Kunci dari rahasia
  perangkat `DeviceKeys` (`core/security/device_keys.dart`): 32 byte acak di
  `toko.key` samping database — Windows dikunci **DPAPI** + garam aplikasi
  (`windows_dpapi.dart`, FFI win32), Android/macOS diacak garam di folder
  pribadi. `databaseKey` & `sealKey` = HMAC turunan. `openDeviceDatabase()`
  (`core/database/database_bootstrap.dart`, dipanggil `main()`): buat kunci
  bila belum ada; database belum terenkripsi (instalasi lama / hasil restore)
  → `PRAGMA rekey`; kunci hilang/salah → `DatabaseLocked` →
  `DatabaseLockedApp` (pulihkan dari backup; TIDAK membuat database baru
  diam-diam karena akun bawaan akan aktif). `AppDatabase(executor, keys:)`;
  tes memakai `NativeDatabase.memory()` (tanpa enkripsi) + kunci tes.
- **Backup & salinan pengaman TIDAK terenkripsi** (`copyDatabasePlain`:
  VACUUM INTO lalu `rekey ''`) supaya bisa dipulihkan di komputer lain;
  konsekuensinya isi backup bisa dibaca → restore memeriksa segelnya
  (`BackupSeals`: utuh / diubah / tidak bisa diperiksa) dan memperingatkan.
- **Segel data** (`Sealer` HMAC-SHA256, `SealsDao`): kolom `seal` (v12) di
  users (id, username, role, toko, aktif, hash password), products (id, kode,
  harga beli/jual, aktif), store_products (toko, barang, stok, harga). Disegel
  ulang otomatis di DAO (`insertUser/updateUser`, `insertProduct/
  updateProduct`, `changeStock/setPrice`); `resealAll()` di onCreate, migrasi
  v12, seeder, dan setelah restore. **Login menolak akun yang segelnya tidak
  cocok** (role dinaikkan lewat DB Browser). Mengubah daftar kolom tersegel =
  perlu `resealAll()` di migrasi.
- **Catatan aktivitas** (`audit_log` v12, `AuditDao.append`, berantai:
  `hash` = HMAC(isi + `prev_hash`); tidak pernah diubah/dihapus aplikasi).
  `AuditType` (textEnum): login/gagal/keluar, sale & saleReturn (+ sidik jari
  isi faktur `saleDigest`), cartCleared, cartItemReduced, heldCartDeleted,
  drawerOpened (`CashierAudit` di `sales/data/cashier_audit.dart`, dipanggil
  layar kasir), barang/import/stok, akun, toko, metode bayar, terminal,
  backup, restore, sealsRebuilt, **clockBack** (otomatis bila jam mundur
  > 2 menit dari catatan terakhir). Ditulis di dalam transaksi tindakannya.
  Feature `features/audit`: `AuditRepository` (record, between, attention),
  domain `AuditEntry`/`AuditTypeInfo` (label, kategori, `needsAttention`).
- **Pemeriksaan keutuhan** (`IntegrityService`): mulai dari jangkar terakhir
  (sealsRebuilt/restoreApplied): rantai catatan, faktur vs catatan
  (diubah/dihapus/disisipkan), lubang nomor faktur, jam mundur, segel akun/
  barang/stok. Laporan › **Aktivitas** (`activity_section.dart`): kartu
  Keutuhan data (Periksa Ulang), "Perlu perhatian" per akun, daftar catatan
  + filter; HP = daftar. Nanti server menjalankan pemeriksaan yang sama
  (Tahap C).
- Batasan (jujur ke user): orang yang sangat ahli bisa membongkar aplikasi
  untuk mengambil kunci; yang ini baru tuntas dengan pemeriksaan server.

## Android / HP & tablet (permintaan user)

- Tata letak responsif (`AppBreakpoints` di `app_metrics.dart`): lebar
  < 700 = **HP** (`_CompactShell` di `app_shell.dart`: bilah atas ☰ + nama
  toko, sidebar jadi laci `Drawer`, `SafeArea` bawah; gutter 16), 700–1000 =
  sidebar otomatis ikon saja, ≥ 1000 = desktop. `LargeTitlePage`: judul &
  tombol aksi dalam `Wrap` (tombol turun bila tak muat). `InsetGroupedTile`:
  value terpotong, trailing `FittedBox.scaleDown`.
- Kasir HP: header (judul + ikon printer, tab di baris sendiri), isian scan
  ringkas (cari = ikon), `CartTable` < 560 px = daftar (nama, barcode·harga,
  ±, total; hapus = kurangi sampai 0), `CartSummaryPanel(compact)` = kartu
  bawah (total + Bayar, Tahan/Tertahan/Batalkan/Laci ikon). Hari Ini HP =
  daftar ringkas.
- `Device` (`core/utils/device.dart`, dari `dart:io` — **jangan pakai
  `defaultTargetPlatform`, di tes selalu Android**): `isTouch`/`isAndroid`,
  `withShortcut(label, key)` (petunjuk "(F2)" hanya di komputer). Tes:
  `Device.debugAndroidOverride = true` (lihat `test/android_mode_test.dart`).
- Perangkat sentuh: kolom barcode tidak autofocus/fokus ulang (keyboard layar
  menutupi keranjang), kecuali setelah scan/Enter (`focusEntry(force: true)`)
  supaya scanner Bluetooth bisa beruntun.
- Printer Android: Jaringan + **Bluetooth (SPP)** lewat kode native sendiri
  (`MainActivity.kt`, kanal `id.toko/bluetooth`: bondedDevices, send; izin
  BLUETOOTH_CONNECT diminta saat dipakai; hanya perangkat yang sudah
  dipasangkan) ← `AndroidBluetooth` (`receipt/data/android_bluetooth.dart`);
  `serialPort` = "Nama (MAC)". Plugin pihak ketiga sengaja tidak dipakai
  (print_bluetooth_thermal menambah kode native Windows/macOS). "Terpasang
  (USB)" & baud rate disembunyikan di Android. USB di Android belum ada.
- Backup Android: folder bawaan (penyimpanan aplikasi) tidak bisa diganti;
  "Buka Folder" → "Simpan Salinan…" (`saveFileAs`, Download/Drive).
- Manifest: INTERNET, BLUETOOTH(+ADMIN ≤ API 30), BLUETOOTH_CONNECT; label
  "Toko"; ikon adaptif (latar #007AFF).
- `test/layout_sizes_test.dart`: semua halaman admin di 4 ukuran (HP tegak/
  mendatar, tablet tegak/mendatar) + alur kasir, form barang, 8 bagian laporan
  di HP; luapan apa pun = gagal (lokasi kode penyebab ikut dilaporkan).

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
| `ChoiceChips` | Deretan kapsul pilih satu (filter rentang laporan, filter toko dashboard) |
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
- Bantuan tes aplikasi penuh (`pumpApp(size:)`, `login`, `fill`, `settle`,
  `unmount`, `tapVisible`) ada di `test/helpers/app_harness.dart`.
- Tes yang gagal di tengah (sebelum `unmount`) bisa menggantung karena stream
  drift; cari error pertama di log.
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
  - `categories` (id, name unik; tidak dipakai sejak v10), `units` (id, name unik)
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
- v8: `tags`, `product_tags` (tag jenis barang, banyak-ke-banyak).
- v9: data saja (tag contoh untuk barang contoh), skema sama dengan v8.
- v10: data saja: kategori lama → tag (kategori & tag jadi satu konsep).
  `categories`/`products.category_id` tidak dipakai lagi.
- v12: `audit_log` (catatan aktivitas berantai, indeks created_at) + kolom
  `seal` di users, products, store_products (segel data). Data lama disegel
  saat migrasi (`_baselineSeals`).
- v11: `sales.return_of_id` (+ indeks `idx_sales_return_of`),
  `sales.return_reason`, `sale_items.return_of_item_id` (nota retur).
  `StockMovementType.saleReturn` (textEnum, tanpa migrasi).
- Langkah `from < 4` idempoten (`_ensureColumn` cek `PRAGMA table_info`) karena
  bisa dicapai dari v1/v2/v3 yang tabelnya berbeda-beda.
- PENTING migrasi: `createTable` memakai definisi TERBARU, jadi cabang `from < 2`
  membuat semua tabel baru sekaligus dan cabang `else if (from < 3)` hanya
  menambah yang belum ada. Pola ini harus dijaga untuk v4 dst.
- Tes migrasi (`checkout_service_test.dart`): v1 manual, v2–v11 dari
  `test/fixtures/schema_v{2,…,11}.sql` (skema asli DB user) → versi terbaru.
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
- [x] Restore backup, peringatan nama mirip di import, retur/batal faktur (nota retur, v11)
- [x] Android: tata letak HP/tablet, printer Bluetooth, kunci rilis, ikon, CI APK
- [x] Keamanan: database terenkripsi, segel data, catatan aktivitas berantai, pemeriksaan keutuhan (Laporan › Aktivitas)
- [ ] Sinkron Tahap B/C/D — server, mesin sinkron & pairing, VPN (**ditunda ke paling akhir**, keputusan user 2026-10-01; fokus fitur dulu)

## Catatan

- `design_reference/` dan `sample_data/` belum diberikan user.
