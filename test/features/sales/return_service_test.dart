import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:toko/core/database/app_database.dart';
import 'package:toko/core/database/tables/sales.dart';
import 'package:toko/features/auth/data/auth_repository.dart';
import 'package:toko/features/auth/data/user_repository.dart';
import 'package:toko/features/auth/domain/app_user.dart';
import 'package:toko/features/auth/domain/user_role.dart';
import 'package:toko/features/payments/data/payment_method_repository.dart';
import 'package:toko/features/products/data/product_repository.dart';
import 'package:toko/features/reports/data/report_repository.dart';
import 'package:toko/features/reports/domain/report_models.dart';
import 'package:toko/features/sales/data/checkout_service.dart';
import 'package:toko/features/sales/data/return_service.dart';
import 'package:toko/features/sales/data/sales_repository.dart';
import 'package:toko/features/sales/domain/cart.dart';

import '../../helpers/test_app.dart';

void main() {
  late AppDatabase db;
  late ProductRepository products;
  late AppUser kasir;
  late AppUser admin;
  late int store;
  final saleAt = DateTime(2026, 10, 4, 9);
  final returnAt = DateTime(2026, 10, 4, 15);

  setUpAll(() => initializeDateFormatting('id_ID'));

  setUp(() async {
    db = await createSeededDb();
    products = ProductRepository(db);
    final auth = AuthRepository(db, testHasher);
    kasir = await auth.login('kasir', 'kasir123');
    admin = await auth.login('admin', 'admin123');
    store = await mainStoreId(db);
  });
  tearDown(() => db.close());

  ReturnService service() => ReturnService(db, clock: () => returnAt);

  /// 3 × Indomie (3.500, beli 2.800) + 1 × Teh Botol (5.500, beli 4.200),
  /// tunai = Rp 16.000.
  Future<int> sell() async {
    var cart = const Cart();
    cart = cart.add((await products.findByCodeOrBarcode('BRG001'))!, qty: 3);
    cart = cart.add((await products.findByCodeOrBarcode('BRG010'))!);
    final tunai = (await PaymentMethodRepository(
      db,
    ).watchAll().first).firstWhere((m) => m.name == 'Tunai');
    final r = await CheckoutService(db, clock: () => saleAt).checkout(
      cart: cart,
      cashier: kasir,
      storeId: store,
      paymentMethodId: tunai.id,
      paid: 20000,
    );
    return r.saleId;
  }

  Future<double> stockOf(String code) async =>
      (await products.findByCodeOrBarcode(code, storeId: store))!.stock;

  test('retur sebagian: nota RET negatif, stok kembali, laporan terpotong '
      'tanpa menambah transaksi', () async {
    final saleId = await sell();
    final before = await stockOf('BRG001');
    final sale = await service().load(saleId);
    final indomie = sale.lines.firstWhere((l) => l.code == 'BRG001');

    final r = await service().create(
      actor: admin,
      saleId: saleId,
      qtys: {indomie.saleItemId: 1},
      reason: 'Kemasan rusak',
    );
    expect(r.invoiceNo, startsWith('RET-'));
    expect(r.invoiceNo, endsWith('-20261004-0001'));
    expect(r.refund, 3500);
    expect(r.isCash, isTrue);
    expect(await stockOf('BRG001'), before + 1);

    final movement = await (db.select(
      db.stockMovements,
    )..where((m) => m.refId.equals(r.saleId))).getSingle();
    expect(movement.type, StockMovementType.saleReturn);
    expect(movement.qtyChange, 1);

    // Ringkasan hari itu: omzet & pokok terpotong, transaksi tetap 1.
    final day = ReportRange.preset(RangePreset.today, returnAt);
    final s = await ReportRepository(db, clock: () => returnAt).summary(day);
    expect(s.transactions, 1);
    expect(s.revenue, 16000 - 3500);
    expect(s.cost, 3 * 2800 + 4200 - 2800);
    expect(s.quantity, 3);

    // Daftar faktur: faktur asal "diretur sebagian", nota retur negatif.
    final list = await SalesRepository(db).watchDay(returnAt).first;
    final original = list.firstWhere((x) => x.id == saleId);
    expect(original.returnedAmount, 3500);
    expect(original.isPartlyReturned, isTrue);
    final note = list.firstWhere((x) => x.isReturn);
    expect(note.total, -3500);
    expect(note.returnReason, 'Kemasan rusak');

    // Sisa yang bisa diretur berkurang.
    final again = await service().load(saleId);
    expect(again.lines.firstWhere((l) => l.code == 'BRG001').returnable, 2);
  });

  test('batal semua: sisa dikembalikan persis, lalu tidak bisa diretur '
      'lagi', () async {
    final saleId = await sell();
    final sale = await service().load(saleId);
    final first = sale.lines.first;
    await service().create(
      actor: admin,
      saleId: saleId,
      qtys: {first.saleItemId: 1},
      reason: 'Salah ambil',
    );

    final rest = await service().load(saleId);
    final r = await service().create(
      actor: admin,
      saleId: saleId,
      qtys: {for (final l in rest.lines) l.saleItemId: l.returnable},
      reason: 'Batal',
    );
    expect(r.invoiceNo, endsWith('-0002'));
    expect(r.refund, 16000 - 3500);

    final list = await SalesRepository(db).watchDay(returnAt).first;
    expect(list.firstWhere((x) => x.id == saleId).isFullyReturned, isTrue);
    expect(
      () => service().create(
        actor: admin,
        saleId: saleId,
        qtys: {first.saleItemId: 1},
        reason: 'Lagi',
      ),
      throwsA(isA<ReturnFailure>()),
    );

    final day = ReportRange.preset(RangePreset.today, returnAt);
    final s = await ReportRepository(db, clock: () => returnAt).summary(day);
    expect(s.revenue, 0);
    expect(s.cost, 0);
  });

  test('aturan: alasan wajib, jumlah ≤ sisa, kasir tidak boleh, supervisor '
      'toko sendiri boleh', () async {
    final saleId = await sell();
    final line = (await service().load(saleId)).lines.first;

    Future<void> attempt(AppUser who, double qty, String reason) =>
        service().create(
          actor: who,
          saleId: saleId,
          qtys: {line.saleItemId: qty},
          reason: reason,
        );

    await expectLater(attempt(admin, 1, '  '), throwsA(isA<ReturnFailure>()));
    await expectLater(attempt(admin, 4, 'x'), throwsA(isA<ReturnFailure>()));
    await expectLater(attempt(admin, 0, 'x'), throwsA(isA<ReturnFailure>()));
    await expectLater(attempt(kasir, 1, 'x'), throwsA(isA<ReturnFailure>()));

    final supervisor = await UserRepository(db, testHasher).create(
      actor: admin,
      username: 'spv',
      fullName: 'Supervisor',
      role: UserRole.supervisor,
      storeId: store,
      password: 'rahasia1',
    );
    final spv = await AuthRepository(db, testHasher).login('spv', 'rahasia1');
    expect(spv.id, supervisor.id);
    await attempt(spv, 1, 'Retur pelanggan');
  });
}
