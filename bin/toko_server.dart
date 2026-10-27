import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:toko/server/server_store.dart';
import 'package:toko/server/toko_server.dart';
import 'package:toko/sync_protocol/sync_protocol.dart';

const _usage =
    '''
Server data Toko (sinkron antar komputer kasir).

Pemakaian: toko_server [pilihan]
  --port <n>          Port (bawaan ${SyncApi.defaultPort})
  --data <folder>     Folder data (bawaan: %ProgramData%\\TokoServer di
                      Windows, ~/.toko-server di macOS/Linux)
  --code              Tampilkan kode pairing lalu keluar
  --new-code          Buat kode pairing baru lalu keluar
  --terminals         Daftar komputer yang terpasang lalu keluar
  --revoke <kode>     Cabut komputer berkode terminal itu lalu keluar
  --help              Bantuan ini
''';

Future<void> main(List<String> args) async {
  String? opt(String name) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  if (args.contains('--help')) {
    stdout.write(_usage);
    return;
  }
  final dir = Directory(opt('--data') ?? _defaultDataDir());
  await dir.create(recursive: true);
  final store = ServerStore.open(
    p.join(dir.path, 'toko-server.sqlite'),
    key: await _key(File(p.join(dir.path, 'toko-server.key'))),
  );
  final codeFile = File(p.join(dir.path, 'KODE-PAIRING.txt'));
  Future<void> writeCode() => codeFile.writeAsString(
    'Kode pairing: ${store.pairingCode}\r\n'
    'Masukkan di aplikasi: Pengaturan › Terminal & Sinkronisasi.\r\n',
  );

  if (args.contains('--code')) {
    stdout.writeln('Kode pairing: ${store.pairingCode}');
    return store.close();
  }
  if (args.contains('--new-code')) {
    stdout.writeln('Kode pairing baru: ${store.newPairingCode()}');
    await writeCode();
    return store.close();
  }
  if (args.contains('--terminals')) {
    for (final t in store.terminals()) {
      stdout.writeln(
        '${t.code.padRight(7)} ${t.role.name.padRight(7)} ${t.name} '
        '(terakhir: ${t.lastSeen ?? '-'})',
      );
    }
    return store.close();
  }
  if (opt('--revoke') case final code?) {
    stdout.writeln(
      store.revoke(code) ? 'Dicabut: $code' : 'Tidak ada terminal $code',
    );
    return store.close();
  }

  final port = int.tryParse(opt('--port') ?? '') ?? SyncApi.defaultPort;
  final server = TokoServer(
    store,
    log: (m) => stdout.writeln('[${DateTime.now()}] $m'),
  );
  await server.start(port: port);
  await writeCode();
  stdout
    ..writeln('Server Toko berjalan di port $port')
    ..writeln('Folder data : ${dir.path}')
    ..writeln('Kode pairing: ${store.pairingCode}')
    ..writeln('Alamat untuk komputer kasir:');
  for (final ni in await NetworkInterface.list(
    type: InternetAddressType.IPv4,
  )) {
    for (final a in ni.addresses) {
      stdout.writeln('  ${a.address}:$port (${ni.name})');
    }
  }
  ProcessSignal.sigint.watch().listen((_) async {
    await server.stop();
    store.close();
    exit(0);
  });
}

String _defaultDataDir() {
  if (Platform.isWindows) {
    final base =
        Platform.environment['ProgramData'] ?? Platform.environment['APPDATA']!;
    return p.join(base, 'TokoServer');
  }
  return p.join(Platform.environment['HOME'] ?? '.', '.toko-server');
}

/// Kunci enkripsi database server: 32 byte acak, dibuat sekali. Simpan
/// salinan folder data (termasuk file kunci) sebagai backup.
Future<String> _key(File file) async {
  if (await file.exists()) return (await file.readAsString()).trim();
  final r = Random.secure();
  final key = [
    for (var i = 0; i < 32; i++)
      r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
  await file.writeAsString(key);
  return key;
}
