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
  `database/` (drift, mulai Langkah 2).
- Aturan: logika bisnis di repository/service (`data`/`domain`), bukan di widget.
  Widget hanya membaca provider Riverpod.
- State: Riverpod 3 (`Notifier`/`NotifierProvider`).
- Routing: go_router. `ShellRoute` + `AppShell` (sidebar) membungkus semua halaman
  utama; path di `core/router/routes.dart`.

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
| `LargeTitlePage` | Halaman dengan large title + toolbar kaca saat digulir |
| `AppSidebar` | Sidebar kaca yang bisa diciutkan |
| `AppDialogs` | `alert`, `confirm`, `actionSheet`, `sheet` (bottom sheet dengan handle) |
| `EmptyState`, `LoadingState`, `SkeletonBox` | State kosong/loading |

Format angka/tanggal: `Fmt` di `core/utils/formatters.dart` (`Fmt.rupiah(10000)` → `Rp 10.000`).

### Shortcut keyboard

- Ctrl+1..5: pindah halaman (Dashboard, Kasir, Produk, Laporan, Pengaturan)
- Ctrl+\\: ciutkan/tampilkan sidebar
- (Langkah 5) F2 bayar, F3 cari barang

## Rencana skema database (Langkah 2)

Uang = INTEGER Rupiah; stok = REAL (mendukung kg/liter).
users, categories, units, products, sales, sale_items (snapshot nama/harga/satuan),
stock_movements, settings. Detail lengkap ditulis saat tabel dibuat.

## Default yang dipakai (belum dikonfirmasi user)

- Diskon per transaksi: nominal (Rp) dan persen
- Metode bayar: tunai saja
- PPN: tidak dihitung
- Kasir hanya akses Kasir + Dashboard; Produk/Import/Laporan/Pengaturan khusus Admin

## Progres

- [x] Langkah 0 — Setup project, fvm, CI build Windows
- [x] Langkah 1 — Design system + app shell (sidebar, halaman kosong) — **menunggu review tampilan**
- [ ] Langkah 2 — Database (drift), seed, login + role
- [ ] Langkah 3 — Master barang
- [ ] Langkah 4 — Import iPOS (butuh `sample_data/ipos_export.xlsx`)
- [ ] Langkah 5 — Transaksi penjualan
- [ ] Langkah 6 — Struk 58 mm (PDF preview)
- [ ] Langkah 7 — Dashboard + laporan

## Catatan

- `design_reference/` dan `sample_data/` belum diberikan user.
- Bagian "Pratinjau Komponen" di halaman Pengaturan hanya untuk review desain; hapus setelah disetujui.
