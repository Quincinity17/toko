import 'package:flutter/widgets.dart';

/// Warna tag. Warna sistem Apple yang terbaca di mode terang dan gelap.
enum TagColor {
  blue('Biru', Color(0xFF007AFF)),
  purple('Ungu', Color(0xFFAF52DE)),
  pink('Merah muda', Color(0xFFFF2D55)),
  red('Merah', Color(0xFFFF3B30)),
  orange('Oranye', Color(0xFFFF9500)),
  yellow('Kuning', Color(0xFFD4A000)),
  green('Hijau', Color(0xFF34C759)),
  teal('Toska', Color(0xFF30B0C7)),
  brown('Cokelat', Color(0xFFA2845E)),
  gray('Abu-abu', Color(0xFF8E8E93));

  const TagColor(this.label, this.color);

  final String label;
  final Color color;

  static TagColor of(String? name) =>
      TagColor.values.asNameMap()[name] ?? TagColor.blue;
}

/// Tag jenis barang (mis. Mainan, Boneka, Alat Tulis). Satu barang bisa
/// punya banyak tag.
@immutable
class Tag {
  const Tag({
    required this.id,
    required this.name,
    this.color = TagColor.blue,
    this.productCount = 0,
  });

  final int id;
  final String name;
  final TagColor color;

  /// Jumlah barang yang memakai tag ini (hanya terisi di daftar tag).
  final int productCount;

  @override
  bool operator ==(Object other) =>
      other is Tag &&
      other.id == id &&
      other.name == name &&
      other.color == color &&
      other.productCount == productCount;

  @override
  int get hashCode => Object.hash(id, name, color, productCount);
}

/// Validasi nama tag.
class TagRules {
  const TagRules._();

  static const maxLength = 30;

  static String? name(String v) {
    final n = v.trim();
    if (n.isEmpty) return 'Nama tag wajib diisi.';
    if (n.length > maxLength) return 'Nama tag maksimal $maxLength karakter.';
    if (n.contains(',')) return 'Nama tag tidak boleh berisi koma.';
    return null;
  }

  /// Memecah teks "Mainan, Boneka" (kolom Tag di file import) menjadi nama.
  static List<String> split(String text) => [
    for (final t in text.split(RegExp(r'[,;]')))
      if (t.trim().isNotEmpty) t.trim(),
  ];
}
