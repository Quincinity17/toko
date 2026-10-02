import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/sales.dart';
import '../../auth/domain/app_user.dart';
import '../domain/fuzzy_match.dart';
import '../domain/product.dart';

class ProductFailure implements Exception {
  const ProductFailure(this.message);

  final String message;

  @override
  String toString() => 'ProductFailure: $message';
}

enum ProductRemoval {
  /// Barang belum pernah terjual, dihapus permanen.
  deleted,

  /// Barang sudah pernah terjual, hanya dinonaktifkan agar faktur lama utuh.
  deactivated,
}

class ProductRepository {
  ProductRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  // ---------------------------------------------------------------------------
  // Kasir
  // ---------------------------------------------------------------------------

  // Harga & stok mengikuti toko [storeId] (`null` = semua toko).

  /// Untuk scan barcode / ketik kode di kasir: harus cocok persis.
  Future<Product?> findByCodeOrBarcode(String value, {int? storeId}) {
    if (value.trim().isEmpty) return Future.value(null);
    return _db.productsDao.findActiveByCodeOrBarcode(value, storeId: storeId);
  }

  Future<List<Product>> search(String text, {int? storeId, int limit = 50}) =>
      _db.productsDao.searchActive(text, storeId: storeId, limit: limit);

  /// Saran barang dengan nama yang mendekati [text] (salah ketik dll.),
  /// dipakai saat [search] tidak menemukan apa pun.
  Future<List<Product>> suggest(
    String text, {
    int? storeId,
    int limit = 8,
  }) async {
    if (text.trim().length < 3) return const [];
    final names = await _db.productsDao.activeNames();
    final ids = FuzzyMatch.rank(text, names, (n) => n.$2, limit: limit);
    return _db.productsDao.byIds([
      for (final (id, _) in ids) id,
    ], storeId: storeId);
  }

  // ---------------------------------------------------------------------------
  // Master barang (admin)
  // ---------------------------------------------------------------------------

  Stream<List<Product>> watchPage(
    ProductFilter filter, {
    required int page,
    required int pageSize,
  }) => _db.productsDao.watchPage(
    filter,
    offset: page * pageSize,
    limit: pageSize,
  );

  Stream<int> watchCount(ProductFilter filter) =>
      _db.productsDao.watchCount(filter);

  Future<List<Product>> allMatching(ProductFilter filter) =>
      _db.productsDao.allMatching(filter);

  Stream<List<(int, String)>> watchCategories() => _db.productsDao
      .watchCategories()
      .map((rows) => [for (final r in rows) (r.id, r.name)]);

  Stream<List<String>> watchUnitNames() => _db.productsDao.watchUnits().map(
    (rows) => [for (final r in rows) r.name],
  );

  /// Stok dan harga khusus barang [productId] di setiap toko yang punya
  /// datanya (`storeId → (stok, harga khusus)`), untuk form barang.
  Future<Map<int, ({double stock, int? price})>> storeValues(
    int productId,
  ) async => {
    for (final e in await _db.storesDao.entriesOf(productId))
      e.storeId: (stock: e.stock, price: e.sellingPrice),
  };

  /// Menambah (`id == null`) atau mengubah barang, beserta stok & harga
  /// khusus per toko ([stores]; toko yang tidak disebut tidak diubah).
  /// Perubahan stok dicatat sebagai riwayat stok jenis penyesuaian.
  Future<Product> save({
    required AppUser actor,
    int? id,
    required ProductDraft draft,
    List<StoreProductValues> stores = const [],
  }) async {
    _requireAdmin(actor);
    final code = draft.code.trim();
    final barcode = (draft.barcode?.trim().isEmpty ?? true)
        ? null
        : draft.barcode!.trim();
    _check(ProductRules.code(code));
    _check(ProductRules.barcode(barcode));
    _check(ProductRules.name(draft.name));
    _check(ProductRules.price(draft.purchasePrice, label: 'Harga beli'));
    _check(ProductRules.price(draft.sellingPrice, label: 'Harga jual'));
    _check(ProductRules.minStock(draft.minStock));
    for (final v in stores) {
      if (v.price != null) {
        _check(ProductRules.price(v.price, label: 'Harga jual toko'));
      }
    }

    final dao = _db.productsDao;
    return _db.transaction(() async {
      final current = id == null ? null : await dao.findById(id);
      if (id != null && current == null) {
        throw const ProductFailure('Barang tidak ditemukan.');
      }

      final sameCode = await dao.findByCode(code);
      if (sameCode != null && sameCode.id != id) {
        throw ProductFailure(
          'Kode "$code" sudah dipakai oleh "${sameCode.name}".',
        );
      }
      if (barcode != null) {
        final sameBarcode = await dao.findByBarcode(barcode);
        if (sameBarcode != null && sameBarcode.id != id) {
          throw ProductFailure(
            'Barcode $barcode sudah dipakai oleh "${sameBarcode.name}".',
          );
        }
      }

      final data = ProductsCompanion(
        code: Value(code),
        barcode: Value(barcode),
        name: Value(draft.name.trim()),
        categoryId: Value(await dao.categoryIdFor(draft.categoryName)),
        unitId: Value(await dao.unitIdFor(draft.unitName)),
        purchasePrice: Value(draft.purchasePrice),
        sellingPrice: Value(draft.sellingPrice),
        minStock: Value(draft.minStock),
        isActive: Value(draft.isActive),
        updatedAt: Value(_clock()),
      );

      final savedId = id ?? await dao.insertProduct(data);
      if (id != null) await dao.updateProduct(id, data);

      final storesDao = _db.storesDao;
      for (final v in stores) {
        final entry = await storesDao.entry(v.storeId, savedId);
        // Harga sama dengan default disimpan sebagai "tanpa harga khusus".
        final price = v.price == draft.sellingPrice ? null : v.price;
        if (price != entry?.sellingPrice) {
          await storesDao.setPrice(
            storeId: v.storeId,
            productId: savedId,
            price: price,
          );
        }
        final change = v.stock - (entry?.stock ?? 0);
        if (change != 0) {
          await storesDao.changeStock(
            storeId: v.storeId,
            productId: savedId,
            delta: change,
            type: StockMovementType.adjust,
            userId: actor.id,
            note: current == null ? 'Stok awal' : 'Penyesuaian manual',
          );
        }
      }
      return (await dao.findById(savedId))!;
    });
  }

  /// Menghapus barang. Barang yang sudah pernah terjual hanya dinonaktifkan.
  Future<ProductRemoval> remove({
    required AppUser actor,
    required int id,
  }) async {
    _requireAdmin(actor);
    final dao = _db.productsDao;
    return _db.transaction(() async {
      if (await dao.countSaleItems(id) > 0) {
        await dao.updateProduct(
          id,
          ProductsCompanion(
            isActive: const Value(false),
            updatedAt: Value(_clock()),
          ),
        );
        return ProductRemoval.deactivated;
      }
      await dao.deleteProduct(id);
      return ProductRemoval.deleted;
    });
  }

  void _requireAdmin(AppUser actor) {
    if (!actor.isAdmin) {
      throw const ProductFailure('Hanya admin yang bisa mengelola barang.');
    }
  }

  void _check(String? error) {
    if (error != null) throw ProductFailure(error);
  }
}

final productRepositoryProvider = Provider<ProductRepository>(
  (ref) => ProductRepository(ref.watch(appDatabaseProvider)),
);
