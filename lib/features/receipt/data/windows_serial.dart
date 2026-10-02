import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'printer_failure.dart';

/// Port serial Windows (COM) lewat FFI kernel32. Printer Bluetooth yang sudah
/// dipasangkan muncul sebagai port COM, jadi jalurnya sama.

/// Membuka [port] (mis. `COM5`), mengatur baud 8-N-1, lalu menulis [data].
/// [data] kosong = hanya cek port bisa dibuka.
void windowsWriteSerial(String port, int baudRate, Uint8List data) => using((
  arena,
) {
  final opened = CreateFile(
    arena.pcwstr(r'\\.\' + port),
    GENERIC_WRITE,
    FILE_SHARE_NONE,
    null,
    OPEN_EXISTING,
    FILE_ATTRIBUTE_NORMAL,
    null,
  );
  final handle = opened.value;
  if (handle.address == INVALID_HANDLE_VALUE.address || handle.address == 0) {
    throw PrinterFailure(
      'Port $port tidak bisa dibuka. Pastikan printer menyala, sudah '
      'dipasangkan (Bluetooth), dan tidak sedang dipakai aplikasi lain.',
    );
  }
  try {
    final dcb = arena<DCB>();
    dcb.ref.DCBlength = sizeOf<DCB>();
    if (GetCommState(handle, dcb).value) {
      dcb.ref
        ..BaudRate = baudRate
        ..ByteSize = 8
        ..Parity = NOPARITY
        ..StopBits = ONESTOPBIT;
      SetCommState(handle, dcb);
    }
    final timeouts = arena<COMMTIMEOUTS>();
    timeouts.ref
      ..WriteTotalTimeoutConstant = 5000
      ..WriteTotalTimeoutMultiplier = 10;
    SetCommTimeouts(handle, timeouts);

    if (data.isEmpty) return;
    final buffer = arena<Uint8>(data.length);
    buffer.asTypedList(data.length).setAll(0, data);
    final written = arena<Uint32>();
    final ok = WriteFile(handle, buffer, data.length, written, null);
    if (!ok.value || written.value != data.length) {
      throw PrinterFailure(
        'Gagal mengirim data ke $port (terkirim ${written.value} dari '
        '${data.length} byte). Coba cek baud rate.',
      );
    }
  } finally {
    CloseHandle(handle);
  }
});
