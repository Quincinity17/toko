import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/app_database.dart';
import '../../../core/database/database_bootstrap.dart';
import '../../../core/database/tables/audit.dart';
import '../../../core/utils/formatters.dart';
import '../../auth/domain/app_user.dart';
import '../../sync/data/terminal_repository.dart';
import '../domain/history_retention.dart';
import 'backup_service.dart';

class HistoryCleanupFailure implements Exception {
  const HistoryCleanupFailure(this.message);

  final String message;

  @override
  String toString() => 'HistoryCleanupFailure: $message';
}

/// Ringkasan riwayat penjualan yang tersimpan (Pengaturan › Riwayat
/// Penjualan).
@immutable
class HistoryStatus {
  const HistoryStatus({
    required this.keepMonths,
    required this.sales,
    required this.oldest,
    required this.databaseBytes,
    this.lastRun,
    this.lastDeleted = 0,
    this.lastError,
  });

  final int keepMonths;

  /// Jumlah faktur penjualan (tanpa nota retur).
  final int sales;
  final DateTime? oldest;
  final int databaseBytes;
  final DateTime? lastRun;
  final int lastDeleted;
  final String? lastError;
}

/// Hasil satu kali penghapusan.
@immutable
class CleanupResult {
  const CleanupResult({
    required this.cutoff,
    required this.sales,
    required this.returns,
    this.safetyCopy,
  });

  final DateTime cutoff;

  /// Faktur penjualan & nota retur yang dihapus.
  final int sales;
  final int returns;

  /// Salinan data sebelum dihapus (`null` = tidak ada yang dihapus).
  final String? safetyCopy;
}

