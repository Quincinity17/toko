import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show listEquals;
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
import '../domain/product_pricing.dart';
import '../domain/similar_names.dart';
import '../domain/tag.dart';
import '../../sync/data/terminal_repository.dart';

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

  /// Untuk kasir: barcode/kode barang, atau barcode kemasan satuan lain
  /// (hasilnya membawa satuan itu).
  Future<ScanMatch?> scan(String value, {int? storeId}) async {
    final product = await findByCodeOrBarcode(value, storeId: storeId);
    if (product != null) return ScanMatch(product);
    if (value.trim().isEmpty) return null;
    final byUnit = await _db.productsDao.findActiveByUnitBarcode(
      value,
      storeId: storeId,
    );
    if (byUnit == null) return null;
    final (p, unitId) = byUnit;
    return ScanMatch(p, unit: p.unitById(unitId));
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

  /// Stok, harga khusus, harga satuan lain, dan grosir barang
  /// [productId] di setiap toko yang punya datanya, untuk form barang.
  Future<Map<int, StoreProductSaved>> storeValues(int productId) async {
    final dao = _db.productsDao;
    final entries = await _db.storesDao.entriesOf(productId);
    final unitPrices = await dao.storeUnitPricesOf(productId);
    final tiers = await dao.storeTiersOf(productId);
    final ids = {
      for (final e in entries) e.storeId,
      for (final (store, _, _) in unitPrices) store,
      for (final t in tiers) t.storeId!,
    };
    final entryOf = {for (final e in entries) e.storeId: e};
    return {
      for (final id in ids)
        id: StoreProductSaved(
          stock: entryOf[id]?.stock ?? 0,
          price: entryOf[id]?.sellingPrice,
          unitPrices: {
            for (final (store, name, price) in unitPrices)
              if (store == id) name: price,
          },
          tiers: [
            for (final t in tiers)
              if (t.storeId == id) PriceTier(minQty: t.minQty, price: t.price),
          ],
        ),
    };
  }

  static const kAutoCodeSetting = 'products.auto_code';

  /// Barcode berikutnya untuk barang baru (lihat [CodeSequence]): seri
  /// mengikuti kategori pertama di [categories] yang sudah punya barcode
  /// bernomor, dan nomor yang terlewat diisi dulu. `null` bila belum ada
  /// barcode berakhiran angka.
  Future<CodeSuggestion?> nextCode({
    List<String> categories = const [],
    Iterable<String> alsoTaken = const [],
  }) async {
    final all = await codesNewestFirst();
    final taken = [...alsoTaken, ...await _db.productsDao.unitBarcodes()];
    for (final name in categories) {
      final tag = await _db.tagsDao.findByName(name.trim());
      final next = CodeSequence.next(
        all,
        series: await _db.productsDao.codesInTag(name),
        fixedPrefix: tag?.codePrefix,
        minWidth: tag?.codeDigits,
        category: tag?.name ?? name.trim(),
        alsoTaken: taken,
      );
      if (next?.category != null) return next;
    }
    return CodeSequence.next(all, alsoTaken: taken);
  }

  /// Kode barang & awalan barcode per kategori (kunci huruf kecil), untuk
  /// barcode otomatis Input Tabel.
  Future<Map<String, ({List<String> codes, String? prefix, int? digits})>>
  codesByCategory(Iterable<String> names) async => {
    for (final n in {for (final n in names) n.trim().toLowerCase()})
      n: (
        codes: await _db.productsDao.codesInTag(n),
        prefix: (await _db.tagsDao.findByName(n))?.codePrefix,
        digits: (await _db.tagsDao.findByName(n))?.codeDigits,
      ),
  };

  /// Barcode kemasan (satuan lain); tidak boleh dipakai barcode otomatis.
  Future<List<String>> unitBarcodes() => _db.productsDao.unitBarcodes();

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
    await _requireMaster();
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
      for (final p in (v.unitPrices ?? const <String, int?>{}).values) {
        if (p != null) {
          _check(ProductRules.price(p, label: 'Harga satuan toko'));
        }
      }
      if (v.tiers case final tiers?) {
        _check(
          PricingRules.tiers(
            tiers,
            sellingPrice: v.price ?? draft.sellingPrice,
          ),
        );
      }
    }
    if (draft.units case final units?) {
      _check(
        PricingRules.units(
          units,
          baseUnit: draft.unitName,
          code: code,
          barcode: barcode,
        ),
      );
    }
    if (draft.tiers case final tiers?) {
      _check(PricingRules.tiers(tiers, sellingPrice: draft.sellingPrice));
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
      // Barcode barang tidak boleh sama dengan barcode kemasan barang lain,
      // dan sebaliknya.
      for (final b in {code, ?barcode}) {
        final unit = await dao.findUnitByBarcode(b);
        if (unit != null && unit.productId != id) {
          final owner = await dao.findById(unit.productId);
          throw ProductFailure(
            'Barcode $b sudah dipakai satuan ${unit.name} '
            '"${owner?.name ?? '-'}".',
          );
        }
      }
      for (final u in draft.units ?? const <ProductUnit>[]) {
        final b = u.barcode?.trim() ?? '';
        if (b.isEmpty) continue;
        final other =
            await dao.findByCode(b) ??
            await dao.findByBarcode(b) ??
            await _unitOwner(b, exceptProduct: id);
        if (other != null && other.id != id) {
          throw ProductFailure(
            'Barcode satuan ${PricingRules.unitName(u.name)} ($b) sudah '
            'dipakai oleh "${other.name}".',
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
          if (draft.units case final u? when !_sameUnits(current.units, u))
            'satuan lain ${_unitsText(current.units)} → ${_unitsText(u)}',
          if (draft.tiers case final t? when !listEquals(current.tiers, t))
            'harga grosir ${_tiersText(current.tiers)} → ${_tiersText(t)}',
        ],
      ];
      if (draft.units != null || draft.tiers != null) {
        await dao.setPricing(
          savedId,
          unitList: draft.units,
          tierList: draft.tiers == null
              ? null
              : ([...draft.tiers!]
                  ..sort((a, b) => a.minQty.compareTo(b.minQty))),
        );
      }

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
        await _saveStorePricing(
          savedId,
          v,
          storeName,
          changes: current == null ? null : changes,
        );
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
    await _requireMaster();
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

  /// Harga satuan lain & grosir khusus toko [v] (lihat
  /// [StoreProductValues]). Perubahan dicatat di [changes] (ubah barang).
  Future<void> _saveStorePricing(
    int productId,
    StoreProductValues v,
    String storeName, {
    List<String>? changes,
  }) async {
    final dao = _db.productsDao;
    final unitPrices = v.unitPrices;
    final tiers = v.tiers;
    if (unitPrices == null && tiers == null) return;
    final saved = (await storeValues(productId))[v.storeId];
    final units = (await dao.findById(productId))?.units ?? const [];
    if (unitPrices != null) {
      for (final u in units) {
        var price = unitPrices[PricingRules.unitName(u.name)];
        // Sama dengan harga satuan itu = tanpa harga khusus.
        if (price == u.defaultPrice) price = null;
        final before = saved?.unitPrices[u.name];
        if (price == before) continue;
        changes?.add(
          'harga ${u.name} $storeName '
          '${before == null ? 'default' : Fmt.rupiah(before)} → '
          '${price == null ? 'default' : Fmt.rupiah(price)}',
        );
        await dao.setStoreUnitPrice(v.storeId, u.id!, price);
      }
    }
    if (tiers != null) {
      final sorted = [...tiers]..sort((a, b) => a.minQty.compareTo(b.minQty));
      final before = saved?.tiers ?? const <PriceTier>[];
      if (!listEquals(before, sorted)) {
        changes?.add(
          'grosir $storeName ${before.isEmpty ? 'ikut semua toko' : _tiersText(before)}'
          ' → ${sorted.isEmpty ? 'ikut semua toko' : _tiersText(sorted)}',
        );
        await dao.setStoreTiers(productId, v.storeId, sorted);
      }
    }
    await _db.sealsDao.resealPricing(productId);
  }

  /// Barang pemilik satuan dengan barcode kemasan [barcode], selain
  /// [exceptProduct].
  Future<ProductRow?> _unitOwner(String barcode, {int? exceptProduct}) async {
    final unit = await _db.productsDao.findUnitByBarcode(barcode);
    if (unit == null || unit.productId == exceptProduct) return null;
    return (_db.select(
      _db.products,
    )..where((p) => p.id.equals(unit.productId))).getSingleOrNull();
  }

  static bool _sameUnits(List<ProductUnit> a, List<ProductUnit> b) {
    String key(ProductUnit u) =>
        '${PricingRules.unitName(u.name)}|${u.factor}|'
        '${u.barcode?.trim() ?? ''}|${u.defaultPrice}';
    return listEquals(
      [for (final u in a) key(u)]..sort(),
      [for (final u in b) key(u)]..sort(),
    );
  }

  static String _unitsText(List<ProductUnit> units) => units.isEmpty
      ? '(tidak ada)'
      : units
            .map(
              (u) =>
                  '${PricingRules.unitName(u.name)} isi ${Fmt.number(u.factor)} '
                  '${Fmt.rupiah(u.defaultPrice)}',
            )
            .join(', ');

  static String _tiersText(List<PriceTier> tiers) => tiers.isEmpty
      ? '(tidak ada)'
      : tiers
            .map((t) => '≥${Fmt.number(t.minQty)} ${Fmt.rupiah(t.price)}')
            .join(', ');

  /// Data master hanya diubah di komputer server (lihat sinkron).
  Future<void> _requireMaster() async {
    final message = await TerminalRepository.masterLockMessage(_db);
    if (message != null) throw ProductFailure(message);
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

/// Hasil scan kasir: barang, dan satuan lainnya bila yang di-scan barcode
/// kemasan.
class ScanMatch {
  const ScanMatch(this.product, {this.unit});

  final Product product;
  final ProductUnit? unit;
}

final productRepositoryProvider = Provider<ProductRepository>(
  (ref) => ProductRepository(ref.watch(appDatabaseProvider)),
);
