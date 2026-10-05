import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:toko/core/database/app_database.dart';
import 'package:toko/core/database/seed.dart';
import 'package:toko/core/security/sealer.dart';
import 'package:toko/features/auth/data/auth_repository.dart';
import 'package:toko/features/auth/domain/app_user.dart';
import 'package:toko/features/backup/data/backup_service.dart';
import 'package:toko/features/backup/data/restore_service.dart';

import '../../helpers/test_app.dart';

void main() {
  late Directory tmp;
  late Directory support;
  late Directory backups;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('toko-restore-');
    support = await Directory(p.join(tmp.path, 'support')).create();
    backups = await Directory(p.join(tmp.path, 'backup')).create();
  });
  tearDown(() => tmp.delete(recursive: true));

  /// Database file sungguhan berisi data seed (seperti hasil backup).
  Future<String> backupFile(String name) async {
    final path = p.join(tmp.path, name);
    final db = AppDatabase(NativeDatabase(File(path)));
    await DatabaseSeeder(db, testHasher).seed();
    await db.close();
    return path;
  }

  group('inspect', () {
    test('backup aplikasi ini: ringkasan isi', () async {
      final info = RestoreService.inspect(await backupFile('b.sqlite'));
      expect(info.schemaVersion, AppDatabase.currentSchemaVersion);
      expect(info.products, 20);
      expect(info.sales, 0);
      expect(info.lastSale, isNull);
    });

    test('bukan database / versi lebih baru / tanpa admin → ditolak', () async {
      final text = File(p.join(tmp.path, 'catatan.sqlite'))
        ..writeAsStringSync('bukan database');
      expect(
        () => RestoreService.inspect(text.path),
        throwsA(isA<RestoreFailure>()),
      );

      final newer = await backupFile('baru.sqlite');
      sqlite3.open(newer)
        ..userVersion = 99
        ..close();
      expect(
        () => RestoreService.inspect(newer),
        throwsA(predicate((e) => '$e'.contains('versi lebih baru'))),
      );

      final noAdmin = await backupFile('tanpa-admin.sqlite');
      sqlite3.open(noAdmin)
        ..execute("UPDATE users SET is_active = 0 WHERE role = 'admin'")
        ..close();
      expect(
        () => RestoreService.inspect(noAdmin),
        throwsA(predicate((e) => '$e'.contains('admin aktif'))),
      );
    });
  });

  group('segel backup', () {
    test('utuh / diubah di luar aplikasi / dari perangkat lain', () async {
      final path = await backupFile('b.sqlite');
      final mine = Sealer.forTests();
      expect(
        RestoreService.inspect(path, sealer: mine).seals,
        BackupSeals.intact,
      );
      expect(
        RestoreService.inspect(path, sealer: Sealer(List.filled(32, 7))).seals,
        BackupSeals.unverifiable,
      );
      sqlite3.open(path)
        ..execute("UPDATE users SET role = 'admin' WHERE username = 'kasir'")
        ..close();
      expect(
        RestoreService.inspect(path, sealer: mine).seals,
        BackupSeals.tampered,
      );
    });
  });

  group('stage + applyPending', () {
    late AppDatabase db;
    late RestoreService service;
    late AppUser admin;

    setUp(() async {
      db = await createSeededDb();
      admin = await AuthRepository(db, testHasher).login('admin', 'admin123');
      service = RestoreService(
        db,
        BackupService(db, defaultFolder: () async => backups),
        supportDir: () async => support,
        clock: () => DateTime(2026, 10, 4, 10),
      );
    });
    tearDown(() => db.close());

    test('data sekarang disalin dulu, backup ditukar saat dibuka', () async {
      final source = await backupFile('toko-database-20261001-090000.sqlite');
      // Penanda: barang di backup berbeda dengan database sekarang.
      sqlite3.open(source)
        ..execute(
          "UPDATE products SET name = 'Dari Backup' WHERE code = 'BRG001'",
        )
        ..close();

      final safety = await service.stage(admin, source);
      expect(p.basename(safety), 'toko-sebelum-pulih-20261004-100000.sqlite');
      expect(File(safety).existsSync(), isTrue);
      expect(await service.hasPending(), isTrue);

      // Database "lama" di folder aplikasi (+ file WAL sisa).
      File(p.join(support.path, 'toko.sqlite')).writeAsStringSync('lama');
      File(p.join(support.path, 'toko.sqlite-wal')).writeAsStringSync('wal');

      final restored = await RestoreService.applyPending(
        supportDir: () async => support,
      );
      expect(restored, 'toko-database-20261001-090000.sqlite');
      expect(await service.hasPending(), isFalse);
      expect(
        File(p.join(support.path, 'toko.sqlite-wal')).existsSync(),
        isFalse,
      );

      final reopened = sqlite3.open(p.join(support.path, 'toko.sqlite'));
      expect(
        reopened
            .select("SELECT name FROM products WHERE code = 'BRG001'")
            .first['name'],
        'Dari Backup',
      );
      reopened.close();

      // Tidak ada yang menunggu → tidak melakukan apa-apa.
      expect(
        await RestoreService.applyPending(supportDir: () async => support),
        isNull,
      );
    });

    test('batalkan pemulihan; hanya admin', () async {
      final source = await backupFile('b.sqlite');
      await service.stage(admin, source);
      await service.cancelPending();
      expect(await service.hasPending(), isFalse);

      final kasir = await AuthRepository(
        db,
        testHasher,
      ).login('kasir', 'kasir123');
      expect(
        () => service.stage(kasir, source),
        throwsA(isA<RestoreFailure>()),
      );
    });
  });
}
