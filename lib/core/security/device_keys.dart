import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'windows_dpapi.dart';

/// Rahasia perangkat (32 byte acak, dibuat sekali per komputer/HP), sumber
/// kunci enkripsi database ([databaseKey]) dan kunci segel data
/// ([sealKey], lihat `Sealer`).
///
/// Disimpan di `toko.key` di samping database:
/// - Windows: dikunci DPAPI (hanya akun Windows itu di komputer itu) +
///   garam rahasia aplikasi.
/// - Android/macOS/Linux: di penyimpanan pribadi aplikasi, diacak dengan
///   garam aplikasi (Android: tidak bisa dibaca aplikasi lain tanpa root).
///
/// Tujuannya mencegah file database dibuka/diubah dengan program lain (mis.
/// DB Browser). Orang yang sangat ahli dan bisa membongkar aplikasi tetap
/// mungkin mendapatkan kuncinya; perubahan seperti itu tertangkap segel data
/// dan (nanti) pemeriksaan di server.
class DeviceKeys {
  DeviceKeys(this._master) : assert(_master.length == 32);

  /// Kunci tetap untuk tes (database di memori tidak dienkripsi).
  factory DeviceKeys.forTests() =>
      DeviceKeys(Uint8List.fromList(List.generate(32, (i) => i)));

  final Uint8List _master;

  static Uint8List _derive(Uint8List master, String label) =>
      Uint8List.fromList(
        Hmac(sha256, master).convert(utf8.encode(label)).bytes,
      );

  /// Kunci SQLite3MultipleCiphers (`PRAGMA key`), heksadesimal.
  String get databaseKey => _derive(
    _master,
    'toko-db-v1',
  ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Kunci HMAC segel data & catatan aktivitas.
  Uint8List get sealKey => _derive(_master, 'toko-seal-v1');
}

/// Membaca/membuat `toko.key`.
abstract final class DeviceKeyStore {
  static const fileName = 'toko.key';
  static const _magic = 'TOKOKEY1';

  /// Garam rahasia aplikasi (bukan pengganti DPAPI; menyulitkan membuka
  /// file kunci dengan perintah standar seperti PowerShell).
  static final _appSalt = Uint8List.fromList(const [
    0x5a, 0x19, 0xc3, 0x7e, 0x02, 0xb8, 0x44, 0xd1, 0x9f, 0x63, 0x2a, 0xe7, //
    0x10, 0x8c, 0x55, 0xfb, 0x36, 0xa0, 0x7d, 0x4e, 0xc9, 0x13, 0x88, 0x2f,
    0xe4, 0x61, 0xb5, 0x0a, 0x97, 0x3c, 0xd8, 0x71,
  ]);

  static File _file(Directory dir) => File(p.join(dir.path, fileName));

  /// `null` bila belum ada file kunci.
  static Future<DeviceKeys?> read(Directory dir) async {
    final file = _file(dir);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    final magic = utf8.encode(_magic);
    if (bytes.length <= magic.length ||
        utf8.decode(bytes.sublist(0, magic.length), allowMalformed: true) !=
            _magic) {
      throw const FormatException('File kunci rusak.');
    }
    final payload = Uint8List.fromList(bytes.sublist(magic.length));
    final master = Platform.isWindows
        ? windowsUnprotect(payload, _appSalt)
        : _xor(payload);
    if (master.length != 32) throw const FormatException('File kunci rusak.');
    return DeviceKeys(master);
  }

  /// Membuat rahasia baru dan menyimpannya.
  static Future<DeviceKeys> create(Directory dir) async {
    final rnd = Random.secure();
    final master = Uint8List.fromList(
      List.generate(32, (_) => rnd.nextInt(256)),
    );
    final payload = Platform.isWindows
        ? windowsProtect(master, _appSalt)
        : _xor(master);
    final file = _file(dir);
    await file.parent.create(recursive: true);
    await file.writeAsBytes([...utf8.encode(_magic), ...payload], flush: true);
    if (Platform.isMacOS || Platform.isLinux) {
      try {
        await Process.run('chmod', ['600', file.path]);
      } on Object {
        // Sandbox macOS: folder aplikasi sudah pribadi.
      }
    }
    return DeviceKeys(master);
  }

  static Uint8List _xor(Uint8List data) => Uint8List.fromList([
    for (var i = 0; i < data.length; i++) data[i] ^ _appSalt[i % 32],
  ]);
}
