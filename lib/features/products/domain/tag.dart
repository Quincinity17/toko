import 'package:flutter/widgets.dart';

/// Warna tag: salah satu dari 15 [values] (preset), atau warna bebas dari
/// color wheel / kode hex ([TagColor.custom]). Disimpan sebagai [name]:
/// nama preset (`red`) atau hex (`#FF8800`).
///
/// Chip tag diisi warna penuh supaya tag mudah dikenali dari warnanya saja.
@immutable
class TagColor {
  const TagColor._(this.name, this.label, this.color);

  /// Warna bebas. Bila sama persis dengan preset, dipakai preset itu.
  factory TagColor.custom(Color color) {
    final opaque = color.withAlpha(0xFF);
    for (final p in values) {
      if (p.color.toARGB32() == opaque.toARGB32()) return p;
    }
    final hex = hexOf(opaque);
    return TagColor._(hex, hex, opaque);
  }

  static const red = TagColor._('red', 'Merah', Color(0xFFFF3B30));
  static const orange = TagColor._('orange', 'Oranye', Color(0xFFFF9500));
  static const yellow = TagColor._('yellow', 'Kuning', Color(0xFFFFCC00));
  static const lime = TagColor._('lime', 'Hijau muda', Color(0xFF9ACD32));
  static const green = TagColor._('green', 'Hijau', Color(0xFF34C759));
  static const mint = TagColor._('mint', 'Mint', Color(0xFF00C7BE));
  static const teal = TagColor._('teal', 'Toska', Color(0xFF30B0C7));
  static const cyan = TagColor._('cyan', 'Biru muda', Color(0xFF32ADE6));
  static const blue = TagColor._('blue', 'Biru', Color(0xFF007AFF));
  static const indigo = TagColor._('indigo', 'Nila', Color(0xFF5856D6));
  static const purple = TagColor._('purple', 'Ungu', Color(0xFFAF52DE));
  static const pink = TagColor._('pink', 'Merah muda', Color(0xFFFF2D55));
  static const brown = TagColor._('brown', 'Cokelat', Color(0xFFA2845E));
  static const gray = TagColor._('gray', 'Abu-abu', Color(0xFF8E8E93));
  static const black = TagColor._('black', 'Hitam', Color(0xFF3A3A3C));

  /// Warna siap pakai, urut seperti di pemilih warna.
  static const values = [
    red, orange, yellow, lime, green, mint, teal, cyan, //
    blue, indigo, purple, pink, brown, gray, black,
  ];

  /// Kunci simpan: nama preset atau `#RRGGBB`.
  final String name;

  /// Nama warna (preset) atau kode hex (warna bebas).
  final String label;
  final Color color;

  bool get isCustom => name.startsWith('#');

  /// `#RRGGBB` huruf besar.
  String get hex => hexOf(color);

  static String hexOf(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  /// `#FF8800`, `FF8800`, atau `#F80` → warna; `null` bila tidak valid.
  static Color? parseHex(String text) {
    var h = text.trim().replaceFirst('#', '');
    if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
    if (h.length != 6 || !RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(h)) return null;
    return Color(0xFF000000 | int.parse(h, radix: 16));
  }

  /// Dari kunci simpan; tidak dikenal = biru.
  static TagColor of(String? name) {
    if (name == null) return blue;
    for (final p in values) {
      if (p.name == name) return p;
    }
    final c = parseHex(name);
    return c == null ? blue : TagColor.custom(c);
  }

  /// Warna teks di atas [color]: gelap untuk warna terang (kuning, hijau
  /// muda, mint), putih untuk lainnya.
  Color get onColor => color.computeLuminance() > 0.45
      ? const Color(0xFF1C1C1E)
      : const Color(0xFFFFFFFF);

  @override
  bool operator ==(Object other) => other is TagColor && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'TagColor($name)';
}

/// Kategori barang (mis. Mainan, Boneka, Alat Tulis); di kode dan database
/// disebut "tag". Satu barang bisa punya banyak kategori.
@immutable
class Tag {
  const Tag({
    required this.id,
    required this.name,
    this.color = TagColor.blue,
    this.productCount = 0,
    this.codePrefix,
    this.codeDigits,
  });

  final int id;
  final String name;
  final TagColor color;

  /// Awalan barcode otomatis barang di kategori ini (mis. BNK); `null` =
  /// mengikuti barcode barang di kategori itu.
  final String? codePrefix;

  /// Jumlah digit nomor barcode otomatis (mis. 4 → BNK0001); `null` =
  /// mengikuti seri yang sudah ada.
  final int? codeDigits;

  /// Jumlah barang yang memakai tag ini (hanya terisi di daftar tag).
  final int productCount;

  @override
  bool operator ==(Object other) =>
      other is Tag &&
      other.id == id &&
      other.name == name &&
      other.color == color &&
      other.productCount == productCount &&
      other.codePrefix == codePrefix &&
      other.codeDigits == codeDigits;

  @override
  int get hashCode =>
      Object.hash(id, name, color, productCount, codePrefix, codeDigits);
}

/// Validasi nama tag.
class TagRules {
  const TagRules._();

  static const maxLength = 30;

  static String? name(String v) {
    final n = v.trim();
    if (n.isEmpty) return 'Nama kategori wajib diisi.';
    if (n.length > maxLength) {
      return 'Nama kategori maksimal $maxLength karakter.';
    }
    if (n.contains(',')) return 'Nama kategori tidak boleh berisi koma.';
    return null;
  }

  /// Memecah teks "Mainan, Boneka" (kolom Kategori di file import) menjadi
  /// nama.
  static List<String> split(String text) => [
    for (final t in text.split(RegExp(r'[,;]')))
      if (t.trim().isNotEmpty) t.trim(),
  ];
}
