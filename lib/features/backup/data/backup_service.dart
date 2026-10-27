import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_bootstrap.dart';
import '../../../core/database/tables/audit.dart';
import '../../auth/domain/app_user.dart';
import '../../products/data/product_file_io.dart';
import '../../products/data/product_repository.dart';
import '../../products/domain/product.dart';
import '../domain/backup_policy.dart';

class BackupFailure implements Exception {
  const BackupFailure(this.message);

  final String message;

  @override
  String toString() => 'BackupFailure: $message';
}

/// Backup komputer ini: salinan database (`VACUUM INTO`) + Excel barang per
/// toko, ke folder bawaan (`Documents/Toko Backup`) atau folder pilihan admin.
/// Otomatis tiap N hari ([runIfDue]); hanya N terbaru per jenis yang
/// disimpan (keduanya diatur admin, bawaan 7 hari & 2 file).
class BackupService {
  BackupService(
    this._db, {
    DateTime Function()? clock,
    Future<Directory> Function()? defaultFolder,
  }) : _clock = clock ?? DateTime.now,
       _defaultFolder = defaultFolder ?? _documentsFolder;

  final AppDatabase _db;
  final DateTime Function() _clock;
  final Future<Directory> Function() _defaultFolder;

  static const kFolder = 'backup.dir';
  static const kLastAt = 'backup.last_at';
  static const kLastError = 'backup.last_error';
  static const kEnabled = 'backup.enabled';
  static const kIntervalDays = 'backup.interval_days';
  static const kKeep = 'backup.keep';
  static const _keys = [
    kFolder,
    kLastAt,
    kLastError,
    kEnabled,
    kIntervalDays,
    kKeep,
  ];

  static int _intervalOf(Map<String, String> s) => BackupPolicy.clampInterval(
    int.tryParse(s[kIntervalDays] ?? '') ?? BackupPolicy.defaultIntervalDays,
  );

  static int _keepOf(Map<String, String> s) => BackupPolicy.clampKeep(
    int.tryParse(s[kKeep] ?? '') ?? BackupPolicy.defaultKeep,
  );

  /// Mencegah dua backup berjalan bersamaan (otomatis + tombol).
  static Future<List<BackupFile>>? _running;

  static Future<Directory> _documentsFolder() async => Directory(
    p.join((await getApplicationDocumentsDirectory()).path, 'Toko Backup'),
  );

  Future<Directory> folder() async {
    final custom = await _db.settingsDao.get(kFolder);
    return custom == null || custom.isEmpty
        ? _defaultFolder()
        : Directory(custom);
  }

  // ── Status ──

  Stream<BackupStatus> watch() =>
      _db.settingsDao.watchMany(_keys).asyncMap(_statusFrom);

  Future<BackupStatus> status() async => _statusFrom(await _settings());

  Future<Map<String, String>> _settings() async {
    final out = <String, String>{};
    for (final k in _keys) {
      final v = await _db.settingsDao.get(k);
      if (v != null) out[k] = v;
    }
    return out;
  }

  Future<BackupStatus> _statusFrom(Map<String, String> s) async {
    final custom = s[kFolder] ?? '';
    final dir = custom.isEmpty ? await _defaultFolder() : Directory(custom);
    final error = s[kLastError] ?? '';
    return BackupStatus(
      enabled: s[kEnabled] != 'false',
      folder: dir.path,
      isCustomFolder: custom.isNotEmpty,
      intervalDays: _intervalOf(s),
      keep: _keepOf(s),
      lastAt: DateTime.tryParse(s[kLastAt] ?? ''),
      lastError: error.isEmpty ? null : error,
      files: await _listFiles(dir),
    );
  }

  Future<List<BackupFile>> _listFiles(Directory dir) async {
    if (!await dir.exists()) return const [];
    final out = <BackupFile>[];
    await for (final e in dir.list()) {
      if (e is! File) continue;
      final name = p.basename(e.path);
      for (final kind in BackupKind.values) {
        if (!kind.matches(name)) continue;
        final stat = await e.stat();
        out.add(
          BackupFile(
            kind: kind,
            name: name,
            path: e.path,
            size: stat.size,
            modified: stat.modified,
          ),
        );
      }
    }
    return out..sort((a, b) => b.name.compareTo(a.name));
  }

  // ── Pengaturan (admin) ──

  Future<void> setEnabled(AppUser actor, bool enabled) async {
    _requireAdmin(actor);
    await _db.settingsDao.set(kEnabled, '$enabled');
    await _log(
      actor,
      enabled ? 'Backup otomatis dinyalakan' : 'Backup otomatis dimatikan',
    );
  }

  Future<void> _log(AppUser actor, String summary) => _db.auditDao.append(
    type: AuditType.backupChanged,
    summary: summary,
    userId: actor.id,
    userName: actor.fullName,
  );

  /// Backup otomatis tiap [days] hari (1–30).
  Future<void> setIntervalDays(AppUser actor, int days) async {
    _requireAdmin(actor);
    final v = BackupPolicy.clampInterval(days);
    await _db.settingsDao.set(kIntervalDays, '$v');
    await _log(actor, 'Backup tiap $v hari');
  }

