import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/audit.dart';
import '../../auth/domain/app_user.dart';
import '../domain/payment_method.dart';

class PaymentMethodFailure implements Exception {
  const PaymentMethodFailure(this.message);

  final String message;

  @override
  String toString() => 'PaymentMethodFailure: $message';
}

PaymentMethod paymentMethodFromRow(PaymentMethodRow r) => PaymentMethod(
  id: r.id,
  name: r.name,
  kind: r.kind,
  isActive: r.isActive,
  sortOrder: r.sortOrder,
);

/// Kelola metode pembayaran. Aturan: minimal satu metode aktif, dan metode
/// yang sudah dipakai transaksi tidak bisa dihapus (cukup dinonaktifkan).
class PaymentMethodRepository {
  PaymentMethodRepository(this._db);

  final AppDatabase _db;

  Stream<List<PaymentMethod>> watchAll({bool activeOnly = false}) => _db
      .paymentMethodsDao
      .watchAll(activeOnly: activeOnly)
      .map((r) => r.map(paymentMethodFromRow).toList());

  Future<PaymentMethod> save({
    required AppUser actor,
    int? id,
    required String name,
    required PaymentKind kind,
    required bool isActive,
  }) async {
    _requireAdmin(actor);
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const PaymentMethodFailure('Nama metode wajib diisi.');
    }
    if (trimmed.length > 40) {
      throw const PaymentMethodFailure('Nama maksimal 40 karakter.');
    }
    final dao = _db.paymentMethodsDao;

    return _db.transaction(() async {
      final same = await dao.findByName(trimmed);
      if (same != null && same.id != id) {
        throw PaymentMethodFailure('Metode "$trimmed" sudah ada.');
      }

      if (id == null) {
        final newId = await dao.insertMethod(
          PaymentMethodsCompanion.insert(
            name: trimmed,
            kind: kind,
            isActive: Value(isActive),
            sortOrder: Value(await dao.nextSortOrder()),
          ),
        );
        await _log(actor, 'Metode bayar baru "$trimmed"');
        return paymentMethodFromRow((await dao.findById(newId))!);
      }

      final current = await dao.findById(id);
      if (current == null) {
        throw const PaymentMethodFailure('Metode tidak ditemukan.');
      }
      if (current.isActive && !isActive && await dao.countActive() <= 1) {
        throw const PaymentMethodFailure(
          'Harus ada minimal satu metode pembayaran aktif.',
        );
      }
      await dao.updateMethod(
        id,
        PaymentMethodsCompanion(
          name: Value(trimmed),
          kind: Value(kind),
          isActive: Value(isActive),
        ),
      );
      await _log(
        actor,
        'Metode bayar "${current.name}" diubah'
        '${current.isActive != isActive ? (isActive ? ' (diaktifkan)' : ' (dinonaktifkan)') : ''}',
      );
      return paymentMethodFromRow((await dao.findById(id))!);
    });
  }

  Future<void> delete({required AppUser actor, required int id}) async {
    _requireAdmin(actor);
    final dao = _db.paymentMethodsDao;
    await _db.transaction(() async {
      final current = await dao.findById(id);
      if (current == null) return;
      if (await dao.countSalesUsing(id) > 0) {
        throw const PaymentMethodFailure(
          'Metode ini sudah dipakai transaksi sehingga tidak bisa dihapus. '
          'Nonaktifkan saja.',
        );
      }
      if (current.isActive && await dao.countActive() <= 1) {
        throw const PaymentMethodFailure(
          'Harus ada minimal satu metode pembayaran aktif.',
        );
      }
      await dao.deleteMethod(id);
      await _log(actor, 'Metode bayar "${current.name}" dihapus');
    });
  }

  Future<void> _log(AppUser actor, String summary) => _db.auditDao.append(
    type: AuditType.paymentMethodChanged,
    summary: summary,
    userId: actor.id,
    userName: actor.fullName,
  );

  void _requireAdmin(AppUser actor) {
    if (!actor.isAdmin) {
      throw const PaymentMethodFailure(
        'Hanya admin yang bisa mengelola metode pembayaran.',
      );
    }
  }
}

final paymentMethodRepositoryProvider = Provider<PaymentMethodRepository>(
  (ref) => PaymentMethodRepository(ref.watch(appDatabaseProvider)),
);

/// Metode aktif untuk popup pembayaran kasir.
final activePaymentMethodsProvider =
    StreamProvider.autoDispose<List<PaymentMethod>>(
      (ref) =>
          ref.watch(paymentMethodRepositoryProvider).watchAll(activeOnly: true),
    );
