import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/audit.dart';
import '../../auth/domain/app_user.dart';
import '../domain/voucher.dart';
import '../../sync/data/terminal_repository.dart';

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
  storeId: r.storeId,
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
    this.storeId,
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

  /// `null` = semua toko.
  final int? storeId;
  final bool isActive;
}

/// Kelola voucher promo (admin) dan pencarian kode untuk kasir. Aturan:
/// kode unik, voucher yang sudah dipakai faktur tidak bisa dihapus atau
/// diganti kodenya (cukup dinonaktifkan).
class VoucherRepository {
  VoucherRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  Stream<List<Voucher>> watchAll() =>
      _db.vouchersDao.watchAll().map((r) => r.map(voucherFromRow).toList());

  /// Dipakai kasir: cari kode lalu periksa apakah bisa dipakai di toko
  /// [storeId]. Melempar [VoucherFailure] berisi alasannya jika tidak.
  ///
  /// Minimal belanja tidak membuat gagal di sini; kasir tetap bisa memasang
  /// voucher lalu menambah barang sampai memenuhi.
  Future<Voucher> findUsable(String code, {required int storeId}) async {
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
      storeId: storeId,
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
    await _requireMaster();
    final code = VoucherRules.normalizeCode(draft.code);
    _check(VoucherRules.code(code));
    _check(VoucherRules.value(draft.type, draft.value));
    _check(VoucherRules.period(draft.startDate, draft.endDate));
    if (draft.minPurchase < 0) {
      throw const VoucherFailure('Minimal belanja tidak boleh negatif.');
    }
    if ((draft.maxDiscount ?? 0) < 0) {
      throw const VoucherFailure('Maksimal potongan tidak boleh negatif.');
    }

    final dao = _db.vouchersDao;
    return _db.transaction(() async {
      final existing = id == null ? null : await dao.findById(id);
      if (id != null && existing == null) {
        throw const VoucherFailure('Voucher tidak ditemukan.');
      }
      if (draft.storeId != null &&
          await _db.storesDao.findById(draft.storeId!) == null) {
        throw const VoucherFailure('Toko tidak ditemukan.');
      }
      final sameCode = await dao.findByCode(code);
      if (sameCode != null && sameCode.id != id) {
        throw VoucherFailure('Kode "$code" sudah dipakai voucher lain.');
      }
      if (existing != null &&
          existing.code != code &&
          await dao.countSalesUsing(existing.id) > 0) {
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
        storeId: Value(draft.storeId),
        isActive: Value(draft.isActive),
      );

      final savedId = id ?? await dao.insertVoucher(data);
      if (id != null) await dao.updateVoucher(id, data);
      final saved = voucherFromRow((await dao.findById(savedId))!);
      await _log(
        actor,
        existing == null
            ? 'Voucher baru $code: ${saved.summary}'
            : 'Voucher $code diubah: ${saved.summary}'
                  '${existing.isActive != draft.isActive ? (draft.isActive ? ' (diaktifkan)' : ' (dinonaktifkan)') : ''}',
      );
      return saved;
    });
  }

  Future<void> delete({required AppUser actor, required int id}) async {
    _requireAdmin(actor);
    await _requireMaster();
    await _db.transaction(() async {
      final row = await _db.vouchersDao.findById(id);
      if (row == null) return;
      if (await _db.vouchersDao.countSalesUsing(id) > 0) {
        throw const VoucherFailure(
          'Voucher ini sudah pernah dipakai sehingga tidak bisa dihapus. '
          'Nonaktifkan saja.',
        );
      }
      await _db.vouchersDao.deleteVoucher(id);
      await _log(actor, 'Voucher ${row.code} dihapus');
    });
  }

  Future<void> _log(AppUser actor, String summary) => _db.auditDao.append(
    type: AuditType.voucherChanged,
    summary: summary,
    userId: actor.id,
    userName: actor.fullName,
    at: _clock(),
  );

  static DateTime? _dateOnly(DateTime? d) =>
      d == null ? null : DateTime(d.year, d.month, d.day);

  /// Data master hanya diubah di komputer server (lihat sinkron).
  Future<void> _requireMaster() async {
    final message = await TerminalRepository.masterLockMessage(_db);
    if (message != null) throw VoucherFailure(message);
  }

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
