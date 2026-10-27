import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../auth/domain/app_user.dart';
import '../domain/audit_entry.dart';

/// Catatan aktivitas: menulis (dari repository/service dan layar kasir) dan
/// membaca untuk Laporan › Aktivitas. Penulisan berantai & bersegel ada di
/// `AuditDao`.
class AuditRepository {
  AuditRepository(this._db);

  final AppDatabase _db;

  /// [storeId] bawaan = toko [actor] (supervisor/kasir).
  Future<void> record(
    AuditType type,
    String summary, {
    AppUser? actor,
    int? storeId,
    Map<String, Object?>? data,
    DateTime? at,
    String? userName,
  }) => _db.auditDao.append(
    type: type,
    summary: summary,
    userId: actor?.id,
    userName: actor?.fullName ?? userName,
    storeId: storeId ?? actor?.storeId,
    data: data,
    at: at,
  );

  AuditEntry _entry(AuditRow r) => AuditEntry(
    id: r.id,
    at: r.createdAt,
    type: r.type,
    summary: r.summary,
    userId: r.userId,
    userName: r.userName,
    storeId: r.storeId,
    terminalCode: r.terminalCode,
    data: r.data,
  );

  /// Catatan dalam [start, end), terbaru dulu. [storeId]: catatan toko itu +
  /// catatan tanpa toko (mis. perubahan akun oleh admin).
  Future<List<AuditEntry>> between(
    DateTime start,
    DateTime end, {
    int? storeId,
    int limit = 1000,
  }) async {
    final a = _db.auditLog;
    final query = _db.select(a)
      ..where(
        (t) =>
            t.createdAt.isBiggerOrEqualValue(start) &
            t.createdAt.isSmallerThanValue(end) &
            (storeId == null
                ? const Constant(true)
                : t.storeId.isNull() | t.storeId.equals(storeId)),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.id)])
      ..limit(limit);
    final local = (await query.get()).map(_entry).toList();

    // Komputer master: catatan komputer cabang (lewat sinkron).
    final r = _db.remoteAuditLog;
    final remoteQuery = _db.select(r)
      ..where(
        (t) =>
            t.createdAt.isBiggerOrEqualValue(start) &
            t.createdAt.isSmallerThanValue(end) &
            (storeId == null
                ? const Constant(true)
                : t.storeId.isNull() | t.storeId.equals(storeId)),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(limit);
    final types = AuditType.values.asNameMap();
    final remote = [
      for (final row in await remoteQuery.get())
        if (types[row.type] case final type?)
          AuditEntry(
            // Negatif supaya tidak bentrok dengan id catatan lokal.
            id: -row.id,
            at: row.createdAt,
            type: type,
            summary: row.summary,
            userId: row.userId,
            userName: row.userName,
            storeId: row.storeId,
            terminalCode: row.terminalCode,
            data: row.data,
          ),
    ];
    if (remote.isEmpty) return local;
    return ([
      ...local,
      ...remote,
    ]..sort((a, b) => b.at.compareTo(a.at))).take(limit).toList();
  }

  /// Tindakan yang perlu diperhatikan per user dalam [start, end), terbanyak
  /// dulu.
  Future<List<AttentionSummary>> attention(
    DateTime start,
    DateTime end, {
    int? storeId,
  }) async {
    final rows = await between(start, end, storeId: storeId, limit: 100000);
    final byUser = <String, Map<AuditType, int>>{};
    final cleared = <String, int>{};
    final returned = <String, int>{};
    for (final e in rows.where((e) => e.type.needsAttention)) {
      final name = e.userName ?? '(tanpa akun)';
      final counts = byUser.putIfAbsent(name, () => {});
      counts[e.type] = (counts[e.type] ?? 0) + 1;
      final d = e.details;
      if (e.type == AuditType.cartCleared) {
        cleared[name] =
            (cleared[name] ?? 0) + ((d['total'] as num?) ?? 0).toInt();
      }
      if (e.type == AuditType.saleReturn) {
        returned[name] =
            (returned[name] ?? 0) + ((d['refund'] as num?) ?? 0).toInt();
      }
    }
    return [
      for (final MapEntry(key: name, value: counts) in byUser.entries)
        AttentionSummary(
          userName: name,
          counts: counts,
          cartClearedValue: cleared[name] ?? 0,
          returnValue: returned[name] ?? 0,
        ),
    ]..sort((a, b) => b.total.compareTo(a.total));
  }
}

final auditRepositoryProvider = Provider<AuditRepository>(
  (ref) => AuditRepository(ref.watch(appDatabaseProvider)),
);
