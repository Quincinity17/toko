import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/sales.dart';
import '../../auth/domain/app_user.dart';
import '../domain/stock_adjustment.dart';

class StockFailure implements Exception {
  const StockFailure(this.message);

  final String message;

  @override
  String toString() => 'StockFailure: $message';
}

/// Penyesuaian stok per toko (halaman Stok). Hanya admin (semua toko) dan
/// supervisor (tokonya sendiri); kasir tidak bisa mengubah stok.
class StockRepository {
  StockRepository(this._db);

  final AppDatabase _db;

  /// Mengubah stok barang [productId] di toko [storeId] dan mencatatnya di
  /// riwayat stok. Mengembalikan stok baru.
  Future<double> adjust({
    required AppUser actor,
    required int storeId,
    required int productId,
    required StockAdjustMode mode,
    required double qty,
    String? note,
  }) async {
    if (!actor.canAdjustStockAt(storeId)) {
      throw const StockFailure(
        'Anda tidak punya izin mengubah stok di toko ini.',
      );
    }
    if (qty < 0 || (qty == 0 && mode != StockAdjustMode.count)) {
      throw const StockFailure('Jumlah harus lebih dari 0.');
    }
    final dao = _db.storesDao;
    return _db.transaction(() async {
      if (await _db.productsDao.findById(productId) == null) {
        throw const StockFailure('Barang tidak ditemukan.');
      }
      final current = (await dao.entry(storeId, productId))?.stock ?? 0;
      final delta = mode.delta(current, qty);
      if (delta == 0) return current;
      final text = note?.trim() ?? '';
      await dao.changeStock(
        storeId: storeId,
        productId: productId,
        delta: delta,
        type: StockMovementType.adjust,
        userId: actor.id,
        note: text.isEmpty ? mode.label : '${mode.label}: $text',
      );
      return current + delta;
    });
  }

  /// 20 riwayat stok terakhir barang [productId] di toko [storeId].
  Stream<List<StockMovement>> watchHistory(int storeId, int productId) => _db
      .storesDao
      .watchMovements(storeId, productId)
      .map(
        (rows) => [
          for (final (m, user) in rows)
            StockMovement(
              date: m.createdAt,
              type: m.type,
              change: m.qtyChange,
              note: m.note,
              userName: user,
            ),
        ],
      );
}

final stockRepositoryProvider = Provider<StockRepository>(
  (ref) => StockRepository(ref.watch(appDatabaseProvider)),
);
