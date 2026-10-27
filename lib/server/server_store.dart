import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

import '../sync_protocol/sync_protocol.dart';

class ServerFailure implements Exception {
  const ServerFailure(this.message, {this.status = 400});

  final String message;

  /// Kode HTTP.
  final int status;

  @override
  String toString() => message;
}

/// Komputer yang sudah dipasangkan.
class PairedTerminal {
  const PairedTerminal({
    required this.id,
    required this.code,
    required this.name,
    required this.role,
    this.lastSeen,
  });

  final String id;
  final String code;
  final String name;
  final SyncRole role;
  final DateTime? lastSeen;
}

/// Data pusat server: log perubahan (satu baris terbaru per data), daftar
/// komputer, dan kode pairing. Murni Dart (`package:sqlite3`).
///
/// - Data master hanya diterima dari komputer master; versi baru
///   menggantikan yang lama dengan nomor urut ([SyncChange.seq]) baru.
/// - Transaksi (faktur, riwayat stok) tidak pernah berubah: kiriman ulang
///   dengan uuid yang sama diabaikan (idempotent).
class ServerStore {
  ServerStore(this.db, {DateTime Function()? clock, Random? random})
    : _clock = clock ?? DateTime.now,
      _random = random ?? Random.secure() {
    _migrate();
  }