/// Menghapus riwayat penjualan lama (permintaan user, supaya database tidak
/// terus membesar). Bawaan: tidak pernah.
///
/// - Yang dihapus: faktur sebelum batas tanggal beserta barangnya, nota
///   returnya, riwayat stok penjualan/retur, dan antriannya di `sync_outbox`.
///   **Stok tidak berubah** (stok disimpan di `store_products`).
/// - Faktur yang punya nota retur setelah batas tidak dihapus (supaya nota
///   retur tetap menunjuk fakturnya).
/// - Komputer kasir cabang (Tahap C): hanya faktur yang sudah terkirim ke
///   server.
/// - Catatan aktivitas TIDAK dihapus (rantai keamanan); pemeriksaan keutuhan
///   mengenali penghapusan lewat catatan [AuditType.salesPurged].
/// - Sebelum menghapus, salinan lengkap disimpan di folder backup
///   (`toko-sebelum-hapus-*.sqlite`, tidak ikut dipangkas). Gagal menyalin =
///   tidak ada yang dihapus.
class HistoryCleanupService {
  HistoryCleanupService(this._db, this._backup, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final BackupService _backup;
  final DateTime Function() _clock;

  static const kKeepMonths = 'history.keep_months';
  static const kLastRun = 'history.last_run';
  static const kLastDeleted = 'history.last_deleted';
  static const kLastError = 'history.last_error';
  static const safetyPrefix = 'toko-sebelum-hapus-';

  Future<int> keepMonths() async => HistoryRetention.clamp(
    int.tryParse(await _db.settingsDao.get(kKeepMonths) ?? '') ??
        HistoryRetention.never,
  );

  Future<HistoryStatus> status() async {
    final row = await _db
        .customSelect(
          'SELECT COUNT(*) AS n, MIN(sale_date) AS oldest FROM sales '
          'WHERE return_of_id IS NULL',
          readsFrom: {_db.sales},
        )
        .getSingle();
    final size = await _db
        .customSelect(
          'SELECT page_count * page_size AS s '
          'FROM pragma_page_count(), pragma_page_size()',
        )
        .getSingle();
    final oldest = row.data['oldest'];
    final err = await _db.settingsDao.get(kLastError);
    return HistoryStatus(
      keepMonths: await keepMonths(),
      sales: row.read<int>('n'),
      oldest: oldest is int
          ? DateTime.fromMillisecondsSinceEpoch(oldest * 1000)
          : null,
      databaseBytes: size.read<int>('s'),
      lastRun: DateTime.tryParse(await _db.settingsDao.get(kLastRun) ?? ''),
      lastDeleted:
          int.tryParse(await _db.settingsDao.get(kLastDeleted) ?? '') ?? 0,
      lastError: err == null || err.isEmpty ? null : err,
    );
  }

  Future<void> setKeepMonths(AppUser actor, int months) async {
    _requireAdmin(actor);
    final value = HistoryRetention.clamp(months);
    await _db.settingsDao.set(kKeepMonths, '$value');
    await _db.auditDao.append(
      type: AuditType.backupChanged,
      summary:
          'Hapus riwayat penjualan otomatis: '
          '${HistoryRetention.label(value).toLowerCase()}',
      userId: actor.id,
      userName: actor.fullName,
      at: _clock(),
    );
  }

  /// Jumlah faktur penjualan yang akan dihapus untuk batas [months].
  Future<int> preview(int months) async {
    if (months == HistoryRetention.never) return 0;
    final cutoff = HistoryRetention.cutoff(_clock(), months);
    final row = await _db
        .customSelect(
          'SELECT COUNT(*) AS n FROM sales s WHERE ${await _originalsWhere()}',
          variables: [Variable<DateTime>(cutoff)],
          readsFrom: {_db.sales, _db.syncOutbox},
        )
        .getSingle();
    return row.read<int>('n');
  }

  /// Otomatis (sekali sehari, dari `BackupScheduler`): hanya bila diatur.
  /// Gagal dicatat (tampil di Pengaturan), tidak dilempar.
  Future<CleanupResult?> runIfDue() async {
    final months = await keepMonths();
    if (months == HistoryRetention.never) return null;
    final last = DateTime.tryParse(await _db.settingsDao.get(kLastRun) ?? '');
    if (!HistoryRetention.isDue(last, _clock())) return null;
    try {
      return await _run(months, actor: null);
    } on HistoryCleanupFailure {
      return null;
    }
  }

  /// "Hapus Sekarang" (admin) dengan batas yang sedang diatur.
  Future<CleanupResult> runNow(AppUser actor) async {
    _requireAdmin(actor);
    final months = await keepMonths();
    if (months == HistoryRetention.never) {
      throw const HistoryCleanupFailure(
        'Pilih dulu batas lama riwayat yang disimpan.',
      );
    }
    return _run(months, actor: actor);
  }

  /// Syarat faktur penjualan (alias `s`, batas = variabel ?1) yang boleh
  /// dihapus.
  Future<String> _originalsWhere() async {
    // Cabang, atau master yang sudah tersambung: faktur yang belum terkirim
    // ke server tidak dihapus.
    final client =
        !(await TerminalRepository(_db).current()).isServer ||
        (await _db.settingsDao.get('sync.token') ?? '').isNotEmpty;
    return '''
      s.return_of_id IS NULL AND s.sale_date < ?1
      AND NOT EXISTS (SELECT 1 FROM sales r
                      WHERE r.return_of_id = s.id AND r.sale_date >= ?1)
      ${client ? '''
      AND NOT EXISTS (SELECT 1 FROM sales x
                      JOIN sync_outbox o ON o.entity_uuid = x.uuid
                      WHERE (x.id = s.id OR x.return_of_id = s.id)
                        AND o.sent_at IS NULL)''' : ''}
    ''';
  }

  Future<CleanupResult> _run(int months, {required AppUser? actor}) async {
    final now = _clock();
    final cutoff = HistoryRetention.cutoff(now, months);
    final where = await _originalsWhere();

    final count = await preview(months);
    if (count == 0) {
      await _done(now, 0);
      return CleanupResult(cutoff: cutoff, sales: 0, returns: 0);
    }

    // 1. Jaring pengaman: salinan lengkap sebelum menghapus.
    final String safety;
    try {
      final dir = await _backup.folder();
      await dir.create(recursive: true);
      safety = p.join(
        dir.path,
        '$safetyPrefix${DateFormat('yyyyMMdd-HHmmss').format(now)}.sqlite',
      );
      await copyDatabasePlain(_db, safety);
    } on Exception catch (e) {
      final message =
          'Riwayat tidak dihapus: salinan pengaman ke folder backup gagal '
          '(flashdisk terpasang?). ($e)';
      await _db.settingsDao.set(kLastError, message);
      throw HistoryCleanupFailure(message);
    }

    // 2. Hapus dalam satu transaksi.
    late int sales, returns;
    await _db.transaction(() async {
      await _db.customStatement('DROP TABLE IF EXISTS temp.purge_sales');
      await _db.customStatement(
        'CREATE TEMP TABLE purge_sales (id INTEGER PRIMARY KEY)',
      );
      await _db.customStatement(
        'INSERT INTO temp.purge_sales SELECT s.id FROM sales s WHERE $where',
        [cutoff.millisecondsSinceEpoch ~/ 1000],
      );
      sales = await _countTemp();
      await _db.customStatement(
        'INSERT INTO temp.purge_sales SELECT id FROM sales '
        'WHERE return_of_id IN (SELECT id FROM temp.purge_sales)',
      );
      returns = await _countTemp() - sales;

      await _db.customStatement(
        "DELETE FROM stock_movements WHERE type IN ('sale', 'saleReturn') "
        'AND ref_id IN (SELECT id FROM temp.purge_sales)',
      );
      await _db.customStatement(
        "DELETE FROM sync_outbox WHERE entity = 'sale' AND entity_uuid IN "
        '(SELECT uuid FROM sales WHERE id IN '
        '(SELECT id FROM temp.purge_sales))',
      );
      await _db.customStatement(
        'DELETE FROM sale_items WHERE sale_id IN '
        '(SELECT id FROM temp.purge_sales)',
      );
      await _db.customStatement(
        'DELETE FROM sale_payments WHERE sale_id IN '
        '(SELECT id FROM temp.purge_sales)',
      );
      // Nota retur dulu (menunjuk faktur asalnya).
      await _db.customStatement(
        'DELETE FROM sales WHERE return_of_id IS NOT NULL '
        'AND id IN (SELECT id FROM temp.purge_sales)',
      );
      await _db.customStatement(
        'DELETE FROM sales WHERE id IN (SELECT id FROM temp.purge_sales)',
      );
      await _db.customStatement('DROP TABLE temp.purge_sales');

      await _db.auditDao.append(
        type: AuditType.salesPurged,
        summary:
            'Riwayat penjualan sebelum ${Fmt.dateShort(cutoff)} dihapus: '
            '$sales faktur, $returns nota retur'
            '${actor == null ? ' (otomatis)' : ''}',
        userId: actor?.id,
        userName: actor?.fullName,
        data: {
          'before': cutoff.millisecondsSinceEpoch,
          'sales': sales,
          'returns': returns,
          'copy': p.basename(safety),
        },
        at: now,
      );
    });

    // 3. Kecilkan file database (ruang bekas data yang dihapus).
    try {
      await _db.customStatement('VACUUM');
    } on Exception {
      // Tidak wajib; ruang akan dipakai ulang untuk data baru.
    }
    await _done(now, sales);
    return CleanupResult(
      cutoff: cutoff,
      sales: sales,
      returns: returns,
      safetyCopy: safety,
    );
  }

  Future<int> _countTemp() async =>
      (await _db
              .customSelect('SELECT COUNT(*) AS n FROM temp.purge_sales')
              .getSingle())
          .read<int>('n');

  Future<void> _done(DateTime now, int deleted) async {
    await _db.settingsDao.set(kLastRun, now.toIso8601String());
    await _db.settingsDao.set(kLastDeleted, '$deleted');
    await _db.settingsDao.set(kLastError, '');
  }

  void _requireAdmin(AppUser actor) {
    if (!actor.isAdmin) {
      throw const HistoryCleanupFailure(
        'Hanya admin yang bisa mengatur penghapusan riwayat.',
      );
    }
  }
}

final historyCleanupServiceProvider = Provider<HistoryCleanupService>(
  (ref) => HistoryCleanupService(
    ref.watch(appDatabaseProvider),
    ref.watch(backupServiceProvider),
  ),
);
