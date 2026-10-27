import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/audit.dart';
import '../../../core/database/tables/sales.dart';
import '../../../sync_protocol/sync_protocol.dart';
import '../../auth/domain/app_user.dart';
import '../domain/terminal.dart';
import 'sync_codec.dart';
import 'sync_schema.dart';
import 'terminal_repository.dart';

/// Permintaan HTTP ke server sinkron.
class SyncHttp {
  SyncHttp({this.timeout = const Duration(seconds: 20)});

  final Duration timeout;

  Future<Map<String, Object?>> send(
    Uri base,
    String method,
    String path, {
    String? token,
    Map<String, Object?>? body,
    Map<String, String>? query,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final uri = base.replace(path: path, queryParameters: query);
      final req = await client.openUrl(method, uri).timeout(timeout);
      req.headers.contentType = ContentType.json;
      if (token != null) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (body != null) req.write(jsonEncode(body));
      final res = await req.close().timeout(timeout);
      final text = await utf8.decodeStream(res).timeout(timeout);
      final json = text.isEmpty
          ? <String, Object?>{}
          : (jsonDecode(text) as Map).cast<String, Object?>();
      if (res.statusCode >= 400) {
        throw SyncFailure(
          '${json['error'] ?? 'Server menolak (${res.statusCode}).'}',
        );
      }
      return json;
    } on SocketException catch (e) {
      throw SyncFailure(
        'Server tidak bisa dihubungi (${base.host}:${base.port}). '
        'Pastikan server menyala dan jaringan/VPN tersambung. '
        '(${e.osError?.message ?? e.message})',
      );
    } on TimeoutException {
      throw SyncFailure('Server tidak menjawab (${base.host}:${base.port}).');
    } on FormatException {
      throw const SyncFailure('Alamat itu bukan server Toko.');
    } finally {
      client.close(force: true);
    }
  }
}

/// Status sinkron komputer ini.
class SyncStatus {
  const SyncStatus({
    this.server,
    this.paired = false,
    this.lastOkAt,
    this.lastError,
    this.lastSeq = 0,
  });

  /// Alamat server, mis. `http://192.168.1.10:8787`.
  final String? server;
  final bool paired;
  final DateTime? lastOkAt;
  final String? lastError;
  final int lastSeq;
}

/// Hasil satu kali sinkron.
class SyncResult {
  const SyncResult({required this.sent, required this.received});

  final int sent;
  final int received;
}

/// Mesin sinkron (Tahap C): pairing, kirim antrian (`sync_outbox`), tarik
/// perubahan dari server. Lihat CLAUDE.md "Arsitektur online/offline".
class SyncService {
  SyncService(
    this._db, {
    SyncHttp? http,
    DateTime Function()? clock,
    this.pageSize = SyncApi.pageSize,
  }) : _http = http ?? SyncHttp(),
       _codec = SyncCodec(_db),
       _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final SyncHttp _http;
  final SyncCodec _codec;
  final DateTime Function() _clock;

  /// Banyak data per permintaan tarik (maks. [SyncApi.pageSize]).
  final int pageSize;

  static const kServer = 'sync.server';
  static const kToken = 'sync.token';
  static const kServerId = 'sync.server_id';
  static const kLastSeq = 'sync.last_seq';
  static const kLastOk = 'sync.last_ok_at';
  static const kLastError = 'sync.last_error';

  /// Sedang berjalan (cegah dua sinkron bersamaan).
  Future<SyncResult>? _running;

  Future<SyncStatus> status() async {
    final s = _db.settingsDao;
    return _status({
      for (final k in [kServer, kToken, kLastOk, kLastError, kLastSeq])
        k: await s.get(k),
    });
  }

  Stream<SyncStatus> watchStatus() => _db.settingsDao
      .watchMany([kServer, kToken, kLastOk, kLastError, kLastSeq])
      .map(_status);

  SyncStatus _status(Map<String, String?> v) => SyncStatus(
    server: _blank(v[kServer]),
    paired: _blank(v[kToken]) != null,
    lastOkAt: switch (int.tryParse(v[kLastOk] ?? '')) {
      final ms? => DateTime.fromMillisecondsSinceEpoch(ms),
      null => null,
    },
    lastError: _blank(v[kLastError]),
    lastSeq: int.tryParse(v[kLastSeq] ?? '') ?? 0,
  );

