import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../auth/domain/app_user.dart';
import '../domain/voucher.dart';

class VoucherFailure implements Exception {
  const VoucherFailure(this.message);

  final String message;

  @override
  String toString() => 'VoucherFailure: $message';
}

Voucher voucherFromRow(VoucherRow r) => Voucher(
  id: r.id,
  code: r.code,
  name: r.name,
  type: r.type,
  value: r.value,
  maxDiscount: r.maxDiscount,
  minPurchase: r.minPurchase,
  startDate: r.startDate,
  endDate: r.endDate,
  quota: r.quota,
  usedCount: r.usedCount,
  isActive: r.isActive,
);

/// Isian form voucher (tambah/ubah).
class VoucherDraft {
  const VoucherDraft({
    required this.code,
    this.name = '',
    required this.type,
    required this.value,
    this.maxDiscount,
    this.minPurchase = 0,
    this.startDate,
    this.endDate,
    this.quota,
    this.isActive = true,
  });

  final String code;
  final String name;
  final VoucherType type;
  final double? value;
  final int? maxDiscount;
  final int minPurchase;
  final DateTime? startDate;
  final DateTime? endDate;
  final int? quota;
  final bool isActive;
}

class VoucherRepository {
  VoucherRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  Stream<List<Voucher>> watchAll() =>
      _db.vouchersDao.watchAll().map((r) => r.map(voucherFromRow).toList());

  /// Dipakai kasir: cari kode lalu periksa apakah bisa dipakai untuk
  /// [subtotal]. Melempar [VoucherFailure] berisi alasannya jika tidak.
  ///
  /// Minimal belanja tidak membuat gagal di sini; kasir tetap bisa memasang
  /// voucher lalu menambah barang sampai memenuhi.
  Future<Voucher> findUsable(String code) async {
    final normalized = VoucherRules.normalizeCode(code);
    if (normalized.isEmpty) throw const VoucherFailure('Isi kode voucher.');
    final row = await _db.vouchersDao.findByCode(normalized);
    if (row == null) {
      throw VoucherFailure('Voucher "$normalized" tidak ditemukan.');
    }
    final voucher = voucherFromRow(row);
    final problem = voucher.problemFor(
      subtotal: voucher.minPurchase,
      now: _clock(),
    );
    if (problem != null) throw VoucherFailure(problem);
    return voucher;
  }

  Future<Voucher> save({
    required AppUser actor,
    int? id,
    required VoucherDraft draft,
  }) async {
    _requireAdmin(actor);
    final existing = id == null ? null : await _db.vouchersDao.findById(id);
    if (id != null && existing == null) {
      throw const VoucherFailure('Voucher tidak ditemukan.');
    }

    final code = VoucherRules.normalizeCode(draft.code);
    _check(VoucherRules.code(code));
    _check(VoucherRules.value(draft.type, draft.value));
    _check(VoucherRules.period(draft.startDate, draft.endDate));
    _check(VoucherRules.quota(draft.quota, existing?.usedCount ?? 0));
    if (draft.minPurchase < 0) {
      throw const VoucherFailure('Minimal belanja tidak boleh negatif.');
    }

    final sameCode = await _db.vouchersDao.findByCode(code);
    if (sameCode != null && sameCode.id != id) {
      throw VoucherFailure('Kode "$code" sudah dipakai voucher lain.');
    }
    if (existing != null && existing.code != code && existing.usedCount > 0) {
      throw const VoucherFailure(
        'Kode voucher yang sudah pernah dipakai tidak bisa diubah.',
      );
    }

    final data = VouchersCompanion(
      code: Value(code),
      name: Value(draft.name.trim()),
      type: Value(draft.type),
      value: Value(draft.value!),
      maxDiscount: Value(
        draft.type == VoucherType.percent ? draft.maxDiscount : null,
      ),
      minPurchase: Value(draft.minPurchase),
      startDate: Value(_dateOnly(draft.startDate)),
      endDate: Value(_dateOnly(draft.endDate)),
      quota: Value(draft.quota),
      isActive: Value(draft.isActive),
    );

    final savedId = id ?? await _db.vouchersDao.insertVoucher(data);
    if (id != null) await _db.vouchersDao.updateVoucher(id, data);
    return voucherFromRow((await _db.vouchersDao.findById(savedId))!);
  }

  Future<void> delete({required AppUser actor, required int id}) async {
    _requireAdmin(actor);
    final row = await _db.vouchersDao.findById(id);
    if (row == null) return;
    if (row.usedCount > 0 || await _db.vouchersDao.countSalesUsing(id) > 0) {
      throw const VoucherFailure(
        'Voucher ini sudah pernah dipakai sehingga tidak bisa dihapus. '
        'Nonaktifkan saja.',
      );
    }
    await _db.vouchersDao.deleteVoucher(id);
  }

  static DateTime? _dateOnly(DateTime? d) =>
      d == null ? null : DateTime(d.year, d.month, d.day);

  void _requireAdmin(AppUser actor) {
    if (!actor.isAdmin) {
      throw const VoucherFailure('Hanya admin yang bisa mengelola voucher.');
    }
  }

  void _check(String? error) {
    if (error != null) throw VoucherFailure(error);
  }
}

final voucherRepositoryProvider = Provider<VoucherRepository>(
  (ref) => VoucherRepository(ref.watch(appDatabaseProvider)),
);
