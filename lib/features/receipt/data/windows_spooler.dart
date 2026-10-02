import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'printer_failure.dart';

/// Akses spooler Windows (winspool.drv) lewat FFI. Hanya dipanggil di
/// Windows; di platform lain library tidak pernah dimuat.

/// Nama semua printer yang terpasang (lokal dan sambungan jaringan).
List<String> windowsPrinterNames() => using((arena) {
  const flags = PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS;
  final needed = arena<Uint32>();
  final count = arena<Uint32>();
  // Panggilan pertama hanya menanyakan ukuran buffer.
  EnumPrinters(flags, null, 4, null, 0, needed, count);
  if (needed.value == 0) return const <String>[];
  final buffer = arena<Uint8>(needed.value);
  final result = EnumPrinters(
    flags,
    null,
    4,
    buffer,
    needed.value,
    needed,
    count,
  );
  if (!result.value) {
    throw const PrinterFailure('Daftar printer tidak bisa dibaca.');
  }
  final infos = buffer.cast<PRINTER_INFO_4>();
  return [
    for (var i = 0; i < count.value; i++) infos[i].pPrinterName.toDartString(),
  ];
});

/// Mengirim [data] apa adanya (RAW) ke printer [printerName], tanpa diolah
/// driver. Cocok untuk printer thermal ESC/POS, termasuk yang dipasang
/// dengan driver "Generic / Text Only".
void windowsWriteRaw(String printerName, Uint8List data, String jobName) =>
    using((arena) {
      final handle = arena<Pointer>();
      final opened = OpenPrinter(arena.pcwstr(printerName), handle, null);
      if (!opened.value) {
        throw PrinterFailure(
          'Printer "$printerName" tidak ditemukan. Periksa nama printer di '
          'Pengaturan › Struk & Printer.',
        );
      }
      final printer = PRINTER_HANDLE(handle.value);
      try {
        final doc = arena<DOC_INFO_1>();
        doc.ref
          ..pDocName = arena.pwstr(jobName)
          ..pOutputFile = PWSTR(nullptr)
          ..pDatatype = arena.pwstr('RAW');
        if (StartDocPrinter(printer, 1, doc) == 0) {
          throw PrinterFailure(
            'Printer "$printerName" menolak pekerjaan cetak.',
          );
        }
        try {
          StartPagePrinter(printer);
          final buffer = arena<Uint8>(data.length);
          buffer.asTypedList(data.length).setAll(0, data);
          final written = arena<Uint32>();
          final ok = WritePrinter(printer, buffer, data.length, written);
          EndPagePrinter(printer);
          if (!ok || written.value != data.length) {
            throw PrinterFailure('Gagal mengirim data ke "$printerName".');
          }
        } finally {
          EndDocPrinter(printer);
        }
      } finally {
        ClosePrinter(printer);
      }
    });
