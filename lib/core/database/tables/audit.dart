import 'package:drift/drift.dart';

import '../uuid.dart';

/// Jenis catatan aktivitas. Disimpan sebagai nama (textEnum), jadi urutan
/// boleh berubah dan nilai baru boleh ditambah tanpa migrasi.
enum AuditType {
  // Login
  login,
  loginFailed,
  logout,
  // Kasir
  sale,
  saleReturn,
  cartCleared,
  cartItemReduced,
  heldCartDeleted,
  drawerOpened,
  // Barang & stok
  productCreated,
  productUpdated,
  productDeleted,
  productsImported,
  stockAdjusted,
  // Akun
  userCreated,
  userUpdated,
  userPasswordReset,
  userDeleted,
  passwordChanged,
  // Pengaturan & sistem
  storeChanged,
  paymentMethodChanged,
  terminalChanged,
  backupChanged,
  restoreStaged,
  restoreApplied,
  sealsRebuilt,
  clockBack,
}

/// v12: catatan aktivitas berantai. Setiap baris menyimpan [hash] =
/// HMAC(kunci perangkat, isi baris + [prevHash] baris sebelumnya), jadi baris
/// yang dihapus/diubah di luar aplikasi memutus rantai (lihat
/// `IntegrityService`). Tidak pernah diubah atau dihapus aplikasi.
@DataClassName('AuditRow')
@TableIndex(name: 'idx_audit_log_created', columns: {#createdAt})
class AuditLog extends Table {
  @override
  String get tableName => 'audit_log';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().nullable().clientDefault(newUuid)();
  DateTimeColumn get createdAt => dateTime()();

  /// Pelaku (tanpa foreign key: akun boleh dihapus, catatannya tetap).
  IntColumn get userId => integer().nullable()();
  TextColumn get userName => text().nullable()();
  IntColumn get storeId => integer().nullable()();
  TextColumn get terminalCode => text().nullable()();
  TextColumn get type => textEnum<AuditType>()();

  /// Kalimat siap tampil, mis. "Batal transaksi 3 barang (Rp 45.000)".
  TextColumn get summary => text()();

  /// Rincian JSON (isi keranjang, perubahan lama → baru, dll.).
  TextColumn get data => text().nullable()();
  TextColumn get prevHash => text()();
  TextColumn get hash => text()();
}