  /// Simpan [count] backup terbaru per jenis (1–10). File lebih lama dari
  /// itu dihapus pada backup berikutnya.
  Future<void> setKeep(AppUser actor, int count) async {
    _requireAdmin(actor);
    final v = BackupPolicy.clampKeep(count);
    await _db.settingsDao.set(kKeep, '$v');
    await _log(actor, 'Simpan $v backup terbaru');
  }

  /// [path] `null` = kembali ke folder bawaan.
  Future<void> setFolder(AppUser actor, String? path) async {
    _requireAdmin(actor);
    await _db.settingsDao.set(kFolder, path ?? '');
    await _log(actor, 'Folder backup: ${path ?? 'bawaan'}');
  }

  void _requireAdmin(AppUser actor) {
    if (!actor.isAdmin) {
      throw const BackupFailure('Hanya admin yang bisa mengatur backup.');
    }
  }

  // ── Menjalankan ──

  /// Backup otomatis: hanya jika aktif dan sudah lewat jarak hari yang
  /// diatur sejak yang terakhir. Gagal dicatat (tampil di Pengaturan), tidak dilempar.
  Future<bool> runIfDue() async {
    final s = await _settings();
    if (s[kEnabled] == 'false') return false;
    final last = DateTime.tryParse(s[kLastAt] ?? '');
    if (!BackupPolicy.isDue(last, _clock(), intervalDays: _intervalOf(s))) {
      return false;
    }
    try {
      await run();
      return true;
    } on BackupFailure {
      return false;
    }
  }

  /// Membuat backup sekarang. Mengembalikan file yang dibuat.
  Future<List<BackupFile>> run() {
    final running = _running;
    if (running != null) return running;
    final job = _run().whenComplete(() => _running = null);
    _running = job;
    return job;
  }

  Future<List<BackupFile>> _run() async {
    final now = _clock();
    final dir = await folder();
    final keep = _keepOf(await _settings());
    try {
      await dir.create(recursive: true);

      // 1. Database: salinan konsisten walau aplikasi sedang dipakai.
      final dbPath = p.join(
        dir.path,
        BackupPolicy.fileName(BackupKind.database, now),
      );
      // Tidak terenkripsi: bisa dipulihkan di perangkat lain.
      await copyDatabasePlain(_db, dbPath);

      // 2. Barang: satu sheet per toko (stok & harga toko itu).
      final products = ProductRepository(_db);
      final stores = await (_db.select(
        _db.stores,
      )..orderBy([(s) => OrderingTerm.asc(s.id)])).get();
      final sheets = <(String, List<Product>)>[
        for (final s in stores)
          (
            s.name,
            await products.allMatching(
              ProductFilter(status: ProductStatusFilter.all, storeId: s.id),
            ),
          ),
      ];
      // Data besar ditulis di isolate supaya layar tidak tersendat; data
      // kecil langsung saja (memulai isolate lebih lama dari pekerjaannya).
      final rows = sheets.fold<int>(0, (n, s) => n + s.$2.length);
      final bytes = rows < 1000
          ? exportProductsWorkbook(sheets)
          : await Isolate.run(() => exportProductsWorkbook(sheets));
      final xlsxPath = p.join(
        dir.path,
        BackupPolicy.fileName(BackupKind.products, now),
      );
      await File(xlsxPath).writeAsBytes(bytes, flush: true);

      // 3. Simpan [keep] terbaru per jenis; sisanya (yang paling lama)
      //    dihapus.
      final names = [
        await for (final e in dir.list())
          if (e is File) p.basename(e.path),
      ];
      for (final kind in BackupKind.values) {
        for (final old in BackupPolicy.toDelete(names, kind, keep: keep)) {
          await File(p.join(dir.path, old)).delete();
        }
      }

      await _db.settingsDao.set(kLastAt, now.toIso8601String());
      await _db.settingsDao.set(kLastError, '');
      final created = await _listFiles(dir);
      return [
        for (final f in created)
          if (f.path == dbPath || f.path == xlsxPath) f,
      ];
    } on Exception catch (e) {
      final message =
          'Backup ke ${dir.path} gagal. Pastikan folder ada dan bisa ditulis '
          '(flashdisk terpasang). ($e)';
      await _db.settingsDao.set(kLastError, message);
      throw BackupFailure(message);
    }
  }
}

/// Menjalankan [BackupService.runIfDue] saat aplikasi dibuka (setelah jeda
/// singkat agar tidak memperlambat) lalu setiap jam, selama aplikasi terbuka.
/// [then] dijalankan setelahnya (penghapusan riwayat lama, sekali sehari).
class BackupScheduler {
  BackupScheduler(this._service, {this.then});

  final BackupService _service;
  final Future<Object?> Function()? then;
  Timer? _timer;

  void start({
    Duration firstDelay = const Duration(seconds: 30),
    Duration every = const Duration(hours: 1),
  }) {
    Timer(firstDelay, _tick);
    _timer = Timer.periodic(every, (_) => _tick());
  }

  void _tick() => unawaited(() async {
    await _service.runIfDue();
    await then?.call();
  }());

  void stop() => _timer?.cancel();
}

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref.watch(appDatabaseProvider)),
);

final backupStatusProvider = StreamProvider<BackupStatus>(
  (ref) => ref.watch(backupServiceProvider).watch(),
);
