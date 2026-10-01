import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

const xlsxMime =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// Simpan [bytes] lewat dialog "Simpan sebagai". Mengembalikan lokasi file,
/// atau `null` jika dibatalkan.
Future<String?> saveFileAs({
  required String fileName,
  required Uint8List bytes,
  required String extension,
  required String mimeType,
}) async {
  final uri = await FilePicker.saveFile(
    fileName: fileName,
    bytes: bytes,
    dialogTitle: 'Simpan file',
    type: FileType.custom,
    allowedExtensions: [extension],
    mimeType: mimeType,
  );
  if (uri == null) return null;
  return uri.scheme == 'file' ? uri.toFilePath() : uri.toString();
}

/// `20261015-1430`, untuk nama file export.
String fileStamp([DateTime? at]) {
  final n = at ?? DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${n.year}${two(n.month)}${two(n.day)}-${two(n.hour)}${two(n.minute)}';
}
