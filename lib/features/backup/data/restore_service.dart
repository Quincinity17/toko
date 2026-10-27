import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_bootstrap.dart';
import '../../../core/database/tables/audit.dart';
import '../../../core/security/sealer.dart';
import '../../auth/domain/app_user.dart';
import 'backup_service.dart';

class RestoreFailure implements Exception {
  const RestoreFailure(this.message);

  final String message;

  @override
  String toString() => 'RestoreFailure: $message';
}

/// Hasil memeriksa segel di dalam file backup.
enum BackupSeals {
  /// Backup dari perangkat ini dan isinya utuh.
  intact,

  /// Backup dari perangkat ini, tetapi isinya diubah di luar aplikasi.
  tampered,

  /// Tidak bisa diperiksa: backup dari perangkat lain atau versi lama.
  unverifiable,
}

/// Ringkasan isi file backup database, ditampilkan sebelum memulihkan.
@immutable
class BackupInfo {
  const BackupInfo({
    required this.path,
    required this.schemaVersion,
    required this.products,
    required this.sales,
    this.lastSale,
    this.seals = BackupSeals.unverifiable,
  });

  final String path;
  final int schemaVersion;
  final int products;
  final int sales;
  final DateTime? lastSale;
  final BackupSeals seals;

  String get fileName => p.basename(path);
}

/// Memulihkan database dari file backup (`toko-database-*.sqlite`).
///
/// Database yang sedang dipakai tidak bisa ditukar di tempat, jadi pemulihan
/// dua langkah: [stage] memeriksa file, menyalin data sekarang sebagai jaring
/// pengaman (`toko-sebelum-pulih-*.sqlite` di folder backup), lalu menaruh
/// salinan backup sebagai `toko.sqlite.restore`. [applyPending] (di `main()`,
/// sebelum database dibuka) menukarnya saat aplikasi dibuka berikutnya.
/// Backup dari versi aplikasi lama ikut dimigrasi seperti biasa.
class RestoreService {
  RestoreService(
    this._db,
    this._backup, {
    Future<Directory> Function()? supportDir,
    DateTime Function()? clock,
  }) : _supportDir = supportDir ?? getApplicationSupportDirectory,
       _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final BackupService _backup;
  final Future<Directory> Function() _supportDir;
  final DateTime Function() _clock;

  static const dbFileName = 'toko.sqlite';
  static const pendingFileName = 'toko.sqlite.restore';
  static const _metaFileName = 'toko.sqlite.restore.json';
  static const safetyPrefix = 'toko-sebelum-pulih-';

  /// "waktu ISO|nama file" pemulihan terakhir, ditulis `main()`.
  static const kLastRestore = 'backup.last_restore';

  /// Menukar database dengan backup yang disiapkan [stage]. Dipanggil di
  /// `main()` SEBELUM `AppDatabase` dibuka. Mengembalikan nama file backup
  /// yang dipulihkan, atau `null` bila tidak ada yang menunggu.
  static Future<String?> applyPending({
    Future<Directory> Function()? supportDir,
  }) async {
    final dir = (await (supportDir ?? getApplicationSupportDirectory)()).path;
    final pending = File(p.join(dir, pendingFileName));
    if (!await pending.exists()) return null;
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      final f = File(p.join(dir, '$dbFileName$suffix'));
      if (await f.exists()) await f.delete();
    }
    await pending.rename(p.join(dir, dbFileName));

