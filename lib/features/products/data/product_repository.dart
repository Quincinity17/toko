import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/audit.dart';
import '../../../core/database/tables/sales.dart';
import '../../../core/utils/formatters.dart';
import '../../auth/domain/app_user.dart';
import '../domain/bulk_entry.dart';
import '../domain/code_sequence.dart';
import '../domain/fuzzy_match.dart';
import '../domain/product.dart';
import '../domain/similar_names.dart';
import '../domain/tag.dart';

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

  static const kAutoCodeSetting = 'products.auto_code';

  /// Barcode berikutnya untuk barang baru (lihat [CodeSequence]); `null`
  /// bila belum ada barcode berakhiran angka.
  Future<({String next, String basedOn})?> nextCode() async =>
      CodeSequence.next(await codesNewestFirst());

  /// Semua barcode (kode) barang, terbaru dulu; bahan [CodeSequence].
  Future<List<String>> codesNewestFirst() => _db.productsDao.codesNewestFirst();

  /// Nama baru yang sama / mirip dengan barang aktif atau dengan nama lain
  /// di [names] (lihat [SimilarNames]). Dipanggil sekali saat menyimpan.
  Future<List<SimilarName>> similarNames(List<(int, String)> names) async {
    if (names.isEmpty) return const [];
    final existing = await _db.productsDao.activeNameCodes();
    // Banyak baris × banyak barang: hitung di isolate agar UI tidak macet.
    if (names.length * existing.length > 100000) {
      return Isolate.run(() => SimilarNames.find(names, existing));
    }
    return SimilarNames.find(names, existing);
  }

  static const kBulkDraftSetting = 'products.bulk_draft';

  /// Draf Input Tabel yang disimpan saat keluar (per komputer).
  Future<List<BulkRowValues>> loadBulkDraft() async =>
      BulkEntry.decodeDraft(await _db.settingsDao.get(kBulkDraftSetting));

  /// Menyimpan draf; tanpa baris terisi = draf dihapus.
  Future<void> saveBulkDraft(List<BulkRowValues> rows) =>
      _db.settingsDao.set(kBulkDraftSetting, BulkEntry.encodeDraft(rows));

  Future<void> clearBulkDraft() => _db.settingsDao.set(kBulkDraftSetting, '');

  /// Pilihan terakhir centang "Otomatis" di form barang (per komputer).
  Future<bool> autoCodeEnabled() async =>
      await _db.settingsDao.get(kAutoCodeSetting) == '1';

  Future<void> setAutoCode(bool enabled) =>
      _db.settingsDao.set(kAutoCodeSetting, enabled ? '1' : '0');

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
    for (final t in draft.tagNames ?? const <String>[]) {
      _check(TagRules.name(t));
    }
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
          'Barcode "$code" sudah dipakai oleh "${sameCode.name}".',
        );
      }
      if (barcode != null) {
        final sameBarcode = await dao.findByBarcode(barcode);
        if (sameBarcode != null && sameBarcode.id != id) {
          throw ProductFailure(
            'Barcode bawaan $barcode sudah dipakai oleh '
            '"${sameBarcode.name}".',
          );
        }
      }

      final data = ProductsCompanion(
        code: Value(code),
        barcode: Value(barcode),
        name: Value(draft.name.trim()),
        unitId: Value(await dao.unitIdFor(draft.unitName)),
        purchasePrice: Value(draft.purchasePrice),
        sellingPrice: Value(draft.sellingPrice),
        minStock: Value(draft.minStock),
        isActive: Value(draft.isActive),
        updatedAt: Value(_clock()),
      );

      final savedId = id ?? await dao.insertProduct(data);
      if (id != null) await dao.updateProduct(id, data);

      // Daftar perubahan untuk catatan aktivitas.
      final changes = <String>[
        if (current != null) ...[
          if (current.code != code) 'barcode ${current.code} → $code',
          if (current.name != draft.name.trim())
            'nama "${current.name}" → "${draft.name.trim()}"',
          if (current.purchasePrice != draft.purchasePrice)
            'harga beli ${Fmt.rupiah(current.purchasePrice)} → '
                '${Fmt.rupiah(draft.purchasePrice)}',
          if (current.defaultSellingPrice != draft.sellingPrice)
            'harga jual ${Fmt.rupiah(current.defaultSellingPrice)} → '
                '${Fmt.rupiah(draft.sellingPrice)}',
          if (current.isActive != draft.isActive)
            draft.isActive ? 'diaktifkan' : 'dinonaktifkan',
        ],
      ];

      final storesDao = _db.storesDao;
      for (final v in stores) {
        final entry = await storesDao.entry(v.storeId, savedId);
        final storeName =
            (await storesDao.findById(v.storeId))?.name ?? 'toko ${v.storeId}';
        // Harga sama dengan default disimpan sebagai "tanpa harga khusus".
        final price = v.price == draft.sellingPrice ? null : v.price;
        if (price != entry?.sellingPrice) {
          if (current != null) {
            changes.add(
              'harga $storeName ${entry?.sellingPrice == null ? 'default' : Fmt.rupiah(entry!.sellingPrice!)}'
              ' → ${price == null ? 'default' : Fmt.rupiah(price)}',
            );
          }
          await storesDao.setPrice(
            storeId: v.storeId,
            productId: savedId,
            price: price,
          );
        }
        final change = v.stock - (entry?.stock ?? 0);
        if (change != 0) {
          changes.add(
            'stok $storeName ${Fmt.number(entry?.stock ?? 0)} → '
            '${Fmt.number(v.stock)}',
          );
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
      // Tag baru (nama belum ada) dibuat otomatis, seperti kategori.
      final tagNames = draft.tagNames;
      if (tagNames != null) {
        await _db.tagsDao.setProductTags(
          savedId,
          await _db.tagsDao.idsForNames(tagNames),
        );
      }
      if (current == null || changes.isNotEmpty) {
        await _db.auditDao.append(
          type: current == null
              ? AuditType.productCreated
              : AuditType.productUpdated,
          summary: current == null
              ? 'Barang baru $code · ${draft.name.trim()} '
                    '(${Fmt.rupiah(draft.sellingPrice)})'
              : '$code · ${draft.name.trim()}: ${changes.join('; ')}',
          userId: actor.id,
          userName: actor.fullName,
          data: {'productId': savedId, 'code': code, 'changes': changes},
          at: _clock(),
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
      final product = await dao.findById(id);
      Future<void> log(String what) => _db.auditDao.append(
        type: AuditType.productDeleted,
        summary: '${product?.code} · ${product?.name}: $what',
        userId: actor.id,
        userName: actor.fullName,
        data: {'productId': id, 'code': product?.code},
        at: _clock(),
      );
      if (await dao.countSaleItems(id) > 0) {
        await log('dinonaktifkan (sudah pernah terjual)');
        await dao.updateProduct(
          id,
          ProductsCompanion(
            isActive: const Value(false),
            updatedAt: Value(_clock()),
          ),
        );
        return ProductRemoval.deactivated;
      }
      await log('dihapus');
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
