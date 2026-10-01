import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:toko/core/database/app_database.dart';
import 'package:toko/features/auth/data/auth_repository.dart';
import 'package:toko/features/auth/data/user_repository.dart';
import 'package:toko/features/auth/domain/app_user.dart';
import 'package:toko/features/payments/data/payment_method_repository.dart';
import 'package:toko/features/payments/domain/payment_method.dart';
import 'package:toko/features/products/data/product_repository.dart';
import 'package:toko/features/sales/data/checkout_service.dart';
import 'package:toko/features/sales/data/sales_repository.dart';
import 'package:toko/features/sales/domain/cart.dart';
import 'package:toko/features/sync/data/terminal_repository.dart';

import '../../helpers/test_app.dart';

void main() {
  late AppDatabase db;
  late ProductRepository products;
  late AppUser kasir;
  late AppUser admin;
  late PaymentMethod tunai;
  late PaymentMethod qris;
  final clock = DateTime(2026, 9, 30, 10, 15);

  // Format tanggal Indonesia untuk pesan dan label.
  setUpAll(() => initializeDateFormatting('id_ID'));

  setUp(() async {
    db = await createSeededDb();
    products = ProductRepository(db);
    final auth = AuthRepository(db, testHasher);
    kasir = await auth.login('kasir', 'kasir123');
    admin = await auth.login('admin', 'admin123');
    final methods = await PaymentMethodRepository(db).watchAll().first;
    tunai = methods.firstWhere((m) => m.name == 'Tunai');
    qris = methods.firstWhere((m) => m.name == 'QRIS');
  });

  tearDown(() => db.close());

  CheckoutService service() => CheckoutService(db, clock: () => clock);

  Future<Cart> cartOf(String code, {double qty = 1}) async =>
      const Cart().add((await products.findByCodeOrBarcode(code))!, qty: qty);

  test('20 barang contoh dan 4 metode bayar bawaan', () async {
    expect(await db.select(db.products).get(), hasLength(20));
    final methods = await PaymentMethodRepository(db).watchAll().first;
    expect(methods.map((m) => m.name), [
      'Tunai',
      'QRIS',
      'Transfer Bank',
      'Kartu Debit/Kredit',
    ]);
    final byCode = await products.findByCodeOrBarcode('brg001');
    expect(byCode?.name, 'Indomie Goreng 85g');
    expect(
      (await products.findByCodeOrBarcode(byCode!.barcode!))?.id,
      byCode.id,
    );
    expect(await products.search('indomie'), hasLength(2));
  });

  test('checkout tunai: faktur, stok, riwayat, kembalian', () async {
    final indomie = (await products.findByCodeOrBarcode('BRG001'))!;
    final telur = (await products.findByCodeOrBarcode('BRG008'))!;
    final cart = const Cart().add(indomie, qty: 5).add(telur, qty: 0.5);

    final result = await service().checkout(
      cart: cart,
      cashier: kasir,
      paymentMethodId: tunai.id,
      paid: 50000,
    );

    expect(result.invoiceNo, 'INV-K01-20260930-0001');
    expect(result.total, 5 * 3500 + 14500);
    expect(result.change, 50000 - result.total);
    expect(result.paymentMethod, 'Tunai');

    expect(
      (await products.findByCodeOrBarcode('BRG001'))!.stock,
      indomie.stock - 5,
    );
    expect((await db.select(db.stockMovements).get()), hasLength(2));
    final lines = await SalesRepository(db).linesOf(result.saleId);
    expect(lines.map((l) => l.name), ['Indomie Goreng 85g', 'Telur Ayam']);
  });

  test('checkout non-tunai dibayar pas dan menyimpan referensi', () async {
    final result = await service().checkout(
      cart: await cartOf('BRG005'),
      cashier: kasir,
      paymentMethodId: qris.id,
      paid: 999999, // diabaikan untuk non-tunai
      paymentRef: ' QR-123 ',
    );
    expect(result.paid, result.total);
    expect(result.change, 0);
    final sale = (await SalesRepository(db).watchDay(clock).first).single;
    expect(sale.paymentMethod, 'QRIS');
    expect(sale.paymentRef, 'QR-123');
  });

  test('uang tunai kurang ditolak dan tidak ada yang tersimpan', () async {
    final cart = await cartOf('BRG005');
    await expectLater(
      service().checkout(
        cart: cart,
        cashier: kasir,
        paymentMethodId: tunai.id,
        paid: 1000,
      ),
      throwsA(isA<CheckoutFailure>()),
    );
    expect(await db.select(db.sales).get(), isEmpty);
    expect(
      (await products.findByCodeOrBarcode('BRG005'))!.stock,
      cart.lines.single.product.stock,
    );
  });

  test('metode nonaktif tidak bisa dipakai', () async {
    await PaymentMethodRepository(db).save(
      actor: admin,
      id: qris.id,
      name: qris.name,
      kind: qris.kind,
      isActive: false,
    );
    expect(
      service().checkout(
        cart: await cartOf('BRG009'),
        cashier: kasir,
        paymentMethodId: qris.id,
      ),
      throwsA(isA<CheckoutFailure>()),
    );
  });

  test('nomor faktur berurutan dalam satu hari', () async {
    final cart = await cartOf('BRG009');
    Future<String> pay() async => (await service().checkout(
      cart: cart,
      cashier: kasir,
      paymentMethodId: tunai.id,
      paid: 5000,
    )).invoiceNo;
    expect(await pay(), 'INV-K01-20260930-0001');
    expect(await pay(), 'INV-K01-20260930-0002');
  });

  group('persiapan sinkron', () {
    test(
      'checkout memberi uuid, kode terminal, dan masuk antrian kirim',
      () async {
        final result = await service().checkout(
          cart: await cartOf('BRG001', qty: 2),
          cashier: kasir,
          paymentMethodId: tunai.id,
          paid: 10000,
        );
        final sale = (await db.select(db.sales).get()).single;
        expect(sale.uuid, isNotNull);
        expect(sale.terminalCode, 'K01');

        final items = await db.select(db.saleItems).get();
        final moves = await db.select(db.stockMovements).get();
        expect(items.single.uuid, isNotNull);
        expect(moves.single.uuid, isNotNull);

        final pending = await db.outboxDao.pending();
        expect(pending.single.entityUuid, sale.uuid);
        expect(pending.single.sentAt, isNull);
        expect(await db.outboxDao.watchPendingCount().first, 1);
        expect(result.saleId, sale.id);
      },
    );

    test('ganti kode terminal hanya memengaruhi faktur berikutnya', () async {
      final terminal = TerminalRepository(db);
      final first = await service().checkout(
        cart: await cartOf('BRG009'),
        cashier: kasir,
        paymentMethodId: tunai.id,
        paid: 5000,
      );
      await terminal.setCode(actor: admin, code: 'cbg2');
      final second = await service().checkout(
        cart: await cartOf('BRG009'),
        cashier: kasir,
        paymentMethodId: tunai.id,
        paid: 5000,
      );
      expect(first.invoiceNo, 'INV-K01-20260930-0001');
      expect(second.invoiceNo, 'INV-CBG2-20260930-0001');
      expect(
        terminal.setCode(actor: kasir, code: 'K09'),
        throwsA(isA<TerminalFailure>()),
      );
      expect(
        terminal.setCode(actor: admin, code: 'K 1'),
        throwsA(isA<TerminalFailure>()),
      );
    });

    test('identitas terminal dibuat sekali dan tetap', () async {
      final a = await TerminalRepository(db).ensureInitialized();
      final b = await TerminalRepository(db).ensureInitialized();
      expect(a.id, isNotEmpty);
      expect(a.id, b.id);
      expect(a.code, 'K01');
      expect(a.isServer, isTrue);
    });

    test('semua baris data bawaan punya uuid unik', () async {
      final uuids = [
        ...(await db.select(db.products).get()).map((r) => r.uuid),
        ...(await db.select(db.categories).get()).map((r) => r.uuid),
        ...(await db.select(db.units).get()).map((r) => r.uuid),
        ...(await db.select(db.users).get()).map((r) => r.uuid),
        ...(await db.select(db.paymentMethods).get()).map((r) => r.uuid),
      ];
      expect(uuids, everyElement(isNotNull));
      expect(uuids.toSet(), hasLength(uuids.length));
    });
  });

  group('metode pembayaran', () {
    test('tambah, tidak boleh duplikat, minimal satu aktif', () async {
      final repo = PaymentMethodRepository(db);
      final gopay = await repo.save(
        actor: admin,
        name: 'GoPay',
        kind: PaymentKind.nonCash,
        isActive: true,
      );
      expect(gopay.sortOrder, 5);
      expect(
        repo.save(
          actor: admin,
          name: 'gopay',
          kind: PaymentKind.nonCash,
          isActive: true,
        ),
        throwsA(isA<PaymentMethodFailure>()),
      );

      // Nonaktifkan semua kecuali satu, lalu yang terakhir harus ditolak.
      final all = await repo.watchAll().first;
      for (final m in all.skip(1)) {
        await repo.save(
          actor: admin,
          id: m.id,
          name: m.name,
          kind: m.kind,
          isActive: false,
        );
      }
      expect(
        repo.save(
          actor: admin,
          id: all.first.id,
          name: all.first.name,
          kind: all.first.kind,
          isActive: false,
        ),
        throwsA(isA<PaymentMethodFailure>()),
      );
    });

    test('metode yang sudah dipakai tidak bisa dihapus', () async {
      await service().checkout(
        cart: await cartOf('BRG009'),
        cashier: kasir,
        paymentMethodId: qris.id,
      );
      expect(
        PaymentMethodRepository(db).delete(actor: admin, id: qris.id),
        throwsA(isA<PaymentMethodFailure>()),
      );
    });
  });

  test('transaksi hari ini muncul di daftar beserta nama kasir', () async {
    await service().checkout(
      cart: await cartOf('BRG010'),
      cashier: kasir,
      paymentMethodId: tunai.id,
      paid: 10000,
    );
    final today = await SalesRepository(db).watchDay(clock).first;
    expect(today.single.cashierName, 'Kasir Satu');
    final yesterday = await SalesRepository(db)
        .watchDay(clock.subtract(const Duration(days: 1)))
        .first;
    expect(yesterday, isEmpty);
  });

  test('akun yang punya transaksi tidak bisa dihapus', () async {
    await service().checkout(
      cart: await cartOf('BRG010'),
      cashier: kasir,
      paymentMethodId: tunai.id,
      paid: 10000,
    );
    expect(
      UserRepository(db, testHasher).delete(actor: admin, id: kasir.id),
      throwsA(isA<AccountFailure>()),
    );
  });

  group('migrasi', () {
    test('v1 → v3: user tetap, semua tabel dan data bawaan dibuat', () async {
      final legacy = NativeDatabase.memory(
        setup: (Database raw) {
          raw.execute('''
            CREATE TABLE users (
              id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
              username TEXT NOT NULL UNIQUE,
              full_name TEXT NOT NULL,
              password_hash TEXT NOT NULL,
              role TEXT NOT NULL,
              is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
              created_at INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
              last_login_at INTEGER NULL
            );
          ''');
          raw.execute(
            "INSERT INTO users (username, full_name, password_hash, role) "
            "VALUES ('lama', 'User Lama', 'x', 'admin')",
          );
          raw.userVersion = 1;
        },
      );
      final upgraded = AppDatabase(legacy);
      addTearDown(upgraded.close);

      expect(
        (await upgraded.select(upgraded.users).get()).single.username,
        'lama',
      );
      expect(await upgraded.select(upgraded.products).get(), hasLength(20));
      expect(
        await upgraded.select(upgraded.paymentMethods).get(),
        hasLength(4),
      );
      expect(await upgraded.select(upgraded.vouchers).get(), isEmpty);
      final users = await upgraded.select(upgraded.users).get();
      expect(users.single.uuid, isNotNull);
      expect(
        (await upgraded.select(upgraded.products).get()).map((p) => p.uuid),
        everyElement(isNotNull),
      );
    });

    test(
      'v2 (skema asli) → v3: faktur lama tetap dan ditandai Tunai',
      () async {
        final schema = File('test/fixtures/schema_v2.sql').readAsStringSync();
        final legacy = NativeDatabase.memory(
          setup: (Database raw) {
            for (final stmt in schema.split(';\n')) {
              if (stmt.trim().isNotEmpty) raw.execute(stmt);
            }
            raw.execute(
              "INSERT INTO users (username, full_name, password_hash, role) "
              "VALUES ('kasir', 'Kasir', 'x', 'kasir')",
            );
            raw.execute(
              "INSERT INTO sales (invoice_no, sale_date, user_id, item_count, "
              "subtotal, discount, total, paid, change_amount, payment_method) "
              "VALUES ('INV-20260930-0001', 1790000000, 1, 1, 3500, 0, 3500, "
              "5000, 1500, 'tunai')",
            );
            raw.userVersion = 2;
          },
        );
        final upgraded = AppDatabase(legacy);
        addTearDown(upgraded.close);

        final sale = (await upgraded.select(upgraded.sales).get()).single;
        expect(sale.invoiceNo, 'INV-20260930-0001');
        expect(sale.paymentMethod, 'Tunai');
        expect(sale.paymentMethodId, isNotNull);
        expect(sale.voucherId, isNull);
        expect(
          await upgraded.select(upgraded.paymentMethods).get(),
          hasLength(4),
        );
        expect(sale.uuid, isNotNull);
        expect(
          (await upgraded.outboxDao.pending()).single.entityUuid,
          sale.uuid,
        );
      },
    );

    test('v3 (skema asli) → v4: uuid terisi, faktur lama diantrikan, '
        'data voucher lama tetap ada', () async {
      final schema = File('test/fixtures/schema_v3.sql').readAsStringSync();
      final legacy = NativeDatabase.memory(
        setup: (Database raw) {
          for (final stmt in schema.split(';\n')) {
            if (stmt.trim().isNotEmpty) raw.execute(stmt);
          }
          raw.execute(
            "INSERT INTO users (username, full_name, password_hash, role) "
            "VALUES ('kasir', 'Kasir', 'x', 'kasir')",
          );
          raw.execute(
            "INSERT INTO payment_methods (name, kind, sort_order) "
            "VALUES ('Tunai', 'cash', 1)",
          );
          raw.execute(
            "INSERT INTO vouchers (code, name, type, value, quota, used_count) "
            "VALUES ('LAMA', '', 'amount', 1000, 5, 5)",
          );
          raw.execute(
            "INSERT INTO sales (invoice_no, sale_date, user_id, item_count, "
            "subtotal, discount, total, paid, change_amount, payment_method, "
            "payment_method_id) VALUES ('INV-20261001-0001', 1790000000, 1, "
            "1, 17500, 0, 17500, 20000, 2500, 'Tunai', 1)",
          );
          raw.userVersion = 3;
        },
      );
      final upgraded = AppDatabase(legacy);
      addTearDown(upgraded.close);

      final sale = (await upgraded.select(upgraded.sales).get()).single;
      expect(sale.invoiceNo, 'INV-20261001-0001');
      expect(sale.uuid, isNotNull);
      expect(sale.terminalCode, isNull);
      expect((await upgraded.outboxDao.pending()).single.entityUuid, sale.uuid);

      // Fitur voucher sudah dihapus, tapi data lama di tabel tetap utuh.
      final vouchers = await upgraded.select(upgraded.vouchers).get();
      expect(vouchers.single.code, 'LAMA');
    });
  });
}
