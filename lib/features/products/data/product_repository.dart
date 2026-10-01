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

  /// Untuk scan barcode / ketik kode di kasir: harus cocok persis.
  Future<Product?> findByCodeOrBarcode(String value) {
    if (value.trim().isEmpty) return Future.value(null);
    return _db.productsDao.findActiveByCodeOrBarcode(value);
  }

  Future<List<Product>> search(String text, {int limit = 50}) =>
      _db.productsDao.searchActive(text, limit: limit);

  /// Saran barang dengan nama yang mendekati [text] (salah ketik dll.),
  /// dipakai saat [search] tidak menemukan apa pun.
  Future<List<Product>> suggest(String text, {int limit = 8}) async {
    if (text.trim().length < 3) return const [];
    final names = await _db.productsDao.activeNames();
    final ids = FuzzyMatch.rank(text, names, (n) => n.$2, limit: limit);
    return _db.productsDao.byIds([for (final (id, _) in ids) id]);
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

  /// Menambah (`id == null`) atau mengubah barang. Perubahan stok dicatat
  /// sebagai riwayat stok jenis penyesuaian.
  Future<Product> save({
    required AppUser actor,
    int? id,
    required ProductDraft draft,
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
        stock: Value(draft.stock),
        minStock: Value(draft.minStock),
        isActive: Value(draft.isActive),
        updatedAt: Value(_clock()),
      );

      final savedId = id ?? await dao.insertProduct(data);
      if (id != null) await dao.updateProduct(id, data);

      final change = draft.stock - (current?.stock ?? 0);
      if (change != 0) {
        await dao.addStockMovement(
          productId: savedId,
          type: StockMovementType.adjust,
          qtyChange: change,
          note: current == null ? 'Stok awal' : 'Penyesuaian manual',
        );
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
