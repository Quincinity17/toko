import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/audit.dart';
import '../../auth/domain/app_user.dart';
import '../domain/store.dart';

class StoreFailure implements Exception {
  const StoreFailure(this.message);

  final String message;

  @override
  String toString() => 'StoreFailure: $message';
}

enum StoreRemoval {
  /// Toko belum punya akun/transaksi/riwayat stok, dihapus permanen.
  deleted,

  /// Toko sudah dipakai, hanya dinonaktifkan agar riwayatnya utuh.
  deactivated,
}

/// Kelola toko (khusus admin). Minimal satu toko aktif.
class StoreRepository {
  StoreRepository(this._db);

  final AppDatabase _db;

  static Store fromRow(StoreRow r) =>
      Store(id: r.id, name: r.name, address: r.address, isActive: r.isActive);

  Stream<List<Store>> watchAll() =>
      _db.storesDao.watchAll().map((rows) => rows.map(fromRow).toList());

  Future<Store?> findById(int id) async {
    final row = await _db.storesDao.findById(id);
    return row == null ? null : fromRow(row);
  }

  Future<Store> save({
    required AppUser actor,
    int? id,
    required String name,
    String? address,
    bool isActive = true,
  }) async {
    _requireAdmin(actor);
    final n = name.trim();
    if (n.isEmpty) throw const StoreFailure('Nama toko wajib diisi.');
    if (n.length > 60) {
      throw const StoreFailure('Nama toko maksimal 60 karakter.');
    }
    final addr = address?.trim() ?? '';
    final dao = _db.storesDao;

    return _db.transaction(() async {
      final current = id == null ? null : await dao.findById(id);
      if (id != null && current == null) {
        throw const StoreFailure('Toko tidak ditemukan.');
      }
      final same = await dao.findByName(n);
      if (same != null && same.id != id) {
        throw StoreFailure('Nama toko "$n" sudah dipakai.');
      }
      if (current != null && current.isActive && !isActive) {
        await _ensureAnotherActive();
      }
      final data = StoresCompanion(
        name: Value(n),
        address: Value(addr.isEmpty ? null : addr),
        isActive: Value(isActive),
      );
      final savedId = id ?? await dao.insertStore(data);
      if (id != null) await dao.updateStore(id, data);
      await _log(
        actor,
        current == null
            ? 'Toko baru "$n"'
            : 'Toko "${current.name}" diubah'
                  '${current.isActive != isActive ? (isActive ? ' (diaktifkan)' : ' (dinonaktifkan)') : ''}',
        savedId,
      );
      return fromRow((await dao.findById(savedId))!);
    });
  }

  /// Menghapus toko yang belum dipakai; yang sudah dipakai dinonaktifkan.
  Future<StoreRemoval> remove({required AppUser actor, required int id}) {
    _requireAdmin(actor);
    final dao = _db.storesDao;
    return _db.transaction(() async {
      final current = await dao.findById(id);
      if (current == null) throw const StoreFailure('Toko tidak ditemukan.');
      if (current.isActive) await _ensureAnotherActive();
      final usage = await dao.usage(id);
      if (usage.users + usage.sales + usage.movements > 0) {
        await dao.updateStore(
          id,
          const StoresCompanion(isActive: Value(false)),
        );
        await _log(actor, 'Toko "${current.name}" dinonaktifkan', id);
        return StoreRemoval.deactivated;
      }
      await dao.deleteStore(id);
      await _log(actor, 'Toko "${current.name}" dihapus', id);
      return StoreRemoval.deleted;
    });
  }

  Future<void> _log(AppUser actor, String summary, int storeId) =>
      _db.auditDao.append(
        type: AuditType.storeChanged,
        summary: summary,
        userId: actor.id,
        userName: actor.fullName,
        data: {'storeId': storeId},
      );

  Future<void> _ensureAnotherActive() async {
    if (await _db.storesDao.countActive() <= 1) {
      throw const StoreFailure('Harus ada minimal satu toko aktif.');
    }
  }

  void _requireAdmin(AppUser actor) {
    if (!actor.isAdmin) {
      throw const StoreFailure('Hanya admin yang bisa mengelola toko.');
    }
  }
}

final storeRepositoryProvider = Provider<StoreRepository>(
  (ref) => StoreRepository(ref.watch(appDatabaseProvider)),
);

/// Semua toko (aktif dulu), untuk halaman Kelola Toko dan pemilih toko.
final storesProvider = StreamProvider<List<Store>>(
  (ref) => ref.watch(storeRepositoryProvider).watchAll(),
);