  static String? _blank(String? v) => v == null || v.isEmpty ? null : v;

  /// Memastikan alamat [address] adalah server Toko.
  Future<Uri> check(String address) async => (await _health(address)).base;

  Future<({Uri base, String serverId})> _health(String address) async {
    final base = SyncApi.parseAddress(address);
    if (base == null) throw const SyncFailure('Alamat server tidak valid.');
    final r = await _http.send(base, 'GET', SyncApi.health);
    if (r['name'] != SyncApi.serverName) {
      throw const SyncFailure('Alamat itu bukan server Toko.');
    }
    return (base: base, serverId: '${r['serverId']}');
  }

  /// Memasangkan komputer ini ke server.
  ///
  /// - [role] master: komputer server/admin. Server harus belum punya
  ///   master; semua data komputer ini dikirim ke server.
  /// - [role] client: komputer kasir cabang. Harus belum punya transaksi;
  ///   data lokal diganti data dari server, lalu semua user harus login
  ///   lagi (akun dari server).
  /// Mengembalikan `true` bila data lokal diganti data server (komputer
  /// cabang baru: semua user harus login lagi).
  Future<bool> pair({
    required AppUser actor,
    required String address,
    required String code,
    required SyncRole role,
    String? name,
  }) async {
    if (!actor.isAdmin) {
      throw const SyncFailure('Hanya admin yang bisa menyambungkan server.');
    }
    final (:base, :serverId) = await _health(address);
    final terminal = await TerminalRepository(_db).current();
    // Sambung ulang ke server yang sama (mis. setelah ganti kode
    // terminal): data lokal tetap, lanjut dari posisi terakhir.
    final reconnect = await _db.settingsDao.get(kServerId) == serverId;
    if (role == SyncRole.client && !reconnect) {
      final sales = await _db
          .customSelect('SELECT COUNT(*) AS n FROM sales')
          .getSingle();
      if (sales.read<int>('n') > 0) {
        throw const SyncFailure(
          'Komputer ini sudah punya transaksi. Komputer cabang harus '
          'komputer baru (data barang & akun diambil dari server). Backup '
          'dulu bila perlu, lalu pakai instalasi baru.',
        );
      }
    }
    final r = await _http.send(
      base,
      'POST',
      SyncApi.pair,
      body: {
        'version': SyncApi.version,
        'code': code.trim(),
        'terminalId': terminal.id,
        'terminalCode': terminal.code,
        'name': (name == null || name.trim().isEmpty)
            ? Platform.localHostname
            : name.trim(),
        'role': role.name,
      },
    );
    final s = _db.settingsDao;
    await s.set(kServer, base.toString());
    await s.set(kToken, '${r['token']}');
    await s.set(kServerId, '${r['serverId']}');
    if (!reconnect) await s.set(kLastSeq, '0');
    await s.set(kLastError, '');
    await TerminalRepository(_db).setMode(
      role == SyncRole.master ? TerminalMode.server : TerminalMode.client,
    );
    await installSyncTriggers(_db);

    if (reconnect) {
      // Data sudah ada di server; antrian lanjut seperti biasa.
    } else if (role == SyncRole.master) {
      await _enqueueSnapshot();
    } else {
      await _codec.wipeForClient();
    }
    await _db.auditDao.append(
      type: AuditType.syncPaired,
      summary:
          '${reconnect ? 'Disambungkan ulang' : 'Disambungkan'} ke server '
          '${base.host}:${base.port} sebagai '
          '${role == SyncRole.master ? 'komputer server (master)' : 'komputer cabang'}',
      userId: role == SyncRole.master ? actor.id : null,
      userName: actor.fullName,
    );
    await syncNow();
    return !reconnect && role == SyncRole.client;
  }

  /// Memutus sambungan (data lokal tetap).
  Future<void> unpair({required AppUser actor}) async {
    if (!actor.isAdmin) {
      throw const SyncFailure('Hanya admin yang bisa memutus sambungan.');
    }
    // ID server & posisi terakhir disimpan supaya bisa disambung ulang
    // tanpa mengulang dari awal.
    for (final k in [kServer, kToken, kLastError]) {
      await _db.settingsDao.set(k, '');
    }
    for (final sql in dropSyncTriggerStatements()) {
      await _db.customStatement(sql);
    }
    await _db.auditDao.append(
      type: AuditType.syncPaired,
      summary: 'Sambungan ke server diputus',
      userId: actor.id,
      userName: actor.fullName,
    );
  }

