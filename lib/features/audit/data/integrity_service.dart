import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/daos/audit_dao.dart';
import '../../../core/database/daos/role_permissions_dao.dart';
import '../../../core/database/daos/seals_dao.dart';
import '../../auth/domain/permission.dart';
import '../../../core/utils/formatters.dart';
import '../domain/audit_entry.dart';
import '../domain/sale_digest.dart';

enum IntegritySeverity { danger, warning }

@immutable
class IntegrityIssue {
  const IntegrityIssue(this.severity, this.title, [this.detail]);

  final IntegritySeverity severity;
  final String title;
  final String? detail;
}

@immutable
class IntegrityReport {
  const IntegrityReport({
    required this.checkedAt,
    required this.issues,
    required this.auditRows,
    required this.sales,
    required this.sealedRows,
    this.since,
  });

  final DateTime checkedAt;
  final List<IntegrityIssue> issues;
  final int auditRows;
  final int sales;
  final int sealedRows;

  /// Awal pemeriksaan (segel dibuat / data dipulihkan terakhir).
  final DateTime? since;

  bool get ok => issues.isEmpty;
}

/// Pemeriksaan keutuhan data di perangkat ini. Menangkap perubahan yang
/// dilakukan di luar aplikasi (database dibuka dengan program lain):
///
/// 1. Rantai catatan aktivitas (`AuditDao`): baris yang dihapus/diubah
///    memutus rantai HMAC.
/// 2. Faktur & nota retur vs catatannya (sidik jari [saleDigest]): faktur
///    yang dihapus, diubah, atau disisipkan.
/// 3. Nomor faktur terminal ini tanpa lubang.
/// 4. Jam perangkat yang pernah dimundurkan ([AuditType.clockBack]).
/// 5. Segel akun, barang (harga), stok/harga per toko, satuan lain & harga
///    grosir (`SealsDao`).
///
/// Dimulai dari titik jangkar terakhir: segel dibuat (v12/database baru)
/// atau data dipulihkan (backup bisa dari perangkat lain, disegel ulang).
/// Nanti server menjalankan pemeriksaan yang sama atas data kiriman
/// perangkat (Tahap C).
class IntegrityService {
  IntegrityService(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  static const _maxPerKind = 20;

  Future<IntegrityReport> check() async {
    final issues = <IntegrityIssue>[];
    final sealer = _db.sealer;

    // 1. Rantai catatan aktivitas.
    final audit = await (_db.select(
      _db.auditLog,
    )..orderBy([(a) => OrderingTerm.asc(a.id)])).get();
    var start = 0;
    for (var i = audit.length - 1; i >= 0; i--) {
      if (audit[i].type == AuditType.restoreApplied ||
          audit[i].type == AuditType.sealsRebuilt) {
        start = i;
        break;
      }
    }
    final chain = audit.sublist(start);
    for (var i = 0; i < chain.length; i++) {
      final r = chain[i];
      final linked = i == 0 || r.prevHash == chain[i - 1].hash;
      if (!linked || !sealer.verify(r.hash, AuditDao.hashFields(r))) {
        issues.add(
          IntegrityIssue(
            IntegritySeverity.danger,
            linked
                ? 'Catatan aktivitas diubah di luar aplikasi'
                : 'Catatan aktivitas dihapus di luar aplikasi',
            'Sekitar ${Fmt.dateTime(r.createdAt)} (catatan #${r.id}).',
          ),
        );
        break;
      }
    }
    final since = chain.isEmpty ? null : chain.first.createdAt;

    // 2. Faktur vs catatan. Faktur sebelum batas penghapusan riwayat lewat
    // aplikasi (Pengaturan › Riwayat Penjualan) memang sudah tidak ada.
    DateTime? purgedBefore;
    for (final r in chain.where((r) => r.type == AuditType.salesPurged)) {
      final d = AuditEntry(
        id: r.id,
        at: r.createdAt,
        type: r.type,
        summary: r.summary,
        data: r.data,
      ).details;
      if (d['before'] case final int ms) {
        final t = DateTime.fromMillisecondsSinceEpoch(ms);
        if (purgedBefore == null || t.isAfter(purgedBefore)) purgedBefore = t;
      }
    }
    final logged = <String, ({String invoice, String digest, DateTime at})>{};
    for (final r in chain) {
      // Faktur dari komputer lain (sinkron): sidik jari dicatat saat
      // diterima.
      if (r.type == AuditType.syncReceived) {
        final d = AuditEntry(
          id: r.id,
          at: r.createdAt,
          type: r.type,
          summary: r.summary,
          data: r.data,
        ).details;
        for (final s in (d['sales'] as List? ?? const [])) {
          if (s case {'uuid': final String uuid}) {
            logged[uuid] = (
              invoice: '${s['invoice']}',
              digest: '${s['digest']}',
              at: r.createdAt,
            );
          }
        }
        continue;
      }
      if (r.type != AuditType.sale && r.type != AuditType.saleReturn) continue;
      final d = AuditEntry(
        id: r.id,
        at: r.createdAt,
        type: r.type,
        summary: r.summary,
        data: r.data,
      ).details;
      if (d['uuid'] case final String uuid) {
        logged[uuid] = (
          invoice: '${d['invoice']}',
          digest: '${d['digest']}',
          at: r.createdAt,
        );
      }
    }
    final sales = since == null
        ? <SaleRow>[]
        : await (_db.select(_db.sales)..where(
                (s) => s.saleDate.isBiggerOrEqualValue(
                  since.subtract(const Duration(seconds: 1)),
                ),
              ))
              .get();
    final salesByUuid = {for (final s in sales) s.uuid: s};
    var tampered = 0, unlogged = 0;
    for (final s in sales) {
      final entry = logged[s.uuid];
      if (entry == null) {
        if (unlogged++ < _maxPerKind) {
          issues.add(
            IntegrityIssue(
              IntegritySeverity.danger,
              'Faktur ${s.invoiceNo} tidak tercatat',
              'Faktur ini tidak dibuat lewat aplikasi '
                  '(${Fmt.rupiah(s.total)}, ${Fmt.dateTime(s.saleDate)}).',
            ),
          );
        }
        continue;
      }
      final items = await _db.salesDao.itemsOf(s.id);
      final digest = saleDigest(
        uuid: s.uuid ?? '',
        invoiceNo: s.invoiceNo,
        total: s.total,
        items: [
          for (final i in items)
            (
              productId: i.productId,
              qty: i.qty,
              price: i.price,
              subtotal: i.subtotal,
            ),
        ],
      );
      if (digest != entry.digest && tampered++ < _maxPerKind) {
        issues.add(
          IntegrityIssue(
            IntegritySeverity.danger,
            'Faktur ${s.invoiceNo} diubah di luar aplikasi',
            'Isi barang, jumlah, harga, atau totalnya tidak sama dengan '
                'saat transaksi.',
          ),
        );
      }
    }
    var deleted = 0;
    for (final MapEntry(key: uuid, value: e) in logged.entries) {
      if (salesByUuid.containsKey(uuid)) continue;
      if (purgedBefore != null && e.at.isBefore(purgedBefore)) continue;
      if (deleted++ < _maxPerKind) {
        issues.add(
          IntegrityIssue(
            IntegritySeverity.danger,
            'Faktur ${e.invoice} dihapus di luar aplikasi',
            'Tercatat di catatan aktivitas, tetapi tidak ada di database.',
          ),
        );
      }
    }

    // 3. Nomor faktur berurutan (per awalan INV/RET-terminal-tanggal).
    final byPrefix = <String, List<int>>{};
    for (final s in sales) {
      final m = RegExp(r'^(.*-)(\d{4})$').firstMatch(s.invoiceNo);
      if (m == null) continue;
      byPrefix.putIfAbsent(m[1]!, () => []).add(int.parse(m[2]!));
    }
    for (final MapEntry(key: prefix, value: numbers) in byPrefix.entries) {
      // Hari sebelum batas penghapusan riwayat: sebagian faktur sengaja
      // dihapus (yang punya retur setelah batas tetap disimpan).
      final day = RegExp(r'-(\d{4})(\d{2})(\d{2})-$').firstMatch(prefix);
      if (purgedBefore != null &&
          day != null &&
          DateTime(
            int.parse(day[1]!),
            int.parse(day[2]!),
            int.parse(day[3]!),
          ).isBefore(purgedBefore)) {
        continue;
      }
      numbers.sort();
      final missing = [
        for (var n = numbers.first; n <= numbers.last; n++)
          if (!numbers.contains(n)) '$prefix${n.toString().padLeft(4, '0')}',
      ];
      if (missing.isNotEmpty) {
        issues.add(
          IntegrityIssue(
            IntegritySeverity.danger,
            'Nomor faktur hilang: ${missing.take(5).join(', ')}'
                '${missing.length > 5 ? ' (+${missing.length - 5})' : ''}',
            'Faktur dengan nomor ini pernah dibuat lalu dihapus.',
          ),
        );
      }
    }

    // 4. Jam mundur.
    for (final r in chain.where((r) => r.type == AuditType.clockBack)) {
      issues.add(
        IntegrityIssue(
          IntegritySeverity.warning,
          'Jam perangkat dimundurkan',
          '${r.summary}${r.userName == null ? '' : ' · ${r.userName}'}',
        ),
      );
    }

    // 5. Segel akun, barang, stok/harga per toko.
    final users = await _db.select(_db.users).get();
    var badUsers = 0;
    for (final u in users) {
      if (!sealer.verify(u.seal, SealsDao.userFields(u)) &&
          badUsers++ < _maxPerKind) {
        issues.add(
          IntegrityIssue(
            IntegritySeverity.danger,
            'Akun ${u.username} diubah di luar aplikasi',
            'Peran, toko, status, atau password-nya diubah tanpa lewat '
                'Kelola Akun. Akun ini tidak bisa login sampai diperbaiki '
                'admin (Kelola Akun › simpan ulang / reset password).',
          ),
        );
      }
    }
    final products = await _db.select(_db.products).get();
    final codes = {for (final p in products) p.id: p.code};
    var badProducts = 0;
    for (final p in products) {
      if (!sealer.verify(p.seal, SealsDao.productFields(p)) &&
          badProducts++ < _maxPerKind) {
        issues.add(
          IntegrityIssue(
            IntegritySeverity.danger,
            'Barang ${p.code} diubah di luar aplikasi',
            'Kode, harga beli, harga jual, atau status aktifnya diubah '
                'tanpa lewat Produk.',
          ),
        );
      }
    }
    final storeProducts = await _db.select(_db.storeProducts).get();
    var badStock = 0;
    for (final r in storeProducts) {
      if (!sealer.verify(r.seal, SealsDao.storeProductFields(r)) &&
          badStock++ < _maxPerKind) {
        issues.add(
          IntegrityIssue(
            IntegritySeverity.danger,
            'Stok/harga ${codes[r.productId] ?? '#${r.productId}'} di toko '
                '#${r.storeId} diubah di luar aplikasi',
            'Stok atau harga toko diubah tanpa lewat aplikasi.',
          ),
        );
      }
    }

    final units = await _db.select(_db.productUnits).get();
    final tiers = await _db.select(_db.priceTiers).get();
    final storeUnitPrices = await _db.select(_db.storeUnitPrices).get();
    final unitProduct = {for (final u in units) u.id: u.productId};
    var badPricing = 0;
    for (final (code, ok) in [
      for (final r in units)
        (
          codes[r.productId],
          sealer.verify(r.seal, SealsDao.productUnitFields(r)),
        ),
      for (final r in tiers)
        (
          codes[r.productId],
          sealer.verify(r.seal, SealsDao.priceTierFields(r)),
        ),
      for (final r in storeUnitPrices)
        (
          codes[unitProduct[r.productUnitId]],
          sealer.verify(r.seal, SealsDao.storeUnitPriceFields(r)),
        ),
    ]) {
      if (!ok && badPricing++ < _maxPerKind) {
        issues.add(
          IntegrityIssue(
            IntegritySeverity.danger,
            'Satuan/harga grosir ${code ?? 'barang'} diubah di luar aplikasi',
            'Isi satuan, harga satuan lain, atau harga grosir diubah tanpa '
                'lewat Produk.',
          ),
        );
      }
    }

    // 6. Catatan aktivitas komputer cabang (komputer master): setiap
    // catatan harus menyambung ke catatan sebelumnya dari komputer yang
    // sama. Catatan yang dihapus di cabang memutus rantai.
    final remote =
        await (_db.select(_db.remoteAuditLog)..orderBy([
              (t) => OrderingTerm.asc(t.origin),
              (t) => OrderingTerm.asc(t.remoteId),
            ]))
            .get();
    var breaks = 0;
    for (var i = 1; i < remote.length; i++) {
      final prev = remote[i - 1];
      final r = remote[i];
      if (r.origin != prev.origin) continue;
      if (r.prevHash != prev.hash && breaks++ < _maxPerKind) {
        issues.add(
          IntegrityIssue(
            IntegritySeverity.danger,
            'Catatan aktivitas komputer ${r.terminalCode ?? '?'} terputus',
            'Ada catatan yang hilang/diubah di komputer itu sebelum '
                '${Fmt.dateTime(r.createdAt)} (sebelum: '
                '"${prev.summary}"). Periksa komputer tersebut.',
          ),
        );
      }
    }

    final permissions = await _db.rolePermissionsDao.all();
    var badPermissions = 0;
    for (final r in permissions) {
      if (!sealer.verify(r.seal, RolePermissionsDao.fields(r)) &&
          badPermissions++ < _maxPerKind) {
        issues.add(
          IntegrityIssue(
            IntegritySeverity.danger,
            'Hak akses ${r.role.label} diubah di luar aplikasi',
            'Hak "${Permission.byName(r.permission)?.label ?? r.permission}" '
                'ditambahkan tanpa lewat Hak Akses Peran, jadi diabaikan '
                'aplikasi. Atur ulang di Pengaturan › Hak Akses Peran.',
          ),
        );
      }
    }

    return IntegrityReport(
      checkedAt: _clock(),
      issues: issues,
      auditRows: chain.length,
      sales: sales.length,
      sealedRows:
          users.length +
          products.length +
          storeProducts.length +
          units.length +
          tiers.length +
          storeUnitPrices.length +
          permissions.length,
      since: since,
    );
  }
}

final integrityServiceProvider = Provider<IntegrityService>(
  (ref) => IntegrityService(ref.watch(appDatabaseProvider)),
);
