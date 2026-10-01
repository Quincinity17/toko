import 'package:flutter/foundation.dart';

enum TerminalMode {
  /// Komputer utama: menyimpan data pusat, satu-satunya tempat admin
  /// mengubah data master. Sebelum ada server (Tahap B), setiap instalasi
  /// berjalan sebagai server mandiri.
  server('Server'),

  /// Komputer kasir lain yang tersambung ke server (Tahap C).
  client('Kasir cabang');

  const TerminalMode(this.label);

  final String label;
}

/// Identitas komputer ini.
@immutable
class Terminal {
  const Terminal({required this.id, required this.code, required this.mode});

  /// UUID, dibuat sekali saat aplikasi pertama kali jalan.
  final String id;

  /// Kode pendek di nomor faktur, mis. `K01` → `INV-K01-20261001-0001`.
  final String code;
  final TerminalMode mode;

  bool get isServer => mode == TerminalMode.server;

  static const defaultCode = 'K01';
  static final _codePattern = RegExp(r'^[A-Z0-9]{2,6}$');

  static String normalizeCode(String v) => v.trim().toUpperCase();

  /// Validasi kode terminal; `null` jika valid.
  static String? validateCode(String v) {
    final c = normalizeCode(v);
    if (!_codePattern.hasMatch(c)) {
      return 'Kode 2–6 huruf/angka tanpa spasi, mis. K01 atau PST.';
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is Terminal &&
      other.id == id &&
      other.code == code &&
      other.mode == mode;

  @override
  int get hashCode => Object.hash(id, code, mode);
}
