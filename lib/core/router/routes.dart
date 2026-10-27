class AppRoutes {
  const AppRoutes._();

  static const login = '/login';
  static const dashboard = '/dashboard';
  static const kasir = '/kasir';
  static const produk = '/produk';
  static const importProduk = '/produk/import';
  static const inputTabel = '/produk/tabel';
  static const cetakLabel = '/produk/label';
  static const stok = '/stok';
  static const laporan = '/laporan';
  static const pengaturan = '/pengaturan';
  static const kelolaAkun = '/pengaturan/akun';
  static const hakAkses = '/pengaturan/hak-akses';
  static const metodeBayar = '/pengaturan/pembayaran';
  static const voucher = '/pengaturan/voucher';
  static const kelolaToko = '/pengaturan/toko';
  static const strukPrinter = '/pengaturan/struk';

  /// Kategori barang (di kode/database disebut tag).
  static const kelolaKategori = '/pengaturan/kategori';
}
