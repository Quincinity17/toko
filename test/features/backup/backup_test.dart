import 'dart:io';

import 'package:drift/native.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:toko/core/database/app_database.dart';
import 'package:toko/features/auth/data/auth_repository.dart';
import 'package:toko/features/auth/domain/app_user.dart';
import 'package:toko/features/backup/data/backup_service.dart';
import 'package:toko/features/backup/domain/backup_policy.dart';
import 'package:toko/features/products/data/product_repository.dart';
import 'package:toko/features/stores/data/store_repository.dart';

import '../../helpers/test_app.dart';

void main() {
  group('BackupPolicy', () {
    test('jatuh tempo seminggu sekali', () {
      final last = DateTime(2026, 10, 1, 9);
      expect(BackupPolicy.isDue(null, last), isTrue);
      expect(BackupPolicy.isDue(last, DateTime(2026, 10, 8, 8, 59)), isFalse);
      expect(BackupPolicy.isDue(last, DateTime(2026, 10, 8, 9)), isTrue);
    });

    test('hanya 2 terbaru per jenis yang disimpan', () {
      final names = [
        'toko-database-20261001-090000.sqlite',
        'toko-database-20261015-090000.sqlite',
        'toko-database-20261008-090000.sqlite',
        'toko-barang-20261001-090000.xlsx',
        'catatan.txt',
      ];
      expect(BackupPolicy.toDelete(names, BackupKind.database), [
        'toko-database-20261001-090000.sqlite',
      ]);
      expect(BackupPolicy.toDelete(names, BackupKind.products), isEmpty);
      expect(
        BackupPolicy.fileName(BackupKind.products, DateTime(2026, 10, 2, 7, 5)),
        'toko-barang-20261002-070500.xlsx',
      );
    });
  });

  group('BackupService', () {
    late AppDatabase db;
    late Directory dir;
    late AppUser admin;
    late AppUser kasir;
    var now = DateTime(2026, 10, 1, 9);

    setUp(() async {
      db = await createSeededDb();
      dir = await Directory.systemTemp.createTemp('toko-backup-');
      final auth = AuthRepository(db, testHasher);
      admin = await auth.login('admin', 'admin123');
      kasir = await auth.login('kasir', 'kasir123');
      now = DateTime(2026, 10, 1, 9);
    });

    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    BackupService service() =>
        BackupService(db, clock: () => now, defaultFolder: () async => dir);

    List<String> filesIn(Directory d) =>
        [for (final f in d.listSync()) p.basename(f.path)]..sort();

    test(
      'database + Excel barang per toko; database bisa dibuka lagi',
      () async {
        await StoreRepository(db).save(actor: admin, name: 'Toko B');
        final created = await service().run();

        expect(filesIn(dir), [
          'toko-barang-20261001-090000.xlsx',
          'toko-database-20261001-090000.sqlite',
        ]);
        expect(created.map((f) => f.kind).toSet(), BackupKind.values.toSet());

        // Database cadangan berisi data yang sama.
        final copy = AppDatabase(
          NativeDatabase(File(p.join(dir.path, filesIn(dir)[1]))),
        );
        addTearDown(copy.close);
        final count = (await copy.select(copy.products).get()).length;
        expect(count, (await db.select(db.products).get()).length);

        // Excel: satu sheet per toko, kolom sama dengan export (bisa import).
        final book = Excel.decodeBytes(
          File(p.join(dir.path, filesIn(dir)[0])).readAsBytesSync(),
        );
        expect(book.tables.keys, containsAll(['Toko Utama', 'Toko B']));
        final main = book.tables['Toko Utama']!;
        expect(main.rows.first.first?.value.toString(), 'Barcode');
        expect(main.maxRows, count + 1);
        final indomie = (await ProductRepository(db)
            .findByCodeOrBarcode('BRG001', storeId: await mainStoreId(db)))!;
        final row = main.rows.firstWhere(
          (r) => r.first?.value.toString() == 'BRG001',
        );
        expect(row[7]?.value.toString(), Fmt0.n(indomie.stock));

        final status = await service().status();
        expect(status.lastAt, now);
        expect(status.lastError, isNull);
        expect(status.files, hasLength(2));
        expect(status.nextAt, DateTime(2026, 10, 8, 9));
      },
    );

    test(
      'backup ke-3 menggantikan yang paling lama (tersisa 2 per jenis)',
      () async {
        for (final day in [1, 8, 15]) {
          now = DateTime(2026, 10, day, 9);
          await service().run();
        }
        expect(filesIn(dir), [
          'toko-barang-20261008-090000.xlsx',
          'toko-barang-20261015-090000.xlsx',
          'toko-database-20261008-090000.sqlite',
          'toko-database-20261015-090000.sqlite',
        ]);
      },
    );

    test('otomatis hanya jika aktif dan sudah seminggu', () async {
      expect(await service().runIfDue(), isTrue);
      now = DateTime(2026, 10, 7, 9);
      expect(await service().runIfDue(), isFalse);
      now = DateTime(2026, 10, 8, 9);
      expect(await service().runIfDue(), isTrue);

      await service().setEnabled(admin, false);
      now = DateTime(2026, 10, 30);
      expect(await service().runIfDue(), isFalse);
      expect(filesIn(dir), hasLength(4));
    });

    test('jumlah file & jarak hari bisa diatur admin (dengan batas)', () async {
      expect(() => service().setKeep(kasir, 5), throwsA(isA<BackupFailure>()));
      expect(
        () => service().setIntervalDays(kasir, 1),
        throwsA(isA<BackupFailure>()),
      );

      // Simpan 3 file: backup ke-4 menghapus yang paling lama saja.
      await service().setKeep(admin, 3);
      for (final day in [1, 2, 3, 4]) {
        now = DateTime(2026, 10, day, 9);
        await service().run();
      }
      expect(filesIn(dir).where((n) => n.endsWith('.sqlite')), [
        'toko-database-20261002-090000.sqlite',
        'toko-database-20261003-090000.sqlite',
        'toko-database-20261004-090000.sqlite',
      ]);

      // Dikurangi jadi 1: berlaku pada backup berikutnya.
      await service().setKeep(admin, 1);
      now = DateTime(2026, 10, 5, 9);
      await service().run();
      expect(filesIn(dir), [
        'toko-barang-20261005-090000.xlsx',
        'toko-database-20261005-090000.sqlite',
      ]);

      // Backup harian.
      await service().setIntervalDays(admin, 1);
      now = DateTime(2026, 10, 6, 8, 59);
      expect(await service().runIfDue(), isFalse);
      now = DateTime(2026, 10, 6, 9);
      expect(await service().runIfDue(), isTrue);
      final status = await service().status();
      expect(status.intervalDays, 1);
      expect(status.keep, 1);
      expect(status.nextAt, DateTime(2026, 10, 7, 9));

      // Di luar batas dipotong: 1–30 hari, 1–10 file.
      await service().setIntervalDays(admin, 99);
      await service().setKeep(admin, 0);
      final clamped = await service().status();
      expect(clamped.intervalDays, 30);
      expect(clamped.keep, 1);
    });

    test('folder pilihan admin; gagal ditulis dicatat', () async {
      expect(
        () => service().setFolder(kasir, dir.path),
        throwsA(isA<BackupFailure>()),
      );
      final custom = Directory(p.join(dir.path, 'flashdisk', 'Backup'));
      await service().setFolder(admin, custom.path);
      await service().run();
      expect(filesIn(custom), hasLength(2));
      expect((await service().status()).isCustomFolder, isTrue);

      // "Folder" yang sebenarnya file: tidak bisa ditulis.
      final blocked = File(p.join(dir.path, 'bukan-folder'))
        ..writeAsStringSync('x');
      await service().setFolder(admin, blocked.path);
      now = DateTime(2026, 10, 9);
      expect(await service().runIfDue(), isFalse);
      final status = await service().status();
      expect(status.lastError, contains('gagal'));
      expect(status.lastAt, DateTime(2026, 10, 1, 9));

      await service().setFolder(admin, null);
      expect((await service().status()).folder, dir.path);
    });
  });
}

/// Format angka seperti di Excel export (bilangan bulat tanpa ,0).
class Fmt0 {
  static String n(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';
}