    final meta = File(p.join(dir, _metaFileName));
    var source = pendingFileName;
    if (await meta.exists()) {
      try {
        final json = jsonDecode(await meta.readAsString()) as Map;
        source = '${json['source'] ?? source}';
      } on FormatException {
        // Nama sumber hanya keterangan.
      }
      await meta.delete();
    }
    return source;
  }

  /// Memeriksa [path]: file database SQLite utuh dari aplikasi ini, versi
  /// skema tidak lebih baru dari aplikasi, dan punya admin aktif (supaya
  /// tetap bisa login setelah dipulihkan).
  static BackupInfo inspect(String path, {Sealer? sealer}) {
    final file = File(path);
    if (!file.existsSync()) throw const RestoreFailure('File tidak ditemukan.');
    final raf = file.openSync();
    final header = raf.readSync(16);
    raf.closeSync();
    if (utf8.decode(header, allowMalformed: true) != 'SQLite format 3\u0000') {
      throw const RestoreFailure(
        'Bukan file backup database (atau salinan langsung database yang '
        'terenkripsi). Pilih file toko-database-….sqlite dari folder backup.',
      );
    }

    final Database db;
    try {
      db = sqlite3.open(path, mode: OpenMode.readOnly);
    } on SqliteException catch (e) {
      throw RestoreFailure('File backup tidak bisa dibuka (${e.message}).');
    }
    try {
      final check = db.select('PRAGMA quick_check').first.values.first;
      if (check != 'ok') {
        throw const RestoreFailure('File backup rusak.');
      }
      final version = db.userVersion;
      final tables = {
        for (final r in db.select(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        ))
          r['name'] as String,
      };
      if (version < 1 || !tables.containsAll(['users', 'products'])) {
        throw const RestoreFailure('File ini bukan database aplikasi Toko.');
      }
      if (version > AppDatabase.currentSchemaVersion) {
        throw const RestoreFailure(
          'Backup ini dibuat aplikasi versi lebih baru. Perbarui aplikasi '
          'dulu sebelum memulihkan.',
        );
      }
      int count(String sql) => db.select(sql).first.values.first as int;
      if (count(
            "SELECT COUNT(*) FROM users WHERE role = 'admin' AND is_active = 1",
          ) ==
          0) {
        throw const RestoreFailure(
          'Backup ini tidak punya akun admin aktif, jadi tidak bisa dipakai '
          'login.',
        );
      }
      final hasSales = tables.contains('sales');
      final last = hasSales
          ? db.select('SELECT MAX(sale_date) AS d FROM sales').first['d']
          : null;
      return BackupInfo(
        path: path,
        seals: sealer == null || !tables.contains('audit_log')
            ? BackupSeals.unverifiable
            : _checkSeals(db, sealer),
        schemaVersion: version,
        products: count('SELECT COUNT(*) FROM products'),
        sales: hasSales ? count('SELECT COUNT(*) FROM sales') : 0,
        lastSale: last is int
            ? DateTime.fromMillisecondsSinceEpoch(last * 1000)
            : null,
      );
    } on SqliteException catch (e) {
      throw RestoreFailure('File backup tidak bisa dibaca (${e.message}).');
    } finally {
      db.close();
    }
  }

  /// Memeriksa rantai catatan aktivitas & segel akun/barang/stok di backup
  /// dengan kunci perangkat ini. Baris jangkar (segel dibuat / pulih) yang
  /// cocok = backup dari perangkat ini; setelah itu ketidakcocokan apa pun =
  /// diubah di luar aplikasi.
  static BackupSeals _checkSeals(Database db, Sealer sealer) {
    DateTime? time(Object? v) =>
        v is int ? DateTime.fromMillisecondsSinceEpoch(v * 1000) : null;
    final audit = db.select('SELECT * FROM audit_log ORDER BY id');
    var start = -1;
    for (var i = audit.length - 1; i >= 0; i--) {
      final t = audit[i]['type'];
      if (t == 'restoreApplied' || t == 'sealsRebuilt') {
        start = i;
        break;
      }
    }
    if (start < 0) return BackupSeals.unverifiable;
    List<Object?> fields(Row r) => [
      r['prev_hash'],
      time(r['created_at']),
      r['user_id'],
      r['user_name'],
      r['store_id'],
      r['terminal_code'],
      r['type'],
      r['summary'],
      r['data'],
    ];
    if (!sealer.verify(audit[start]['hash'] as String?, fields(audit[start]))) {
      return BackupSeals.unverifiable; // kunci lain = perangkat lain
    }
    for (var i = start + 1; i < audit.length; i++) {
      final r = audit[i];
      if (r['prev_hash'] != audit[i - 1]['hash'] ||
          !sealer.verify(r['hash'] as String?, fields(r))) {
        return BackupSeals.tampered;
      }
    }
    bool b(Object? v) => v == 1 || v == true;
    for (final u in db.select('SELECT * FROM users')) {
      final f = [
        u['id'],
        u['username'],
        u['role'],
        u['store_id'],
        b(u['is_active']),
        u['password_hash'],
      ];
      if (!sealer.verify(u['seal'] as String?, f)) return BackupSeals.tampered;
    }
    for (final pr in db.select('SELECT * FROM products')) {
      final f = [
        pr['id'],
        pr['code'],
        pr['purchase_price'],
        pr['selling_price'],
        b(pr['is_active']),
      ];
      if (!sealer.verify(pr['seal'] as String?, f)) return BackupSeals.tampered;
    }
    for (final sp in db.select('SELECT * FROM store_products')) {
      final stock = sp['stock'];
      final f = [
        sp['store_id'],
        sp['product_id'],
        stock is int ? stock.toDouble() : stock,
        sp['selling_price'],
      ];
      if (!sealer.verify(sp['seal'] as String?, f)) return BackupSeals.tampered;
    }
    // Hak akses peran (v14; backup lama belum punya tabelnya).
    final hasPermissions = db
        .select(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' "
          "AND name = 'role_permissions'",
        )
        .isNotEmpty;
    if (hasPermissions) {
      for (final r in db.select('SELECT * FROM role_permissions')) {
        final f = [r['role'], r['permission']];
        if (!sealer.verify(r['seal'] as String?, f)) {
          return BackupSeals.tampered;
        }
      }
    }
    return BackupSeals.intact;
  }

  /// Menyiapkan pemulihan dari [path] (hanya admin). Mengembalikan path
  /// salinan data sekarang (jaring pengaman).
  Future<String> stage(AppUser actor, String path) async {
    if (!actor.isAdmin) {
      throw const RestoreFailure('Hanya admin yang bisa memulihkan backup.');
    }
    inspect(path);

    // 1. Jaring pengaman: data sekarang disalin dulu ke folder backup
    //    (tidak ikut terhapus aturan "simpan N terbaru").
    final folder = await _backup.folder();
    final String safety;
    try {
      await folder.create(recursive: true);
      final stamp = DateFormat('yyyyMMdd-HHmmss').format(_clock());
      safety = p.join(folder.path, '$safetyPrefix$stamp.sqlite');
      await copyDatabasePlain(_db, safety);
    } on Exception catch (e) {
      throw RestoreFailure(
        'Gagal menyalin data sekarang ke ${folder.path}, pemulihan '
        'dibatalkan. ($e)',
      );
    }

    // 2. Salin backup ke samping database (sumber boleh dicabut, mis.
    //    flashdisk); ditukar saat aplikasi dibuka berikutnya.
    final dir = (await _supportDir()).path;
    await File(path).copy(p.join(dir, pendingFileName));
    await File(p.join(dir, _metaFileName))
        .writeAsString(jsonEncode({'source': p.basename(path)}));
    await _db.auditDao.append(
      type: AuditType.restoreStaged,
      summary:
          'Pemulihan dari ${p.basename(path)} disiapkan; data sebelumnya '
          'disalin ke ${p.basename(safety)}',
      userId: actor.id,
      userName: actor.fullName,
    );
    return safety;
  }

  /// Untuk layar "database terkunci" (kunci hilang, aplikasi belum bisa
  /// membuka database): database lama disisihkan sebagai
  /// `toko-terkunci-*.sqlite` lalu [path] disiapkan seperti [stage], tanpa
  /// salinan pengaman (database lama memang tidak bisa dibaca).
  static Future<void> stageForLockedDatabase(
    String path, {
    Future<Directory> Function()? supportDir,
    DateTime Function()? clock,
  }) async {
    inspect(path);
    final dir = (await (supportDir ?? getApplicationSupportDirectory)()).path;
    final current = File(p.join(dir, dbFileName));
    if (await current.exists()) {
      final stamp = DateFormat('yyyyMMdd-HHmmss')
          .format((clock ?? DateTime.now)());
      await current.rename(p.join(dir, 'toko-terkunci-$stamp.sqlite'));
    }
    await File(path).copy(p.join(dir, pendingFileName));
    await File(p.join(dir, _metaFileName))
        .writeAsString(jsonEncode({'source': p.basename(path)}));
  }

  Future<bool> hasPending() async =>
      File(p.join((await _supportDir()).path, pendingFileName)).exists();

  Future<void> cancelPending() async {
    final dir = (await _supportDir()).path;
    for (final name in [pendingFileName, _metaFileName]) {
      final f = File(p.join(dir, name));
      if (await f.exists()) await f.delete();
    }
  }

  /// Pemulihan terakhir (waktu, nama file), atau `null`.
  Future<({DateTime at, String source})?> lastRestore() async {
    final v = await _db.settingsDao.get(kLastRestore);
    if (v == null || !v.contains('|')) return null;
    final i = v.indexOf('|');
    final at = DateTime.tryParse(v.substring(0, i));
    return at == null ? null : (at: at, source: v.substring(i + 1));
  }
}

final restoreServiceProvider = Provider<RestoreService>(
  (ref) => RestoreService(
    ref.watch(appDatabaseProvider),
    ref.watch(backupServiceProvider),
  ),
);

/// Ada pemulihan yang menunggu aplikasi dibuka ulang.
final pendingRestoreProvider = FutureProvider<bool>(
  (ref) => ref.watch(restoreServiceProvider).hasPending(),
);

final lastRestoreProvider = FutureProvider<({DateTime at, String source})?>(
  (ref) => ref.watch(restoreServiceProvider).lastRestore(),
);