  /// Kiriman awal komputer master: semua data yang sudah ada. Stok yang
  /// belum punya riwayat (data lama, barang contoh) dicatat dulu sebagai
  /// riwayat "Saldo awal sinkron", karena stok di komputer lain dihitung
  /// dari riwayat stok.
  Future<void> _enqueueSnapshot() async {
    final gaps = await _db
        .customSelect(
          'SELECT sp.store_id, sp.product_id, sp.stock - COALESCE((SELECT '
          'SUM(m.qty_change) FROM stock_movements m WHERE m.store_id = '
          'sp.store_id AND m.product_id = sp.product_id), 0) AS gap '
          'FROM store_products sp',
        )
        .get();
    await _db.batch((b) {
      for (final r in gaps) {
        final gap = (r.data['gap'] as num).toDouble();
        if (gap.abs() < 1e-9) continue;
        b.insert(
          _db.stockMovements,
          StockMovementsCompanion.insert(
            productId: r.read<int>('product_id'),
            storeId: Value(r.read<int>('store_id')),
            type: StockMovementType.adjust,
            qtyChange: gap,
            note: const Value('Saldo awal sinkron'),
          ),
        );
      }
    });
    for (final spec in syncSpecs) {
      final uuids = await _codec.allUuids(spec.entity);
      await _db.batch((b) {
        for (final u in uuids) {
          b.insert(
            _db.syncOutbox,
            SyncOutboxCompanion.insert(entity: spec.entity, entityUuid: u),
          );
        }
      });
    }
  }

  /// Kirim antrian lalu tarik perubahan. Gagal = pesan disimpan di
  /// [SyncStatus.lastError] lalu dilempar ulang.
  Future<SyncResult> syncNow() =>
      _running ??= _sync().whenComplete(() => _running = null);

  Future<SyncResult> _sync() async {
    final s = _db.settingsDao;
    final server = _blank(await s.get(kServer));
    final token = _blank(await s.get(kToken));
    if (server == null || token == null) {
      throw const SyncFailure('Komputer ini belum disambungkan ke server.');
    }
    final base = Uri.parse(server);
    try {
      final terminal = await TerminalRepository(_db).current();
      final sent = await _push(base, token, terminal.isServer);
      final received = await _pull(base, token);
      await s.set(kLastOk, '${_clock().millisecondsSinceEpoch}');
      await s.set(kLastError, '');
      return SyncResult(sent: sent, received: received);
    } on SyncFailure catch (e) {
      await s.set(kLastError, e.message);
      rethrow;
    }
  }

  Future<int> _push(Uri base, String token, bool master) async {
    var sent = 0;
    while (true) {
      final pending = await _db.outboxDao.pending(limit: SyncApi.pageSize);
      if (pending.isEmpty) return sent;
      // Satu kiriman per data (antrian bisa berisi beberapa perubahan
      // data yang sama).
      final latest = <(SyncEntity, String), List<int>>{};
      for (final o in pending) {
        latest.putIfAbsent((o.entity, o.entityUuid), () => []).add(o.id);
      }
      final changes = <SyncChange>[];
      for (final (entity, uuid) in latest.keys) {
        // Komputer cabang tidak mengirim data master (hanya master yang
        // boleh mengubahnya).
        if (entity.master && !master) continue;
        final change = await _codec.export(entity, uuid);
        // Transaksi/catatan yang sudah tidak ada (dihapus di luar aplikasi)
        // tidak bisa dikirim; pemeriksaan keutuhan yang melaporkannya.
        if (change.deleted && !entity.master) continue;
        changes.add(change);
      }
      final now = _clock();
      if (changes.isNotEmpty) {
        try {
          await _http.send(
            base,
            'POST',
            SyncApi.push,
            token: token,
            body: {
              'changes': [for (final c in changes) c.toJson()],
            },
          );
        } on SyncFailure catch (e) {
          for (final o in pending) {
            await _db.outboxDao.markFailed(o.id, now, e.message);
          }
          rethrow;
        }
      }
      await _db.transaction(() async {
        for (final o in pending) {
          await _db.outboxDao.markSent(o.id, now);
        }
      });
      sent += changes.length;
    }
  }

