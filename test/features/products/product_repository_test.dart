import 'package:flutter_test/flutter_test.dart';
import 'package:toko/core/database/app_database.dart';
import 'package:toko/core/database/tables/sales.dart';
import 'package:toko/features/auth/data/auth_repository.dart';
import 'package:toko/features/auth/domain/app_user.dart';
import 'package:toko/features/payments/data/payment_method_repository.dart';
import 'package:toko/features/products/data/product_repository.dart';
import 'package:toko/features/products/domain/product.dart';
import 'package:toko/features/sales/data/checkout_service.dart';
import 'package:toko/features/sales/domain/cart.dart';

import '../../helpers/test_app.dart';

void main() {
  late AppDatabase db;
  late ProductRepository repo;
  late AppUser admin;
  late AppUser kasir;
  late int store;

  setUp(() async {
    db = await createSeededDb();
    repo = ProductRepository(db);
    final auth = AuthRepository(db, testHasher);
    admin = await auth.login('admin', 'admin123');
    kasir = await auth.login('kasir', 'kasir123');
    store = await mainStoreId(db);
  });

  tearDown(() => db.close());

  ProductDraft draft({
    String code = 'BRG100',
    String? barcode,
    String name = 'Kecap Bango 220ml',
    String? category = 'Bumbu',
    String? unit = 'btl',
    int buy = 9000,
    int sell = 11000,
    double min = 3,
  }) => ProductDraft(
    code: code,
    barcode: barcode,
    name: name,
    categoryName: category,
    unitName: unit,
    purchasePrice: buy,
    sellingPrice: sell,
    minStock: min,
  );

  /// Stok (dan harga khusus) di Toko Utama.
  List<StoreProductValues> at(double stock, {int? price}) => [
    StoreProductValues(storeId: store, stock: stock, price: price),
  ];

  test('tambah barang: kategori baru dibuat, satuan dipakai ulang', () async {
    final p = await repo.save(actor: admin, draft: draft(), stores: at(12));
    expect(p.categoryName, 'Bumbu');
    expect(p.unitName, 'BTL'); // "btl" → satuan BTL yang sudah ada
    final units = await db.select(db.units).get();
    expect(units.where((u) => u.name == 'BTL'), hasLength(1));
    // Stok awal tercatat di riwayat.
    final moves = await (db.select(
      db.stockMovements,
    )..where((m) => m.productId.equals(p.id))).get();
    expect(moves.single.qtyChange, 12);
    expect(moves.single.type, StockMovementType.adjust);
  });

  test('kode dan barcode tidak boleh dobel', () async {
    expect(
      repo.save(
        actor: admin,
        draft: draft(code: 'brg001'),
      ),
      throwsA(isA<ProductFailure>()),
    );
    final indomie = (await repo.findByCodeOrBarcode('BRG001'))!;
    expect(
      repo.save(
        actor: admin,
        draft: draft(barcode: indomie.barcode),
      ),
      throwsA(isA<ProductFailure>()),
    );
  });

  test('validasi: nama kosong, harga negatif, barcode berspasi', () {
    expect(
      repo.save(
        actor: admin,
        draft: draft(name: '  '),
      ),
      throwsA(isA<ProductFailure>()),
    );
    expect(
      repo.save(actor: admin, draft: draft(sell: -1)),
      throwsA(isA<ProductFailure>()),
    );
    expect(
      repo.save(
        actor: admin,
        draft: draft(barcode: '899 123'),
      ),
      throwsA(isA<ProductFailure>()),
    );
  });

  test('kasir tidak boleh mengelola barang', () {
    expect(
      repo.save(actor: kasir, draft: draft()),
      throwsA(isA<ProductFailure>()),
    );
  });

  test('ubah stok mencatat selisih sebagai penyesuaian', () async {
    final p = await repo.save(actor: admin, draft: draft(), stores: at(10));
    await repo.save(actor: admin, id: p.id, draft: draft(), stores: at(7));
    final moves = await (db.select(
      db.stockMovements,
    )..where((m) => m.productId.equals(p.id))).get();
    expect(moves.map((m) => m.qtyChange), [10, -3]);
    // Simpan tanpa mengubah stok tidak menambah riwayat.
    await repo.save(
      actor: admin,
      id: p.id,
      draft: draft(sell: 12000),
      stores: at(7),
    );
    expect(
      await (db.select(
        db.stockMovements,
      )..where((m) => m.productId.equals(p.id))).get(),
      hasLength(2),
    );
  });

  test('hapus: belum terjual dihapus, sudah terjual dinonaktifkan', () async {
    final baru = await repo.save(actor: admin, draft: draft());
    expect(
      await repo.remove(actor: admin, id: baru.id),
      ProductRemoval.deleted,
    );
    expect(await db.productsDao.findById(baru.id), isNull);

    final aqua = (await repo.findByCodeOrBarcode('BRG009'))!;
    final tunai = (await PaymentMethodRepository(db).watchAll().first).first;
    await CheckoutService(db).checkout(
      cart: const Cart().add(aqua),
      cashier: kasir,
      storeId: await mainStoreId(db),
      paymentMethodId: tunai.id,
      paid: 5000,
    );
    expect(
      await repo.remove(actor: admin, id: aqua.id),
      ProductRemoval.deactivated,
    );
    expect((await db.productsDao.findById(aqua.id))!.isActive, isFalse);
    // Barang nonaktif tidak muncul di kasir.
    expect(await repo.findByCodeOrBarcode('BRG009'), isNull);
  });

  group('daftar', () {
    Future<List<String>> codes(
      ProductFilter f, {
      int page = 0,
      int size = 50,
    }) async => (await repo.watchPage(f, page: page, pageSize: size).first)
        .map((p) => p.code)
        .toList();

    test('filter stok menipis dan kategori', () async {
      // Contoh: BRG007 (4 ≤ 6), BRG012 (3 ≤ 12), BRG018 (2 ≤ 5).
      expect(
        await codes(const ProductFilter(lowStockOnly: true)),
        unorderedEquals(['BRG007', 'BRG012', 'BRG018']),
      );
      final cats = await repo.watchCategories().first;
      final minuman = cats.firstWhere((c) => c.$2 == 'Minuman').$1;
      expect(await codes(ProductFilter(categoryId: minuman)), hasLength(4));
    });

    test('urutan dan halaman', () async {
      const f = ProductFilter(sort: ProductSort.stockLow);
      expect((await codes(f)).first, 'BRG018'); // stok 2
      expect(await codes(const ProductFilter(), size: 8), hasLength(8));
      expect(
        await codes(const ProductFilter(), page: 2, size: 8),
        hasLength(4),
      );
      expect(await repo.watchCount(const ProductFilter()).first, 20);
    });

    test('status aktif/nonaktif', () async {
      final p = await repo.save(actor: admin, draft: draft());
      await repo.save(
        actor: admin,
        id: p.id,
        draft: ProductDraft(
          code: p.code,
          name: p.name,
          sellingPrice: p.sellingPrice,
          isActive: false,
        ),
      );
      expect(
        await codes(const ProductFilter(status: ProductStatusFilter.inactive)),
        ['BRG100'],
      );
      expect(await repo.watchCount(const ProductFilter()).first, 20);
      expect(
        await repo
            .watchCount(const ProductFilter(status: ProductStatusFilter.all))
            .first,
        21,
      );
    });
  });
}
