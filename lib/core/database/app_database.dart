import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/auth/domain/user_role.dart';
import 'daos/users_dao.dart';
import 'tables/users.dart';

part 'app_database.g.dart';

/// Database lokal SQLite (drift). Satu instance untuk seluruh aplikasi,
/// dibuat di `main()` dan disuntikkan lewat [appDatabaseProvider].
///
/// Riwayat skema:
/// - v1: users
@DriftDatabase(tables: [Users], daos: [UsersDao])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openDefault());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // Tambahkan langkah migrasi per versi di sini, contoh:
      // if (from < 2) await m.createTable(products);
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// File `toko.sqlite` di folder data aplikasi
  /// (Windows: %APPDATA%\id.toko\toko).
  static QueryExecutor _openDefault() {
    return driftDatabase(
      name: 'toko',
      native: const DriftNativeOptions(
        databaseDirectory: getApplicationSupportDirectory,
      ),
    );
  }
}

final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('Di-override di main()'),
);
