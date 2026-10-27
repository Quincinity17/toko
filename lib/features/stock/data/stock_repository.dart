import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/audit.dart';
import '../../../core/database/tables/sales.dart';
import '../../../core/utils/formatters.dart';
import '../../auth/domain/app_user.dart';
import '../domain/stock_adjustment.dart';
import '../domain/stock_alert.dart';

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
      final product = await _db.productsDao.findById(productId);
      if (product == null) {
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
      await _db.auditDao.append(
        type: AuditType.stockAdjusted,
        summary:
            '${mode.label} ${product.code} · ${product.name}: '
            '${Fmt.number(current)} → ${Fmt.number(current + delta)}'
            '${text.isEmpty ? '' : ' ($text)'}',
        userId: actor.id,
        userName: actor.fullName,
        storeId: storeId,
        data: {
          'productId': productId,
          'mode': mode.name,
          'from': current,
          'to': current + delta,
        },
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

/// Peringatan stok (lihat [StockAlerts]) per toko, atau semua toko aktif.
/// Data [StockAlertSettings.days] hari terakhir; dipantau supaya ikut
/// terbarui setelah penjualan/opname.
class StockAlertRepository {
  StockAlertRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  Stream<StockAlertSettings> watchSettings() => _db.settingsDao
      .watchMany([StockAlertSettings.kSetting])
      .map((v) => StockAlertSettings.fromJson(v[StockAlertSettings.kSetting]));

  Future<StockAlertSettings> settings() async => StockAlertSettings.fromJson(
    await _db.settingsDao.get(StockAlertSettings.kSetting),
  );

  /// Mengatur ambang peringatan (admin).
  Future<void> saveSettings(AppUser actor, StockAlertSettings value) async {
    if (!actor.isAdmin) {
      throw const StockFailure('Hanya admin yang bisa mengatur peringatan.');
    }
    await _db.settingsDao.set(
      StockAlertSettings.kSetting,
      StockAlertSettings.fromJson(value.toJson()).toJson(),
    );
  }

  /// [storeId] `null` = semua toko aktif (peringatan diberi nama toko).
  Stream<List<StockAlert>> watch(
    int? storeId, {
    StockAlertSettings settings = const StockAlertSettings(),
  }) {
    final now = _clock();
    final since = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: settings.days - 1));
    return _db
        .customSelect(
          '''
      SELECT p.id, p.code, p.name, u.name AS unit, p.min_stock,
             st.id AS store_id, st.name AS store_name,
             COALESCE(sp.stock, 0) AS stock,
             COALESCE((SELECT -SUM(m.qty_change) FROM stock_movements m
               WHERE m.product_id = p.id AND m.store_id = st.id
                 AND m.type IN ('sale', 'saleReturn')
                 AND m.created_at >= ?2), 0) AS sold,
             COALESCE((SELECT -SUM(m.qty_change) FROM stock_movements m
               WHERE m.product_id = p.id AND m.store_id = st.id
                 AND m.type = 'adjust' AND m.qty_change < 0
                 AND m.created_at >= ?2), 0) AS adjusted_out
      FROM products p
      JOIN stores st ON (?1 IS NULL AND st.is_active = 1) OR st.id = ?1
      LEFT JOIN units u ON u.id = p.unit_id
      LEFT JOIN store_products sp
        ON sp.product_id = p.id AND sp.store_id = st.id
      WHERE p.is_active = 1
      ''',
          variables: [Variable<int>(storeId), Variable.withDateTime(since)],
          readsFrom: {
            _db.products,
            _db.units,
            _db.stores,
            _db.storeProducts,
            _db.stockMovements,
          },
        )
        .watch()
        .map(
          (rows) => StockAlerts.analyze([
            for (final r in rows)
              StockHealthRow(
                productId: r.read<int>('id'),
                code: r.read<String>('code'),
                name: r.read<String>('name'),
                unit: r.read<String?>('unit'),
                stock: (r.data['stock'] as num).toDouble(),
                minStock: (r.data['min_stock'] as num).toDouble(),
                sold: (r.data['sold'] as num).toDouble(),
                adjustedOut: (r.data['adjusted_out'] as num).toDouble(),
                storeId: r.read<int>('store_id'),
                storeName: storeId == null
                    ? r.read<String>('store_name')
                    : null,
              ),
          ], settings: settings),
        );
  }
}

final stockAlertRepositoryProvider = Provider<StockAlertRepository>(
  (ref) => StockAlertRepository(ref.watch(appDatabaseProvider)),
);

/// Ambang peringatan stok yang berlaku.
final stockAlertSettingsProvider = StreamProvider<StockAlertSettings>(
  (ref) => ref.watch(stockAlertRepositoryProvider).watchSettings(),
);

/// Peringatan stok toko [storeId] (`null` = semua toko aktif).
final stockAlertsProvider = StreamProvider.autoDispose
    .family<List<StockAlert>, int?>((ref, storeId) {
      final settings =
          ref.watch(stockAlertSettingsProvider).value ??
          const StockAlertSettings();
      return ref
          .watch(stockAlertRepositoryProvider)
          .watch(storeId, settings: settings);
    });

final stockRepositoryProvider = Provider<StockRepository>(
  (ref) => StockRepository(ref.watch(appDatabaseProvider)),
);
