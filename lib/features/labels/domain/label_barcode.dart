import 'package:barcode/barcode.dart';

/// Jenis barcode untuk [data]: EAN-13/EAN-8 bila datanya barcode pabrik
/// yang sah (angka + digit pemeriksa), selain itu Code 128 (huruf & angka).
/// `null` = tidak bisa dibuat barcode (karakter di luar ASCII).
Barcode? labelSymbology(String data) {
  if (RegExp(r'^\d{13}$').hasMatch(data) && Barcode.ean13().isValid(data)) {
    return Barcode.ean13(drawEndChar: false);
  }
  if (RegExp(r'^\d{8}$').hasMatch(data) && Barcode.ean8().isValid(data)) {
    return Barcode.ean8();
  }
  final code128 = Barcode.code128();
  return code128.isValid(data) ? code128 : null;
}
