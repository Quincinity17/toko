import 'dart:convert';
import 'dart:io';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../security/device_keys.dart';
import 'app_database.dart';

/// Hasil membuka database saat aplikasi dimulai.
sealed class DatabaseOpenResult {
  const DatabaseOpenResult();
}

class DatabaseOpened extends DatabaseOpenResult {
  const DatabaseOpened(this.db);
  final AppDatabase db;
}

/// Database terenkripsi tidak bisa dibuka: file kunci hilang/rusak atau
/// kuncinya tidak cocok (mis. database disalin dari komputer lain). Data
/// hanya bisa dikembalikan dari file backup.
class DatabaseLocked extends DatabaseOpenResult {
  const DatabaseLocked({required this.databasePath, required this.reason});
  final String databasePath;
  final String reason;
}

const _dbName = 'toko';

bool isPlainSqlite(File file) {
  if (!file.existsSync() || file.lengthSync() < 16) return false;
  final raf = file.openSync();
  try {
    return utf8.decode(raf.readSync(16), allowMalformed: true) ==
        'SQLite format 3\u0000';
  } finally {
    raf.closeSync();
  }
}

/// Membuka `toko.sqlite` terenkripsi (SQLite3MultipleCiphers) di folder
/// aplikasi:
/// 1. Kunci perangkat dibaca dari `toko.key`, atau dibuat bila belum ada dan
///    database belum terenkripsi.
/// 2. Database yang belum terenkripsi (instalasi lama, atau hasil memulihkan
///    backup) dienkripsi di tempat (`PRAGMA rekey`).
/// 3. Kunci yang salah → [DatabaseLocked] (aplikasi menampilkan layar
///    pemulihan, tidak membuat database baru diam-diam).
Future<DatabaseOpenResult> openDeviceDatabase({
  Future<Directory> Function()? directory,
}) async {
  final dir = await (directory ?? getApplicationSupportDirectory)();
  final file = File(p.join(dir.path, '$_dbName.sqlite'));

  DeviceKeys? keys;
  try {
    keys = await DeviceKeyStore.read(dir);
  } on Object {
    keys = null;
    if (file.existsSync() && !isPlainSqlite(file)) {
      return DatabaseLocked(
        databasePath: file.path,
        reason: 'File kunci database rusak.',
      );
    }
  }
  if (keys == null) {
    if (file.existsSync() && !isPlainSqlite(file)) {
      return DatabaseLocked(
        databasePath: file.path,
        reason: 'File kunci database (${DeviceKeyStore.fileName}) hilang.',
      );
    }
    keys = await DeviceKeyStore.create(dir);
  }
  final key = keys.databaseKey;

  if (isPlainSqlite(file)) {
    // Mode jurnal biasa dulu: rekey tidak bisa di mode WAL.
    final raw = sqlite3.open(file.path);
    try {
      raw.execute('PRAGMA journal_mode = DELETE');
      raw.execute("PRAGMA rekey = '$key'");
    } finally {
      raw.close();
    }
  }

  final db = AppDatabase(
    driftDatabase(
      name: _dbName,
      native: DriftNativeOptions(
        databaseDirectory: () async => dir,
        // Folder sementara SQLite; tes memberi [directory] sendiri.
        tempDirectoryPath: directory == null ? null : () async => dir.path,
        setup: (raw) => raw.execute("PRAGMA key = '$key'"),
      ),
    ),
    keys: keys,
  );
  try {
    // Kunci salah baru ketahuan saat membaca.
    await db.customSelect('SELECT count(*) FROM sqlite_master').get();
  } on Object {
    await db.close();
    return DatabaseLocked(
      databasePath: file.path,
      reason: 'Kunci database tidak cocok dengan perangkat ini.',
    );
  }
  return DatabaseOpened(db);
}

/// Salinan lengkap database ke [path] yang TIDAK terenkripsi (backup &
/// jaring pengaman sebelum memulihkan): `VACUUM INTO` menghasilkan salinan
/// berkunci sama, lalu kuncinya dilepas supaya bisa dipulihkan di perangkat
/// lain (kunci terikat ke perangkat ini).
Future<void> copyDatabasePlain(AppDatabase db, String path) async {
  final out = File(path);
  if (await out.exists()) await out.delete();
  await db.customStatement('VACUUM INTO ?', [path]);
  final key = db.keys?.databaseKey;
  if (key == null) return; // database tes tidak dienkripsi
  final raw = sqlite3.open(path);
  try {
    raw.execute("PRAGMA key = '$key'");
    raw.execute("PRAGMA rekey = ''");
  } finally {
    raw.close();
  }
}
