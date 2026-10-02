import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:toko/core/database/app_database.dart';
import 'package:toko/features/auth/data/auth_repository.dart';
import 'package:toko/features/auth/domain/app_user.dart';
import 'package:toko/features/products/data/product_repository.dart';
import 'package:toko/features/sales/data/held_cart_repository.dart';
import 'package:toko/features/sales/domain/cart.dart';

import '../../helpers/test_app.dart';

void main() {
  late AppDatabase db;
  late ProductRepository products;
  late AppUser kasir;
  late int store;
  var now = DateTime(2026, 10, 1, 10, 0);

  setUp(() async {
    db = await createSeededDb();
    products = ProductRepository(db);
    kasir = await AuthRepository(db, testHasher).login('kasir', 'kasir123');
    store = await mainStoreId(db);
    now = DateTime(2026, 10, 1, 10, 0);
  });

  tearDown(() => db.close());

  HeldCartRepository repo() => HeldCartRepository(db, clock: () => now);

  Future<Cart> cartOf(Map<String, double> items) async {
    var cart = const Cart();
    for (final e in items.entries) {
      cart = cart.add(
        (await products.findByCodeOrBarcode(e.key))!,
        qty: e.value,
      );
    }
    return cart;
  }

  test('tahan lalu lanjutkan: isi sama, catatan tersimpan, lalu hilang '
      'dari daftar', () async {
    final cart = await cartOf({'BRG001': 2, 'BRG009': 1.5});
    await repo().hold(
      cart: cart,
      cashier: kasir,
      storeId: store,
      note: '  Ibu A  ',
    );

    final list = await repo().watchToday(storeId: store).first;
    expect(list.single.note, 'Ibu A');
    expect(list.single.cashierName, kasir.fullName);
    expect(list.single.total, cart.total);
    expect(list.single.items.map((i) => i.qty), [2, 1.5]);

    final resumed = await repo().resume(list.single.id);
    expect(resumed.skipped, isEmpty);
    expect(resumed.cart.lines.map((l) => l.product.code), ['BRG001', 'BRG009']);
    expect(resumed.cart.total, cart.total);
    expect(await repo().watchToday(storeId: store).first, isEmpty);

    // Dilanjutkan dua kali (mis. dua klik cepat) ditolak.
    expect(
      () => repo().resume(list.single.id),
      throwsA(isA<HeldCartFailure>()),
    );
  });

  test(
    'catatan kosong disimpan sebagai null, keranjang kosong ditolak',
    () async {
      await repo().hold(
        cart: await cartOf({'BRG001': 1}),
        cashier: kasir,
        storeId: store,
        note: '   ',
      );
      expect(
        (await repo().watchToday(storeId: store).first).single.note,
        isNull,
      );
      expect(
        () => repo().hold(cart: const Cart(), cashier: kasir, storeId: store),
        throwsA(isA<HeldCartFailure>()),
      );
    },
  );

  test('harga mengikuti harga terbaru; barang nonaktif dilewati', () async {
    await repo().hold(
      cart: await cartOf({'BRG001': 2, 'BRG002': 1}),
      cashier: kasir,
      storeId: store,
    );
    await (db.update(db.products)..where((p) => p.code.equals('BRG001'))).write(
      const ProductsCompanion(sellingPrice: Value(4000)),
    );
    await (db.update(db.products)..where((p) => p.code.equals('BRG002'))).write(
      const ProductsCompanion(isActive: Value(false)),
    );

    final id = (await repo().watchToday(storeId: store).first).single.id;
    final resumed = await repo().resume(id);
    expect(resumed.cart.lines.single.product.code, 'BRG001');
    expect(resumed.cart.total, 8000);
    expect(resumed.skipped, ['Indomie Ayam Bawang 69g']);
  });

  test('hanya berlaku hari itu: kemarin tidak tampil dan dihapus', () async {
    now = DateTime(2026, 9, 30, 21, 0);
    await repo().hold(
      cart: await cartOf({'BRG001': 1}),
      cashier: kasir,
      storeId: store,
    );
    now = DateTime(2026, 10, 1, 8, 0);
    await repo().hold(
      cart: await cartOf({'BRG009': 1}),
      cashier: kasir,
      storeId: store,
    );

    final today = await repo().watchToday(storeId: store).first;
    expect(today.single.items.single.code, 'BRG009');

    expect(await repo().purgeExpired(), 1);
    expect(await db.select(db.heldCarts).get(), hasLength(1));
  });
}
