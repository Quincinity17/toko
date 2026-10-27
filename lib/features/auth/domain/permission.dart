import 'user_role.dart';

enum PermissionGroup {
  pages('Halaman'),
  cashier('Kasir');

  const PermissionGroup(this.label);
  final String label;
}

/// Hak akses yang bisa diatur admin untuk peran Supervisor dan Kasir
/// (Pengaturan › Hak Akses Peran). Admin selalu punya semuanya.
///
/// Disimpan di tabel `role_permissions` sebagai nama enum; nama yang tidak
/// dikenal (versi aplikasi lain) diabaikan, jadi urutan boleh berubah dan
/// nilai baru boleh ditambah tanpa migrasi skema.
enum Permission {
  viewDashboard(
    PermissionGroup.pages,
    'Dashboard',
    'Ringkasan penjualan hari ini di tokonya.',
  ),
  viewStock(
    PermissionGroup.pages,
    'Halaman Stok',
    'Melihat stok barang di tokonya.',
  ),
  adjustStock(
    PermissionGroup.pages,
    'Ubah stok',
    'Barang masuk, barang keluar, dan stok opname di tokonya.',
  ),
  viewReports(
    PermissionGroup.pages,
    'Laporan',
    'Laporan penjualan & laba tokonya, termasuk export Excel. Catatan '
        'aktivitas tetap khusus admin.',
  ),
  returnSale(
    PermissionGroup.cashier,
    'Retur / batalkan faktur',
    'Mengembalikan barang dan uang dari faktur di tokonya.',
  ),
  useVoucher(
    PermissionGroup.cashier,
    'Pakai voucher',
    'Memasang kode voucher promo di keranjang.',
  ),
  reduceCartItem(
    PermissionGroup.cashier,
    'Kurangi / hapus barang di keranjang',
    'Jika dimatikan, barang yang sudah di-scan tidak bisa dikurangi; '
        'salah scan hanya bisa diatasi dengan membatalkan transaksi.',
  ),
  clearCart(
    PermissionGroup.cashier,
    'Batalkan transaksi',
    'Mengosongkan keranjang yang belum dibayar.',
  ),
  deleteHeldCart(
    PermissionGroup.cashier,
    'Hapus transaksi tertahan',
    'Membuang keranjang yang ditahan tanpa dibayar.',
  ),
  openDrawer(
    PermissionGroup.cashier,
    'Buka laci tanpa transaksi',
    'Tombol Buka Laci (F6).',
  ),
  reprintReceipt(
    PermissionGroup.cashier,
    'Cetak ulang struk',
    'Mencetak lagi struk faktur yang sudah dibayar.',
  ),
  printerSettings(
    PermissionGroup.cashier,
    'Atur printer',
    'Mengubah sambungan & pengaturan printer nota di komputer ini.',
  );

  const Permission(this.group, this.label, this.description);

  final PermissionGroup group;
  final String label;
  final String description;

  static Permission? byName(String name) {
    for (final p in values) {
      if (p.name == name) return p;
    }
    return null;
  }
}

/// Hak akses bawaan = perilaku aplikasi sebelum hak akses bisa diatur.
class PermissionRules {
  const PermissionRules._();

  /// Peran yang hak aksesnya bisa diatur (admin selalu semua).
  static const editableRoles = [UserRole.supervisor, UserRole.kasir];

  static const _cashierBasics = {
    Permission.useVoucher,
    Permission.reduceCartItem,
    Permission.clearCart,
    Permission.deleteHeldCart,
    Permission.openDrawer,
    Permission.reprintReceipt,
    Permission.printerSettings,
  };

  static Set<Permission> defaults(UserRole role) => switch (role) {
    UserRole.admin => Permission.values.toSet(),
    UserRole.supervisor => {
      ..._cashierBasics,
      Permission.viewStock,
      Permission.adjustStock,
      Permission.returnSale,
    },
    UserRole.kasir => {..._cashierBasics},
  };

  /// Menyalakan/mematikan [p] beserta yang bergantung padanya: ubah stok
  /// butuh halaman Stok.
  static Set<Permission> toggle(
    Set<Permission> current,
    Permission p,
    bool granted,
  ) {
    final next = {...current};
    if (granted) {
      next.add(p);
      if (p == Permission.adjustStock) next.add(Permission.viewStock);
    } else {
      next.remove(p);
      if (p == Permission.viewStock) next.remove(Permission.adjustStock);
    }
    return next;
  }
}
