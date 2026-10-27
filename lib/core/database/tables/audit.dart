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
  permissionsChanged,
  // Pengaturan & sistem
  storeChanged,
  paymentMethodChanged,
  voucherChanged,
  terminalChanged,
  backupChanged,
  restoreStaged,
  restoreApplied,
  salesPurged,
  sealsRebuilt,
  clockBack,
  // Sinkron
  syncPaired,
  syncReceived,
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

/// v18: catatan aktivitas dari komputer lain (diterima komputer master
/// lewat sinkron). Terpisah dari [AuditLog] karena rantai segelnya milik
/// komputer pengirim (kunci perangkatnya); di sini hanya kesinambungan
/// [prevHash] → [hash] yang bisa diperiksa (catatan yang dihapus di
/// cabang memutus rantai).
@DataClassName('RemoteAuditRow')
@TableIndex(name: 'idx_remote_audit_uuid', columns: {#uuid}, unique: true)
@TableIndex(name: 'idx_remote_audit_created', columns: {#createdAt})
class RemoteAuditLog extends Table {
  @override
  String get tableName => 'remote_audit_log';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text()();

  /// ID terminal pengirim.
  TextColumn get origin => text().nullable()();

  /// `audit_log.id` di komputer pengirim (urutan rantai).
  IntColumn get remoteId => integer()();
  DateTimeColumn get createdAt => dateTime()();

  /// Akun (id lokal komputer ini, dari uuid akun).
  IntColumn get userId => integer().nullable()();
  TextColumn get userName => text().nullable()();
  IntColumn get storeId => integer().nullable()();
  TextColumn get terminalCode => text().nullable()();

  /// Nama [AuditType] (teks biasa: jenis yang tidak dikenal versi ini tetap
  /// tersimpan).
  TextColumn get type => text()();
  TextColumn get summary => text()();
  TextColumn get data => text().nullable()();
  TextColumn get prevHash => text()();
  TextColumn get hash => text()();
}
