import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:toko/core/database/app_database.dart';
import 'package:toko/core/database/seed.dart';
import 'package:toko/core/security/password_hasher.dart';

/// Biaya bcrypt minimum supaya tes cepat.
const testHasher = PasswordHasher(logRounds: 4);

/// Database SQLite di memori yang sudah berisi data seed.
Future<AppDatabase> createSeededDb() async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final db = AppDatabase(NativeDatabase.memory());
  await DatabaseSeeder(db, testHasher).seed();
  return db;
}
