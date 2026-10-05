import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/audit.dart';
import '../../../core/database/tables/sales.dart';
import '../../auth/domain/app_user.dart';
import '../domain/product.dart';
import '../domain/product_import.dart';
import '../domain/tag.dart';
import 'product_repository.dart';

/// Menjalankan import barang dari baris yang sudah diperiksa
/// ([validateImport]). Semua perubahan dalam satu database transaction:
/// jika ada kegagalan tak terduga, tidak ada yang tersimpan sebagian.
class ProductImportService {
  ProductImportService(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  /// Kode dan barcode yang sudah ada, untuk pemeriksaan sebelum import.
  Future<ExistingIndex> existingIndex() async {
    final rows =
        await (_db.selectOnly(_db.products)..addColumns([
              _db.products.id,
              _db.products.code,
              _db.products.barcode,
            ]))
            .get();
    final byCode = <String, int>{};
    final byBarcode = <String, int>{};
    for (final r in rows) {
      final id = r.read(_db.products.id)!;
      byCode[r.read(_db.products.code)!.toLowerCase()] = id;
      final b = r.read(_db.products.barcode);
      if (b != null) byBarcode[b] = id;
    }
    return ExistingIndex(idByCode: byCode, idByBarcode: byBarcode);
  }

  /// Harga jual di file menjadi harga default barang; kolom Stok masuk ke
  /// toko [stockStoreId] (wajib jika file berisi stok).
  Future<ImportResult> run({
    required AppUser actor,
    required List<ImportRow> rows,
    required ExistingProductAction existingAction,
    int? stockStoreId,
    void Function(int done, int total)? onProgress,
  }) async {
    if (!actor.isAdmin) {
      throw const ProductFailure('Hanya admin yang bisa import barang.');
    }
    final valid = rows.where((r) => r.isValid).toList();
    final failed = rows.where((r) => !r.isValid).toList();
    final hasStock = valid.any((r) => r.provided.contains(ProductField.stock));
    if (hasStock && stockStoreId == null) {
      throw const ProductFailure('Pilih toko tujuan untuk stok dari file.');
    }

    return _db.transaction(() async {
      // Kategori = tag (lihat CLAUDE.md "Kategori").
      final categories = {
        for (final t in await _db.select(_db.tags).get())
          t.name.toLowerCase(): t.id,
      };
      final units = {
        for (final u in await _db.select(_db.units).get())
          u.name.toUpperCase(): u.id,
      };
      var newCategories = 0, newUnits = 0;

      /// Id kategori untuk nama-nama itu; yang belum ada dibuat (warna
      /// bergiliran) dan dihitung sebagai kategori baru.
      Future<List<int>> categoryIds(List<String> names) async {
        final ids = <int>{};
        for (final raw in names) {
          final n = raw.trim();
          if (n.isEmpty) continue;
          final key = n.toLowerCase();
          var id = categories[key];
          if (id == null) {
            final color =
                TagColor.values[categories.length % TagColor.values.length];
            id = await _db
                .into(_db.tags)
                .insert(
                  TagsCompanion.insert(name: n, color: Value(color.name)),
                );
            categories[key] = id;
            newCategories++;
          }
          ids.add(id);
        }
        return ids.toList();
      }

      Future<int?> unitId(String? name) async {
        final n = name?.trim().toUpperCase() ?? '';
        if (n.isEmpty) return null;
        if (units[n] case final id?) return id;
        newUnits++;
        return units[n] = await _db
            .into(_db.units)
            .insert(UnitsCompanion.insert(name: n));
      }

      final dao = _db.productsDao;
      final storesDao = _db.storesDao;
      final now = _clock();
      var inserted = 0, updated = 0, skipped = 0;

      for (var i = 0; i < valid.length; i++) {
        final row = valid[i];
        final d = row.draft!;
        final has = row.provided.contains;

        if (row.existingId == null) {
          final id = await dao.insertProduct(
            ProductsCompanion.insert(
              code: d.code,
              name: d.name,
              barcode: Value(d.barcode),
              unitId: Value(await unitId(d.unitName)),
              purchasePrice: Value(d.purchasePrice),
              sellingPrice: Value(d.sellingPrice),
              minStock: Value(d.minStock),
              isActive: Value(d.isActive),
              updatedAt: Value(now),
            ),
          );
          if (d.tagNames case final names? when names.isNotEmpty) {
            await _db.tagsDao.setProductTags(id, await categoryIds(names));
          }
          if (row.stock != 0 && stockStoreId != null) {
            await storesDao.changeStock(
              storeId: stockStoreId,
              productId: id,
              delta: row.stock,
              type: StockMovementType.import,
              userId: actor.id,
              note: 'Import (stok awal)',
            );
          }
          inserted++;
        } else if (existingAction == ExistingProductAction.skip) {
          skipped++;
        } else {
          final id = row.existingId!;
          final overwrite = existingAction == ExistingProductAction.overwrite;
          // Hanya kolom yang terisi di file yang mengganti data lama.
          await dao.updateProduct(
            id,
            ProductsCompanion(
              name: overwrite ? Value(d.name) : const Value.absent(),
              barcode: overwrite && has(ProductField.barcode)
                  ? Value(d.barcode)
                  : const Value.absent(),
              unitId: overwrite && has(ProductField.unit)
                  ? Value(await unitId(d.unitName))
                  : const Value.absent(),
              minStock: overwrite && has(ProductField.minStock)
                  ? Value(d.minStock)
                  : const Value.absent(),
              isActive: overwrite && has(ProductField.isActive)
                  ? Value(d.isActive)
                  : const Value.absent(),
              purchasePrice: has(ProductField.purchasePrice)
                  ? Value(d.purchasePrice)
                  : const Value.absent(),
              sellingPrice: Value(d.sellingPrice),
              updatedAt: Value(now),
            ),
          );
          if (overwrite && d.tagNames != null) {
            await _db.tagsDao.setProductTags(
              id,
              await categoryIds(d.tagNames!),
            );
          }
          if (has(ProductField.stock) && stockStoreId != null) {
            final entry = await storesDao.entry(stockStoreId, id);
            final change = row.stock - (entry?.stock ?? 0);
            if (change != 0) {
              await storesDao.changeStock(
                storeId: stockStoreId,
                productId: id,
                delta: change,
                type: StockMovementType.import,
                userId: actor.id,
                note: 'Import (update stok)',
              );
            }
          }
          updated++;
        }

        if (i % 100 == 99 || i == valid.length - 1) {
          onProgress?.call(i + 1, valid.length);
          // Beri kesempatan UI menggambar progress bar.
          await Future<void>.delayed(Duration.zero);
        }
      }

      await _db.auditDao.append(
        type: AuditType.productsImported,
        summary:
            'Import barang: $inserted baru, $updated diperbarui, '
            '$skipped dilewati',
        userId: actor.id,
        userName: actor.fullName,
        storeId: stockStoreId,
        data: {
          'inserted': inserted,
          'updated': updated,
          'skipped': skipped,
          'failed': failed.length,
        },
        at: now,
      );

      return ImportResult(
        inserted: inserted,
        updated: updated,
        skipped: skipped,
        failed: failed,
        newCategories: newCategories,
        newUnits: newUnits,
      );
    });
  }
}

final productImportServiceProvider = Provider<ProductImportService>(
  (ref) => ProductImportService(ref.watch(appDatabaseProvider)),
);

/// Dipakai export: barang sesuai filter halaman Produk, atau semua.
Future<List<Product>> productsForExport(
  ProductRepository repo,
  ProductFilter? filter,
) => repo.allMatching(
  filter ?? const ProductFilter(status: ProductStatusFilter.all),
);
