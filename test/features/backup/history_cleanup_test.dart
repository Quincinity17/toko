import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:toko/core/database/app_database.dart';
import 'package:toko/core/database/tables/audit.dart';
import 'package:toko/features/audit/data/integrity_service.dart';
import 'package:toko/features/auth/data/auth_repository.dart';
import 'package:toko/features/auth/domain/app_user.dart';
import 'package:toko/features/backup/data/backup_service.dart';
import 'package:toko/features/backup/data/history_cleanup_service.dart';
import 'package:toko/features/backup/domain/history_retention.dart';
import 'package:toko/features/payments/data/payment_method_repository.dart';
import 'package:toko/features/products/data/product_repository.dart';
import 'package:toko/features/sales/data/checkout_service.dart';
import 'package:toko/features/sales/data/return_service.dart';
import 'package:toko/features/sales/domain/cart.dart';

import '../../helpers/test_app.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  group('HistoryRetention', () {
    test('batas tanggal = hari ini dikurangi N bulan (awal hari)', () {
      expect(
        HistoryRetention.cutoff(DateTime(2026, 10, 13, 15), 12),
        DateTime(2025, 10, 13),
      );
      expect(
        HistoryRetention.cutoff(DateTime(2026, 3, 31), 1),
        DateTime(2026, 2, 28),
      );
      expect(
        HistoryRetention.cutoff(DateTime(2026, 2, 10), 6),
        DateTime(2025, 8, 10),
      );
      expect(
        HistoryRetention.cutoff(DateTime(2026, 10, 13), 60),
        DateTime(2021, 10, 13),
      );
    });

    test('pilihan tak dikenal = tidak pernah; sekali sehari', () {
      expect(HistoryRetention.clamp(7), HistoryRetention.never);
      expect(HistoryRetention.clamp(24), 24);
      expect(HistoryRetention.label(24), 'Lebih lama dari 2 tahun');
      final now = DateTime(2026, 10, 13, 9);
      expect(HistoryRetention.isDue(null, now), isTrue);
      expect(HistoryRetention.isDue(DateTime(2026, 10, 13, 1), now), isFalse);
      expect(HistoryRetention.isDue(DateTime(2026, 10, 12, 23), now), isTrue);
    });
  });

  group('HistoryCleanupService', () {
    late AppDatabase db;
    late AppUser admin;
    late AppUser kasir;
    late Directory folder;
    late int store;
    // Semua waktu sesudah database dibuat (jangkar pemeriksaan keutuhan =
    // jam sungguhan saat tes), seperti di toko sungguhan.
    final y = DateTime.now().year + 1;
    final now = DateTime(y + 1, 10, 13, 9);

    setUp(() async {
      db = await createSeededDb();
      final auth = AuthRepository(db, testHasher);
      admin = await auth.login('admin', 'admin123');
      kasir = await auth.login('kasir', 'kasir123');
      store = await mainStoreId(db);
      folder = await Directory.systemTemp.createTemp('toko-history-');
    });
    tearDown(() async {
      await db.close();
      await folder.delete(recursive: true);
    });

    HistoryCleanupService service() => HistoryCleanupService(
      db,
      BackupService(db, clock: () => now, defaultFolder: () async => folder),
      clock: () => now,
    );

    Future<int> sell(DateTime at) async {
      final tunai = (await PaymentMethodRepository(
        db,
      ).watchAll().first).firstWhere((m) => m.name == 'Tunai').id;
      final indomie = (await ProductRepository(db)
          .findByCodeOrBarcode('BRG001'))!;
      final r = await CheckoutService(db, clock: () => at).checkout(
        cart: const Cart().add(indomie, qty: 2),
        cashier: kasir,
        storeId: store,
        paymentMethodId: tunai,
        paid: 10000,
      );
      return r.saleId;
    }

    Future<void> returnOne(int saleId, DateTime at) async {
      final returns = ReturnService(db, clock: () => at);
      final sale = await returns.load(saleId);
      await returns.create(
        actor: admin,
        saleId: saleId,
        qtys: {sale.lines.first.saleItemId: 1},
        reason: 'Rusak',
      );
    }

    Future<List<String>> invoices() async => [
      for (final s in await (db.select(
        db.sales,
      )..orderBy([(s) => OrderingTerm.asc(s.id)])).get())
        s.invoiceNo,
    ];

    test('bawaan tidak pernah: otomatis tidak menghapus apa pun', () async {
      await sell(DateTime(2024, 1, 5));
      expect(await service().runIfDue(), isNull);
      expect(await invoices(), hasLength(1));
      expect(service().runNow(admin), throwsA(isA<HistoryCleanupFailure>()));
    });

    test('menghapus faktur lama + returnya; yang diretur setelah batas dan '
        'yang baru tetap; stok tidak berubah; keutuhan data bersih', () async {
      final a = await sell(DateTime(y, 3, 1, 10)); // lama
      final b = await sell(DateTime(y, 4, 1, 10)); // lama, retur lama
      await returnOne(b, DateTime(y, 4, 2, 10));
      final c = await sell(DateTime(y, 5, 1, 10)); // lama, retur baru
      await returnOne(c, DateTime(y + 1, 9, 1, 10));
      await sell(DateTime(y + 1, 10, 1, 10)); // baru

      final indomie = (await ProductRepository(db)
          .findByCodeOrBarcode('BRG001', storeId: store))!;
      final adjustBefore = await (db.select(
        db.stockMovements,
      )..where((m) => m.type.equals('adjust'))).get();

      await service().setKeepMonths(admin, 12); // batas 13 Okt tahun y
      expect(await service().preview(12), 2); // a & b
      final r = await service().runNow(admin);
      expect(r.cutoff, DateTime(y, 10, 13));
      expect(r.sales, 2);
      expect(r.returns, 1);
      expect(File(r.safetyCopy!).existsSync(), isTrue);
      expect(r.safetyCopy, contains(HistoryCleanupService.safetyPrefix));

      final left = await invoices();
      expect(left, hasLength(3)); // c, retur c, faktur baru
      expect(left.where((n) => n.startsWith('RET-')), hasLength(1));
      final ids = (await db.select(db.sales).get()).map((s) => s.id).toSet();
      expect(ids.containsAll([a, b]), isFalse);
      expect(ids, contains(c));

      // Baris barang, riwayat stok penjualan, & antrian ikut terhapus.
      final items = await db.select(db.saleItems).get();
      expect(items.every((i) => ids.contains(i.saleId)), isTrue);
      final moves = await db.select(db.stockMovements).get();
      expect(
        moves
            .where((m) => m.type.name == 'sale')
            .every((m) => ids.contains(m.refId)),
        isTrue,
      );
      expect(
        (await (db.select(
          db.stockMovements,
        )..where((m) => m.type.equals('adjust'))).get()),
        hasLength(adjustBefore.length),
      );
      final uuids = (await db.select(db.sales).get()).map((s) => s.uuid);
      expect(
        (await db.select(db.syncOutbox).get()).map((o) => o.entityUuid),
        unorderedEquals(uuids),
      );

      // Stok toko tidak berubah.
      expect(
        (await ProductRepository(
          db,
        ).findByCodeOrBarcode('BRG001', storeId: store))!.stock,
        indomie.stock,
      );

      final purged = await (db.select(
        db.auditLog,
      )..where((a) => a.type.equalsValue(AuditType.salesPurged))).get();
      expect(purged.single.summary, contains('2 faktur, 1 nota retur'));

      // Penghapusan lewat aplikasi bukan "dihapus di luar aplikasi".
      final issues = (await IntegrityService(db).check()).issues;
      expect(
        issues
            .map((i) => i.title)
            .where(
              (t) => t.startsWith('Faktur') || t.startsWith('Nomor faktur'),
            ),
        isEmpty,
      );
    });

    test('otomatis sekali sehari', () async {
      await sell(DateTime(2024, 1, 5));
      await service().setKeepMonths(admin, 6);
      final first = await service().runIfDue();
      expect(first!.sales, 1);
      expect(await service().runIfDue(), isNull); // sudah hari ini
      final status = await service().status();
      expect(status.lastRun, now);
      expect(status.lastDeleted, 1);
      expect(status.sales, 0);
    });

    test(
      'hanya admin; kasir cabang hanya menghapus yang sudah terkirim',
      () async {
        expect(
          service().setKeepMonths(kasir, 12),
          throwsA(isA<HistoryCleanupFailure>()),
        );
        await sell(DateTime(2024, 1, 5));
        await sell(DateTime(2024, 2, 5));
        await db.settingsDao.set('terminal.mode', 'client');
        await service().setKeepMonths(admin, 12);
        expect(await service().preview(12), 0); // belum terkirim
        final first = (await db.select(db.sales).get()).first;
        await (db.update(db.syncOutbox)
              ..where((o) => o.entityUuid.equals(first.uuid!)))
            .write(SyncOutboxCompanion(sentAt: Value(now)));
        expect(await service().preview(12), 1);
      },
    );
  });
}
