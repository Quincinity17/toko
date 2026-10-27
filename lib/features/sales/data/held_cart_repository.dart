import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/domain/permission.dart';
import '../domain/cart.dart';
import '../domain/held_cart.dart';

class HeldCartFailure implements Exception {
  const HeldCartFailure(this.message);

  final String message;

  @override
  String toString() => 'HeldCartFailure: $message';
}

/// Menahan keranjang kasir dan melanjutkannya lagi, per toko. Data hanya
/// berlaku hari itu: yang dari hari sebelumnya tidak ditampilkan dan dihapus
/// [purgeExpired].
class HeldCartRepository {
  HeldCartRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  DateTime get _startOfToday {
    final now = _clock();
    return DateTime(now.year, now.month, now.day);
  }

  Stream<List<HeldCart>> watchToday({required int storeId}) => _db.heldCartsDao
      .watchSince(_startOfToday, storeId: storeId)
      .map(
        (rows) => [
          for (final (r, cashier) in rows)
            HeldCart(
              id: r.id,
              note: r.note,
              cashierName: cashier,
              items: HeldItem.decodeList(r.items),
              total: r.total,
              createdAt: r.createdAt,
            ),
        ],
      );

  Future<void> hold({
    required Cart cart,
    required AppUser cashier,
    required int storeId,
    String? note,
  }) async {
    if (cart.isEmpty) {
      throw const HeldCartFailure('Keranjang kosong, tidak ada yang ditahan.');
    }
    final trimmed = note?.trim() ?? '';
    await _db.heldCartsDao.insertCart(
      HeldCartsCompanion.insert(
        userId: cashier.id,
        storeId: Value(storeId),
        note: Value(trimmed.isEmpty ? null : trimmed),
        items: HeldItem.encodeCart(cart),
        itemCount: cart.lines.length,
        // Voucher tidak ikut ditahan (dipasang lagi saat dilanjutkan).
        total: cart.subtotal,
        createdAt: _clock(),
      ),
    );
  }

  /// Mengambil kembali transaksi [id] sebagai keranjang (harga terbaru toko
  /// itu) lalu menghapusnya dari daftar tertahan. Barang yang sudah tidak aktif
  /// dilewati dan dilaporkan di [ResumedCart.skipped].
  Future<ResumedCart> resume(int id) => _db.transaction(() async {
    final row = await _db.heldCartsDao.byId(id);
    if (row == null) {
      throw const HeldCartFailure(
        'Transaksi ini sudah tidak ada (mungkin sudah dilanjutkan).',
      );
    }
    final items = HeldItem.decodeList(row.items);
    final products = {
      for (final p in await _db.productsDao.byIds([
        for (final i in items) i.productId,
      ], storeId: row.storeId))
        p.id: p,
    };
    var cart = const Cart();
    final skipped = <String>[];
    for (final item in items) {
      final product = products[item.productId];
      // Satuan lain yang sudah dihapus admin: barang dilewati juga.
      final unit = product?.unitById(item.unitId);
      if (product == null ||
          !product.isActive ||
          (item.unitId != null && unit == null)) {
        skipped.add(
          item.unitName == null ? item.name : '${item.name} (${item.unitName})',
        );
      } else {
        cart = cart.add(product, qty: item.qty, unit: unit);
      }
    }
    await _db.heldCartsDao.deleteById(id);
    return ResumedCart(cart: cart, skipped: skipped);
  });

  /// Membuang transaksi tertahan (butuh hak "Hapus transaksi tertahan").
  Future<void> delete(int id, {required AppUser actor}) async {
    if (!actor.can(Permission.deleteHeldCart)) {
      throw const HeldCartFailure(
        'Anda tidak punya hak menghapus transaksi tertahan.',
      );
    }
    await _db.heldCartsDao.deleteById(id);
  }

  /// Menghapus transaksi tertahan dari hari-hari sebelumnya.
  Future<int> purgeExpired() => _db.heldCartsDao.deleteBefore(_startOfToday);
}

final heldCartRepositoryProvider = Provider<HeldCartRepository>(
  (ref) => HeldCartRepository(ref.watch(appDatabaseProvider)),
);

/// Transaksi tertahan hari ini di toko [storeId].
final heldCartsProvider = StreamProvider.autoDispose
    .family<List<HeldCart>, int>(
      (ref, storeId) =>
          ref.watch(heldCartRepositoryProvider).watchToday(storeId: storeId),
    );
