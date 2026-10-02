import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:toko/core/database/app_database.dart';
import 'package:toko/core/database/seed.dart';
import 'package:toko/core/security/password_hasher.dart';
import 'package:toko/features/sync/data/terminal_repository.dart';

/// Biaya bcrypt minimum supaya tes cepat.
const testHasher = PasswordHasher(logRounds: 4);

/// Database SQLite di memori yang sudah berisi data seed.
Future<AppDatabase> createSeededDb() async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final db = AppDatabase(NativeDatabase.memory());
  await DatabaseSeeder(db, testHasher).seed();
  await TerminalRepository(db).ensureInitialized();
  return db;
}

/// Id "Toko Utama", toko bawaan database baru (tempat akun seed `kasir`).
Future<int> mainStoreId(AppDatabase db) async =>
    (await (db.select(db.stores)..limit(1)).getSingle()).id;

/// Menghapus tag contoh (database baru sudah berisi tag contoh) untuk tes
/// yang butuh mulai tanpa tag.
Future<void> clearSampleTags(AppDatabase db) async {
  await db.delete(db.productTags).go();
  await db.delete(db.tags).go();
}
