import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:toko/core/database/app_database.dart';
import 'package:toko/core/database/database_bootstrap.dart';
import 'package:toko/core/database/seed.dart';
import 'package:toko/core/security/device_keys.dart';

import '../helpers/test_app.dart';

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('toko-enc-'));
  tearDown(() => dir.delete(recursive: true));

  File dbFile() => File(p.join(dir.path, 'toko.sqlite'));

  Future<AppDatabase> open() async {
    final r = await openDeviceDatabase(directory: () async => dir);
    expect(r, isA<DatabaseOpened>(), reason: '$r');
    return (r as DatabaseOpened).db;
  }

  test('database baru terenkripsi; tidak bisa dibuka tanpa kunci', () async {
    final db = await open();
    await DatabaseSeeder(db, testHasher).seed();
    expect(await db.select(db.products).get(), hasLength(20));
    await db.close();

    expect(isPlainSqlite(dbFile()), isFalse);
    final raw = sqlite3.open(dbFile().path);
    expect(
      () => raw.select('SELECT count(*) FROM products'),
      throwsA(isA<SqliteException>()),
    );
    raw.close();

    // Dibuka lagi dengan kunci perangkat: data utuh.
    final again = await open();
    expect(await again.select(again.products).get(), hasLength(20));
    await again.close();
  });

  test(
    'database lama (belum terenkripsi) dienkripsi tanpa kehilangan data',
    () async {
      final plain = AppDatabase(NativeDatabase(dbFile()));
      await DatabaseSeeder(plain, testHasher).seed();
      await plain.close();
      expect(isPlainSqlite(dbFile()), isTrue);

      final db = await open();
      expect(await db.select(db.products).get(), hasLength(20));
      expect(await db.usersDao.countUsers(), 2);
      await db.close();
      expect(isPlainSqlite(dbFile()), isFalse);
    },
  );

  test(
    'kunci hilang atau salah → terkunci, tidak membuat database baru',
    () async {
      final db = await open();
      await db.close();
      final keyFile = File(p.join(dir.path, DeviceKeyStore.fileName));

      await keyFile.delete();
      final missing = await openDeviceDatabase(directory: () async => dir);
      expect(missing, isA<DatabaseLocked>());
      expect((missing as DatabaseLocked).reason, contains('hilang'));

      await DeviceKeyStore.create(dir); // kunci lain
      final wrong = await openDeviceDatabase(directory: () async => dir);
      expect(wrong, isA<DatabaseLocked>());
      expect((wrong as DatabaseLocked).reason, contains('tidak cocok'));
      expect(isPlainSqlite(dbFile()), isFalse); // database lama tidak disentuh
    },
  );

  test(
    'salinan backup tidak terenkripsi (bisa dipulihkan di perangkat lain)',
    () async {
      final db = await open();
      await DatabaseSeeder(db, testHasher).seed();
      final copy = p.join(dir.path, 'backup.sqlite');
      await copyDatabasePlain(db, copy);
      await db.close();

      expect(isPlainSqlite(File(copy)), isTrue);
      final raw = sqlite3.open(copy);
      expect(raw.select('SELECT count(*) AS n FROM products').first['n'], 20);
      raw.close();
    },
  );
}
