import 'package:flutter/services.dart';

import 'formatters.dart';

/// Membaca angka yang diketik dengan format Indonesia.
///
/// - `1.500` → 1500 (titik = pemisah ribuan)
/// - `0,5` / `2,25` → 0.5 / 2.25 (koma = desimal)
/// - `1.5` → 1.5 (titik yang tidak diikuti tepat 3 digit dianggap desimal)
/// - `Rp 10.000` → 10000
double? parseIdNumber(String input) {
  var s = input.replaceAll(RegExp(r'[Rp\s]'), '');
  if (s.isEmpty) return null;
  if (s.contains(',')) {
    s = s.replaceAll('.', '').replaceAll(',', '.');
  } else if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(s)) {
    s = s.replaceAll('.', '');
  }
  return double.tryParse(s);
}

/// Format angka untuk ditampilkan di field: `2.0` → `2`, `0.5` → `0,5`.
String formatQty(double value) => Fmt.number(value);

/// Formatter untuk input Rupiah: hanya angka, ditampilkan dengan titik ribuan
/// saat diketik (`50000` → `50.000`).
class RupiahInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return const TextEditingValue();
    final formatted = Fmt.number(int.parse(digits));
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