  /// Membuka file database server; [key] = kunci enkripsi (SQLite3
  /// Multiple Ciphers). `null` = tidak dienkripsi (tes).
  factory ServerStore.open(String path, {String? key}) {
    final db = sqlite3.open(path);
    if (key != null) {
      db.execute("PRAGMA key = '${key.replaceAll("'", "''")}'");
    }
    db.execute('PRAGMA journal_mode = WAL');
    return ServerStore(db);
  }

  final Database db;
  final DateTime Function() _clock;
  final Random _random;

  int get _now => _clock().millisecondsSinceEpoch ~/ 1000;

  void _migrate() {
    db.execute('''
      CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);
      CREATE TABLE IF NOT EXISTS terminals (
        id TEXT PRIMARY KEY, code TEXT NOT NULL UNIQUE, name TEXT NOT NULL,
        role TEXT NOT NULL, token_hash TEXT NOT NULL,
        paired_at INTEGER NOT NULL, last_seen INTEGER);
      CREATE TABLE IF NOT EXISTS changes (
        seq INTEGER PRIMARY KEY AUTOINCREMENT, entity TEXT NOT NULL,
        uuid TEXT NOT NULL, data TEXT, origin TEXT NOT NULL,
        at INTEGER NOT NULL, UNIQUE (entity, uuid));
    ''');
    if (_meta('server_id') == null) _setMeta('server_id', _token(16));
    if (_meta('pairing_code') == null) newPairingCode();
  }

  String? _meta(String key) {
    final r = db.select('SELECT value FROM meta WHERE key = ?', [key]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  void _setMeta(String key, String value) => db.execute(
    'INSERT INTO meta (key, value) VALUES (?, ?) '
    'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
    [key, value],
  );

  String _token(int bytes) => base64Url
      .encode([for (var i = 0; i < bytes; i++) _random.nextInt(256)])
      .replaceAll('=', '');

  static String _hash(String token) =>
      sha256.convert(utf8.encode(token)).toString();

  String get serverId => _meta('server_id')!;

  /// Kode 6 angka untuk memasangkan komputer baru.
  String get pairingCode => _meta('pairing_code')!;

  String newPairingCode() {
    final code = (100000 + _random.nextInt(900000)).toString();
    _setMeta('pairing_code', code);
    return code;
  }

  int get lastSeq =>
      (db.select('SELECT COALESCE(MAX(seq), 0) AS s FROM changes').first['s']
          as int);

  /// Memasangkan komputer [terminalId]. Mengembalikan token (hanya
  /// diberikan sekali; server menyimpan hash-nya).
  String pair({
    required String code,
    required String terminalId,
    required String terminalCode,
    required String name,
    required SyncRole role,
  }) {
    if (code.trim() != pairingCode) {
      throw const ServerFailure('Kode pairing salah.', status: 403);
    }
    final tCode = terminalCode.trim().toUpperCase();
    if (terminalId.isEmpty || tCode.isEmpty) {
      throw const ServerFailure('Identitas komputer tidak lengkap.');
    }
    final sameCode = db.select(
      'SELECT id, name FROM terminals WHERE code = ? AND id != ?',
      [tCode, terminalId],
    );
    if (sameCode.isNotEmpty) {
      throw ServerFailure(
        'Kode terminal $tCode sudah dipakai komputer '
        '"${sameCode.first['name']}". Ganti kode terminal dulu.',
        status: 409,
      );
    }
    if (role == SyncRole.master) {
      final master = db.select(
        "SELECT id, name FROM terminals WHERE role = 'master' AND id != ?",
        [terminalId],
      );
      if (master.isNotEmpty) {
        throw ServerFailure(
          'Server sudah punya komputer master ("${master.first['name']}").',
          status: 409,
        );
      }
    }
    final token = _token(32);
    db.execute(
      'INSERT INTO terminals (id, code, name, role, token_hash, paired_at) '
      'VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET '
      'code = excluded.code, name = excluded.name, role = excluded.role, '
      'token_hash = excluded.token_hash, paired_at = excluded.paired_at',
      [terminalId, tCode, name.trim(), role.name, _hash(token), _now],
    );
    return token;
  }

  /// Komputer pemilik [token], atau [ServerFailure] 401.
  PairedTerminal authenticate(String? token) {
    if (token == null || token.isEmpty) {
      throw const ServerFailure('Belum dipasangkan.', status: 401);
    }
    final r = db.select('SELECT * FROM terminals WHERE token_hash = ?', [
      _hash(token),
    ]);
    if (r.isEmpty) {
      throw const ServerFailure(
        'Komputer ini tidak dikenal server (dicabut?). Pasangkan ulang.',
        status: 401,
      );
    }
    db.execute('UPDATE terminals SET last_seen = ? WHERE id = ?', [
      _now,
      r.first['id'],
    ]);
    return _terminal(r.first);
  }

  PairedTerminal _terminal(Row r) => PairedTerminal(
    id: r['id'] as String,
    code: r['code'] as String,
    name: r['name'] as String,
    role: SyncRole.values.byName(r['role'] as String),
    lastSeen: r['last_seen'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch((r['last_seen'] as int) * 1000),
  );

  List<PairedTerminal> terminals() => [
    for (final r in db.select('SELECT * FROM terminals ORDER BY code'))
      _terminal(r),
  ];

  /// Mencabut pairing komputer berkode [code]. `false` bila tidak ada.
  bool revoke(String code) {
    db.execute('DELETE FROM terminals WHERE code = ?', [
      code.trim().toUpperCase(),
    ]);
    return db.updatedRows > 0;
  }

  /// Menyimpan kiriman [from]. Mengembalikan jumlah yang baru/berubah.
  int push(PairedTerminal from, List<SyncChange> changes) {
    var accepted = 0;
    db.execute('BEGIN');
    try {
      for (final c in changes) {
        if (c.entity.master) {
          if (from.role != SyncRole.master) {
            throw const ServerFailure(
              'Data master hanya bisa diubah dari komputer server.',
              status: 403,
            );
          }
          final data = c.data == null ? null : jsonEncode(c.data);
          final old = db.select(
            'SELECT data FROM changes WHERE entity = ? AND uuid = ?',
            [c.entity.name, c.uuid],
          );
          if (old.isNotEmpty && old.first['data'] == data) continue;
          // Hapus lalu sisipkan supaya mendapat nomor urut baru.
          db.execute('DELETE FROM changes WHERE entity = ? AND uuid = ?', [
            c.entity.name,
            c.uuid,
          ]);
          db.execute(
            'INSERT INTO changes (entity, uuid, data, origin, at) '
            'VALUES (?, ?, ?, ?, ?)',
            [c.entity.name, c.uuid, data, from.id, _now],
          );
          accepted++;
        } else {
          if (c.data == null) {
            throw const ServerFailure('Transaksi tidak bisa dihapus.');
          }
          db.execute(
            'INSERT OR IGNORE INTO changes (entity, uuid, data, origin, at) '
            'VALUES (?, ?, ?, ?, ?)',
            [c.entity.name, c.uuid, jsonEncode(c.data), from.id, _now],
          );
          accepted += db.updatedRows;
        }
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
    return accepted;
  }

  /// Perubahan setelah nomor urut [since] yang bukan kiriman [to] sendiri.
  ({List<SyncChange> changes, int seq, bool more}) pull(
    PairedTerminal to, {
    required int since,
    int limit = SyncApi.pageSize,
  }) {
    final rows = db.select(
      'SELECT * FROM changes WHERE seq > ? ORDER BY seq LIMIT ?',
      [since, limit + 1],
    );
    final more = rows.length > limit;
    final page = more ? rows.sublist(0, limit) : rows;
    return (
      changes: [
        for (final r in page)
          if (r['origin'] != to.id &&
              // Catatan aktivitas hanya untuk komputer master.
              (r['entity'] != SyncEntity.auditEntry.name ||
                  to.role == SyncRole.master))
            SyncChange(
              entity: SyncEntity.byName(r['entity'] as String)!,
              uuid: r['uuid'] as String,
              data: r['data'] == null
                  ? null
                  : (jsonDecode(r['data'] as String) as Map)
                        .cast<String, Object?>(),
              seq: r['seq'] as int,
              origin: r['origin'] as String,
            ),
      ],
      // Nomor terakhir yang diperiksa (termasuk kiriman sendiri yang
      // dilewati), supaya tidak diperiksa ulang.
      seq: page.isEmpty ? since : page.last['seq'] as int,
      more: more,
    );
  }

  /// Stok per barang di toko [storeUuid] = jumlah semua riwayat stok
  /// (`productUuid → stok`).
  Map<String, double> stockOf(String storeUuid) => {
    for (final r in db.select(
      "SELECT json_extract(data, '\$.product') AS p, "
      "SUM(json_extract(data, '\$.qty')) AS q FROM changes "
      "WHERE entity = 'stockMovement' AND json_extract(data, '\$.store') = ? "
      'GROUP BY p',
      [storeUuid],
    ))
      r['p'] as String: (r['q'] as num).toDouble(),
  };

  void close() => db.close();
}
