import 'dart:convert';

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/audit.dart';
import '../tables/sync.dart';

part 'audit_dao.g.dart';

/// Menulis catatan aktivitas berantai (lihat [AuditLog]). Dipanggil oleh
/// repository/service di dalam transaksinya sendiri, jadi catatan ikut batal
/// bila tindakannya gagal.
@DriftAccessor(tables: [AuditLog, AppSettings])
class AuditDao extends DatabaseAccessor<AppDatabase> with _$AuditDaoMixin {
  AuditDao(super.attachedDatabase);

  /// Jam mundur lebih dari ini dibanding catatan terakhir → dicatat
  /// sebagai [AuditType.clockBack] (mis. jam komputer dimundurkan supaya
  /// faktur tercatat di hari lain).
  static const clockTolerance = Duration(minutes: 2);

  /// Kolom yang masuk ke [AuditRow.hash] (urutan tetap).
  static List<Object?> hashFields(AuditRow r) => [
    r.prevHash,
    r.createdAt,
    r.userId,
    r.userName,
    r.storeId,
    r.terminalCode,
    r.type,
    r.summary,
    r.data,
  ];

  Future<AuditRow?> last() =>
      (select(auditLog)
            ..orderBy([(a) => OrderingTerm.desc(a.id)])
            ..limit(1))
          .getSingleOrNull();

  Future<void> append({
    required AuditType type,
    required String summary,
    int? userId,
    String? userName,
    int? storeId,
    Map<String, Object?>? data,
    DateTime? at,
  }) => transaction(() async {
    final now = at ?? DateTime.now();
    final previous = await last();
    if (previous != null &&
        type != AuditType.clockBack &&
        now.isBefore(previous.createdAt.subtract(clockTolerance))) {
      await append(
        type: AuditType.clockBack,
        summary:
            'Jam perangkat mundur dari ${_fmt(previous.createdAt)} ke '
            '${_fmt(now)}',
        userId: userId,
        userName: userName,
        storeId: storeId,
        data: {'last': previous.createdAt.toIso8601String()},
        at: now,
      );
    }
    final prevHash = (await last())?.hash ?? '';
    final terminal = await (select(
      appSettings,
    )..where((s) => s.key.equals('terminal.code'))).getSingleOrNull();
    // Detik unix: sama dengan yang tersimpan (drift menyimpan detik).
    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      now.millisecondsSinceEpoch ~/ 1000 * 1000,
    );
    final row = AuditRow(
      id: 0,
      createdAt: createdAt,
      userId: userId,
      userName: userName,
      storeId: storeId,
      terminalCode: terminal?.value,
      type: type,
      summary: summary,
      data: data == null ? null : jsonEncode(data),
      prevHash: prevHash,
      hash: '',
    );
    await into(auditLog).insert(
      row
          .copyWith(hash: attachedDatabase.sealer.seal(hashFields(row)))
          .toCompanion(true)
          .copyWith(id: const Value.absent()),
    );
  });

  static String _fmt(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';
}
