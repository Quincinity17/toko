import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// DPAPI Windows (`CryptProtectData`): data hanya bisa dibuka kembali oleh
/// akun Windows yang sama di komputer yang sama, dan hanya dengan [entropy]
/// yang sama. Hanya dipanggil di Windows.

const _uiForbidden = 0x1; // CRYPTPROTECT_UI_FORBIDDEN

Uint8List windowsProtect(Uint8List data, Uint8List entropy) =>
    _run(data, entropy, protect: true);

Uint8List windowsUnprotect(Uint8List data, Uint8List entropy) =>
    _run(data, entropy, protect: false);

Uint8List _run(Uint8List data, Uint8List entropy, {required bool protect}) =>
    using((arena) {
      Pointer<CRYPT_INTEGER_BLOB> blob(Uint8List bytes) {
        final buffer = arena<Uint8>(bytes.length);
        buffer.asTypedList(bytes.length).setAll(0, bytes);
        final b = arena<CRYPT_INTEGER_BLOB>();
        b.ref
          ..cbData = bytes.length
          ..pbData = buffer;
        return b;
      }

      final input = blob(data);
      final salt = blob(entropy);
      final output = arena<CRYPT_INTEGER_BLOB>();
      final ok = protect
          ? CryptProtectData(input, null, salt, null, _uiForbidden, output)
          : CryptUnprotectData(input, null, salt, null, _uiForbidden, output);
      if (!ok.value) {
        throw StateError('DPAPI gagal (kode ${ok.error}).');
      }
      try {
        return Uint8List.fromList(
          output.ref.pbData.asTypedList(output.ref.cbData),
        );
      } finally {
        LocalFree(HLOCAL(output.ref.pbData));
      }
    });
