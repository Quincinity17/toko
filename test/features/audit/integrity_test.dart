import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:toko/core/database/app_database.dart';
import 'package:toko/features/audit/data/audit_repository.dart';
import 'package:toko/features/audit/data/integrity_service.dart';
import 'package:toko/features/audit/domain/audit_entry.dart';
import 'package:toko/features/auth/data/auth_repository.dart';
import 'package:toko/features/auth/domain/app_user.dart';
import 'package:toko/features/payments/data/payment_method_repository.dart';
import 'package:toko/features/products/data/product_repository.dart';
import 'package:toko/features/sales/data/checkout_service.dart';
import 'package:toko/features/sales/domain/cart.dart';

import '../../helpers/test_app.dart';

void main() {
  late AppDatabase db;
  late AppUser kasir;

  setUpAll(() => initializeDateFormatting('id_ID'));
  setUp(() async {
    db = await createSeededDb();
    kasir = await AuthRepository(db, testHasher).login('kasir', 'kasir123');
  });
  tearDown(() => db.close());

  Future<IntegrityReport> check() => IntegrityService(db).check();
  List<String> titles(IntegrityReport r) => [for (final i in r.issues) i.title];

  Future<String> sell(String code) async {
    final tunai = (await PaymentMethodRepository(
      db,
    ).watchAll().first).firstWhere((m) => m.name == 'Tunai');
    final cart = const Cart().add(
      (await ProductRepository(db).findByCodeOrBarcode(code))!,
    );
    final r = await CheckoutService(db).checkout(
      cart: cart,
      cashier: kasir,
      storeId: await mainStoreId(db),
      paymentMethodId: tunai.id,
      paid: 100000,
    );
    return r.invoiceNo;
  }

  test('data utuh: tidak ada masalah; penjualan & login tercatat', () async {
    await sell('BRG001');
    final report = await check();
    expect(report.issues, isEmpty);
    expect(report.sales, 1);
    final entries = await AuditRepository(db)
        .between(DateTime(2000), DateTime(2100));
    expect(
      entries.map((e) => e.type),
      containsAll([AuditType.sealsRebuilt, AuditType.login, AuditType.sale]),
    );
  });

  test(
    'akun dinaikkan jadi admin lewat SQL → ketahuan & tidak bisa login',
    () async {
      await db.customStatement(
        "UPDATE users SET role = 'admin', store_id = NULL "
        "WHERE username = 'kasir'",
      );
      expect(
        titles(await check()),
        contains('Akun kasir diubah di luar aplikasi'),
      );
      await expectLater(
        AuthRepository(db, testHasher).login('kasir', 'kasir123'),
        throwsA(
          isA<AuthFailure>().having(
            (e) => e.message,
            'pesan',
            contains('tidak sah'),
          ),
        ),
      );
    },
  );

  test('harga & stok diubah lewat SQL → ketahuan', () async {
    await db.customStatement(
      "UPDATE products SET selling_price = 100 WHERE code = 'BRG001'",
    );
    await db.customStatement(
      'UPDATE store_products SET stock = 9999 WHERE id = 2',
    );
    final t = titles(await check());
    expect(t, contains('Barang BRG001 diubah di luar aplikasi'));
    expect(t.any((x) => x.startsWith('Stok/harga')), isTrue);
  });

  test('faktur diubah / dihapus / disisipkan lewat SQL → ketahuan', () async {
    final first = await sell('BRG001');
    final second = await sell('BRG009');
    final third = await sell('BRG010');

    await db.customStatement(
      'UPDATE sales SET total = 1000 WHERE invoice_no = ?',
      [first],
    );
    await db.customStatement('DELETE FROM sales WHERE invoice_no = ?', [
      second,
    ]);
    await db.customStatement(
      'INSERT INTO sales (invoice_no, sale_date, user_id, item_count, '
      'subtotal, total, paid, change_amount, uuid) VALUES '
      "('INV-PALSU-1', ?, 1, 0, 0, 0, 0, 0, 'palsu')",
      [DateTime.now().millisecondsSinceEpoch ~/ 1000],
    );
    final t = titles(await check());
    expect(t, contains('Faktur $first diubah di luar aplikasi'));
    expect(t, contains('Faktur $second dihapus di luar aplikasi'));
    expect(t, contains('Faktur INV-PALSU-1 tidak tercatat'));
    expect(t.any((x) => x.startsWith('Nomor faktur hilang')), isTrue);
    expect(t.where((x) => x.contains(third)), isEmpty);
  });

  test('catatan aktivitas dihapus di tengah → rantai putus', () async {
    await sell('BRG001');
    await sell('BRG009');
    final rows = await db.select(db.auditLog).get();
    await db.customStatement('DELETE FROM audit_log WHERE id = ?', [
      rows[rows.length - 2].id,
    ]);
    expect(
      titles(await check()),
      contains('Catatan aktivitas dihapus di luar aplikasi'),
    );
  });

  test('jam dimundurkan → tercatat & diperingatkan', () async {
    await AuditRepository(db).record(
      AuditType.drawerOpened,
      'Laci dibuka tanpa transaksi',
      actor: kasir,
      at: DateTime.now().subtract(const Duration(days: 1)),
    );
    final r = await check();
    expect(
      r.issues
          .where((i) => i.severity == IntegritySeverity.warning)
          .map((i) => i.title),
      contains('Jam perangkat dimundurkan'),
    );
  });

  test('ringkasan perlu perhatian per kasir', () async {
    final audit = AuditRepository(db);
    await audit.record(
      AuditType.cartCleared,
      'Batal transaksi',
      actor: kasir,
      data: {'total': 45000},
    );
    await audit.record(
      AuditType.drawerOpened,
      'Laci dibuka tanpa transaksi',
      actor: kasir,
    );
    final s = await audit.attention(DateTime(2000), DateTime(2100));
    final k = s.firstWhere((x) => x.userName == 'Kasir Satu');
    expect(k.counts[AuditType.cartCleared], 1);
    expect(k.counts[AuditType.drawerOpened], 1);
    expect(k.cartClearedValue, 45000);
  });
}