  /// Menarik perubahan per halaman dan langsung menerapkannya. Data yang
  /// rujukannya belum tiba ditunda ke halaman berikutnya; nomor urut yang
  /// disimpan tidak melewati data yang tertunda (aman bila terputus).
  Future<int> _pull(Uri base, String token) async {
    final s = _db.settingsDao;
    var since = int.tryParse(await s.get(kLastSeq) ?? '') ?? 0;
    var deferred = <SyncChange>[];
    var received = 0;
    while (true) {
      final r = await _http.send(
        base,
        'GET',
        SyncApi.pull,
        token: token,
        query: {'since': '$since', 'limit': '$pageSize'},
      );
      final page = [
        for (final c in (r['changes'] as List? ?? const []))
          SyncChange.fromJson((c as Map).cast()),
      ];
      received += page.length;
      since = r['seq'] as int? ?? since;
      final more = r['more'] == true;
      if (page.isNotEmpty || deferred.isNotEmpty) {
        final applied = await _codec.apply([...deferred, ...page]);
        deferred = applied.deferred;
        await _logReceived(applied);
        if (!more && deferred.isNotEmpty) {
          await s.set(kLastSeq, '${_cursorBefore(deferred, since)}');
          throw SyncFailure(
            '${deferred.length} data dari server belum bisa diterapkan: '
            '${applied.lastMissing}',
          );
        }
      }
      await s.set(kLastSeq, '${_cursorBefore(deferred, since)}');
      if (!more) return received;
    }
  }

  /// Nomor urut yang aman disimpan: sebelum data tertunda yang tertua.
  static int _cursorBefore(List<SyncChange> deferred, int since) {
    var cursor = since;
    for (final c in deferred) {
      final seq = c.seq;
      if (seq != null && seq - 1 < cursor) cursor = seq - 1;
    }
    return cursor;
  }

  Future<void> _logReceived(SyncApplied applied) async {
    if (applied.total == 0) return;
    await _db.auditDao.append(
      type: AuditType.syncReceived,
      summary:
          'Dari server: ${applied.sales.length} faktur, '
          '${applied.movements} riwayat stok, ${applied.master} data '
          'master${applied.audit == 0 ? '' : ', ${applied.audit} catatan aktivitas'}',
      data: {
        'sales': [for (final x in applied.sales) x.toJson()],
      },
    );
  }
}

/// Sinkron otomatis: tiap [every] (bawaan 30 detik) bila sudah
/// disambungkan. Gagal (mis. internet/VPN putus) dicatat di status dan
/// dicoba lagi berikutnya; data tetap aman di antrian.
class SyncScheduler {
  SyncScheduler(this._service);

  final SyncService _service;
  Timer? _timer;

  void start({
    Duration firstDelay = const Duration(seconds: 5),
    Duration every = const Duration(seconds: 30),
  }) {
    Timer(firstDelay, _tick);
    _timer = Timer.periodic(every, (_) => _tick());
  }

  void _tick() => unawaited(() async {
    if (!(await _service.status()).paired) return;
    try {
      await _service.syncNow();
    } on SyncFailure {
      // Sudah dicatat di status.
    } catch (_) {
      // Error tak terduga: coba lagi berikutnya.
    }
  }());

  void stop() => _timer?.cancel();
}

/// Memasang trigger antrian sinkron (lihat [syncTriggerStatements]) bila
/// komputer ini sudah disambungkan. Dipanggil saat database dibuka dan
/// setelah pairing.
Future<void> installSyncTriggers(AppDatabase db) async {
  for (final sql in syncTriggerStatements()) {
    await db.customStatement(sql);
  }
}

final syncServiceProvider = Provider<SyncService>(
  (ref) => SyncService(ref.watch(appDatabaseProvider)),
);

final syncStatusProvider = StreamProvider<SyncStatus>(
  (ref) => ref.watch(syncServiceProvider).watchStatus(),
);
