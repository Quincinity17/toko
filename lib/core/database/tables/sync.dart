import 'package:drift/drift.dart';

/// Pengaturan key-value milik komputer ini (identitas terminal, status
/// sinkron, dll.). Tidak ikut disinkron.
@DataClassName('SettingRow')
class AppSettings extends Table {
  @override
  String get tableName => 'settings';

  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

enum OutboxEntity { sale }

/// Antrian data yang harus dikirim ke server. Diisi di dalam transaksi yang
/// sama dengan datanya (mis. checkout), lalu dikirim oleh mesin sinkron saat
/// ada koneksi. [sentAt] terisi setelah server mengonfirmasi.
@DataClassName('OutboxRow')
@TableIndex(name: 'idx_sync_outbox_pending', columns: {#sentAt, #id})
class SyncOutbox extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entity => textEnum<OutboxEntity>()();

  /// `uuid` baris yang dikirim (mis. `sales.uuid`).
  TextColumn get entityUuid => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get sentAt => dateTime().nullable()();
}
