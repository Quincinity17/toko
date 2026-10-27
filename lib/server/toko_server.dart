import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../sync_protocol/sync_protocol.dart';
import 'server_store.dart';

/// Server HTTP sinkron (lihat [SyncApi]). Satu permintaan diproses satu per
/// satu supaya urutan tulis ke [ServerStore] aman.
class TokoServer {
  TokoServer(this.store, {this.log = print});

  final ServerStore store;
  final void Function(String) log;
  HttpServer? _http;
  Future<void> _queue = Future.value();

  int get port => _http?.port ?? 0;

  Future<void> start({
    int port = SyncApi.defaultPort,
    InternetAddress? address,
  }) async {
    _http = await HttpServer.bind(address ?? InternetAddress.anyIPv4, port);
    _http!.listen((req) {
      // Diproses berurutan.
      _queue = _queue.then((_) => _handle(req)).catchError((_) {});
    });
  }

  Future<void> stop() async => _http?.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    res.headers.contentType = ContentType.json;
    try {
      final body = await _body(req);
      final out = switch ((req.method, req.uri.path)) {
        ('GET', SyncApi.health) => {
          'ok': true,
          'name': SyncApi.serverName,
          'version': SyncApi.version,
          'serverId': store.serverId,
        },
        ('POST', SyncApi.pair) => _pair(body),
        ('POST', SyncApi.push) => _push(req, body),
        ('GET', SyncApi.pull) => _pull(req),
        ('GET', SyncApi.status) => _status(req),
        _ => throw const ServerFailure('Alamat tidak dikenal.', status: 404),
      };
      res.write(jsonEncode(out));
    } on ServerFailure catch (e) {
      res.statusCode = e.status;
      res.write(jsonEncode({'error': e.message}));
    } on FormatException {
      res.statusCode = 400;
      res.write(jsonEncode({'error': 'Format data tidak valid.'}));
    } on SyncProtocolError catch (e) {
      res.statusCode = 400;
      res.write(jsonEncode({'error': e.message}));
    } catch (e) {
      log('Error ${req.method} ${req.uri.path}: $e');
      res.statusCode = 500;
      res.write(jsonEncode({'error': 'Kesalahan server: $e'}));
    }
    await res.close();
  }

  static Future<Map<String, Object?>> _body(HttpRequest req) async {
    if (req.method != 'POST') return const {};
    final text = await utf8.decodeStream(req);
    if (text.isEmpty) return const {};
    return (jsonDecode(text) as Map).cast<String, Object?>();
  }

  PairedTerminal _auth(HttpRequest req) {
    final header = req.headers.value(HttpHeaders.authorizationHeader);
    final token = header != null && header.startsWith('Bearer ')
        ? header.substring(7)
        : null;
    return store.authenticate(token);
  }

  Map<String, Object?> _pair(Map<String, Object?> body) {
    if (body['version'] != SyncApi.version) {
      throw const ServerFailure(
        'Versi aplikasi dan server berbeda. Perbarui keduanya.',
        status: 426,
      );
    }
    final role = SyncRole.values.asNameMap()[body['role']];
    if (role == null) throw const ServerFailure('Peran tidak dikenal.');
    final token = store.pair(
      code: '${body['code'] ?? ''}',
      terminalId: '${body['terminalId'] ?? ''}',
      terminalCode: '${body['terminalCode'] ?? ''}',
      name: '${body['name'] ?? ''}',
      role: role,
    );
    log('Dipasangkan: ${body['terminalCode']} (${body['name']}, ${role.name})');
    return {'token': token, 'serverId': store.serverId, 'seq': store.lastSeq};
  }

  Map<String, Object?> _push(HttpRequest req, Map<String, Object?> body) {
    final from = _auth(req);
    final list = body['changes'];
    if (list is! List) throw const ServerFailure('Tidak ada data.');
    final changes = [
      for (final c in list) SyncChange.fromJson((c as Map).cast()),
    ];
    final accepted = store.push(from, changes);
    return {'accepted': accepted, 'seq': store.lastSeq};
  }

  Map<String, Object?> _pull(HttpRequest req) {
    final to = _auth(req);
    final q = req.uri.queryParameters;
    final page = store.pull(
      to,
      since: int.tryParse(q['since'] ?? '') ?? 0,
      limit: (int.tryParse(q['limit'] ?? '') ?? SyncApi.pageSize).clamp(
        1,
        SyncApi.pageSize,
      ),
    );
    return {
      'changes': [for (final c in page.changes) c.toJson()],
      'seq': page.seq,
      'more': page.more,
    };
  }

  Map<String, Object?> _status(HttpRequest req) {
    _auth(req);
    return {
      'serverId': store.serverId,
      'seq': store.lastSeq,
      'terminals': [
        for (final t in store.terminals())
          {
            'code': t.code,
            'name': t.name,
            'role': t.role.name,
            'lastSeen': t.lastSeen?.toIso8601String(),
          },
      ],
    };
  }
}
