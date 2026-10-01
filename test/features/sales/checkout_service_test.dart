import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:toko/core/database/app_database.dart';
import 'package:toko/features/auth/data/auth_repository.dart';
import 'package:toko/features/auth/data/user_repository.dart';
import 'package:toko/features/auth/domain/app_user.dart';
import 'package:toko/features/products/data/product_repository.dart';
import 'package:toko/features/sales/data/checkout_service.dart';
import 'package:toko/features/sales/data/sales_repository.dart';
import 'package:toko/features/sales/domain/cart.dart';

import '../../helpers/test_app.dart';

void main() {
  late AppDatabase db;
  late ProductRepository products;
  late AppUser kasir;
  final clock = DateTime(2026, 9, 30, 10, 15);

  setUp(() async {
    db = await createSeededDb();
    products = ProductRepository(db);
    kasir = await AuthRepository(db, testHasher).login('kasir', 'kasir123');
  });

  tearDown(() => db.close());

  CheckoutService service() => CheckoutService(db, clock: () => clock);

  test('20 barang contoh tersedia dan bisa dicari', () async {
    expect(await db.select(db.products).get(), hasLength(20));
    final byCode = await products.findByCodeOrBarcode('brg001');
    expect(byCode?.name, 'Indomie Goreng 85g');
    final byBarcode = await products.findByCodeOrBarcode(byCode!.barcode!);
    expect(byBarcode?.id, byCode.id);
    final found = await products.search('indomie');
    expect(found, hasLength(2));
  });

  test(
    'checkout menyimpan faktur, mengurangi stok, dan mencatat riwayat',
    () async {
      final indomie = (await products.findByCodeOrBarcode('BRG001'))!;
      final telur = (await products.findByCodeOrBarcode('BRG008'))!;
      final cart = const Cart()
          .add(indomie, qty: 5)
          .add(telur, qty: 0.5)
          .setDiscount(DiscountType.amount, 500);

      final result = await service().checkout(
        cart: cart,
        cashier: kasir,
        paid: 50000,
      );

      expect(result.invoiceNo, 'INV-20260930-0001');
      expect(result.total, 5 * 3500 + 14500 - 500);
      expect(result.change, 50000 - result.total);

      final after = (await products.findByCodeOrBarcode('BRG001'))!;
      expect(after.stock, indomie.stock - 5);
      final telurAfter = (await products.findByCodeOrBarcode('BRG008'))!;
      expect(telurAfter.stock, closeTo(telur.stock - 0.5, 1e-9));

      final moves = await db.select(db.stockMovements).get();
      expect(moves, hasLength(2));
      expect(moves.first.refId, result.saleId);

      final lines = await SalesRepository(db).linesOf(result.saleId);
      expect(lines.map((l) => l.name), ['Indomie Goreng 85g', 'Telur Ayam']);
    },
  );

  test('nomor faktur berurutan dalam satu hari', () async {
    final p = (await products.findByCodeOrBarcode('BRG009'))!;
    final cart = const Cart().add(p);
    final a = await service().checkout(cart: cart, cashier: kasir, paid: 5000);
    final b = await service().checkout(cart: cart, cashier: kasir, paid: 5000);
    expect(a.invoiceNo, 'INV-20260930-0001');
    expect(b.invoiceNo, 'INV-20260930-0002');
  });

  test('uang kurang ditolak dan tidak ada yang tersimpan', () async {
    final p = (await products.findByCodeOrBarcode('BRG005'))!;
    await expectLater(
      service().checkout(cart: const Cart().add(p), cashier: kasir, paid: 1000),
      throwsA(isA<CheckoutFailure>()),
    );
    expect(await db.select(db.sales).get(), isEmpty);
    expect((await products.findByCodeOrBarcode('BRG005'))!.stock, p.stock);
  });

  test('transaksi hari ini muncul di daftar beserta nama kasir', () async {
    final p = (await products.findByCodeOrBarcode('BRG010'))!;
    await service().checkout(
      cart: const Cart().add(p),
      cashier: kasir,
      paid: 10000,
    );
    final today = await SalesRepository(db).watchDay(clock).first;
    expect(today, hasLength(1));
    expect(today.single.cashierName, 'Kasir Satu');
    final yesterday = await SalesRepository(db)
        .watchDay(clock.subtract(const Duration(days: 1)))
        .first;
    expect(yesterday, isEmpty);
  });

  test('akun yang punya transaksi tidak bisa dihapus', () async {
    final admin = await AuthRepository(
      db,
      testHasher,
    ).login('admin', 'admin123');
    final p = (await products.findByCodeOrBarcode('BRG010'))!;
    await service().checkout(
      cart: const Cart().add(p),
      cashier: kasir,
      paid: 10000,
    );
    expect(
      UserRepository(db, testHasher).delete(actor: admin, id: kasir.id),
      throwsA(isA<AccountFailure>()),
    );
  });

  test('database v1 lama di-upgrade ke v2 tanpa kehilangan user', () async {
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

    final users = await upgraded.select(upgraded.users).get();
    expect(users.single.username, 'lama');
    expect(await upgraded.select(upgraded.products).get(), hasLength(20));
    expect(await upgraded.select(upgraded.sales).get(), isEmpty);
  });
}
