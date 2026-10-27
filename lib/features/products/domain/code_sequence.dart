import 'package:flutter/foundation.dart';

/// Hasil barcode otomatis.
@immutable
class CodeSuggestion {
  const CodeSuggestion({
    required this.next,
    this.basedOn,
    this.fillsGap = false,
    this.category,
  });

  final String next;

  /// Barcode tepat sebelum [next] di serinya (mis. BRG019 → BRG020);
  /// `null` = nomor pertama seri awalan kategori.
  final String? basedOn;

  /// [next] mengisi nomor yang terlewat (masih ada nomor lebih besar di
  /// seri itu).
  final bool fillsGap;

  /// Kategori yang menentukan seri; `null` = seri barang terbaru.
  final String? category;

  /// Keterangan di bawah kolom barcode.
  String get note =>
      '${basedOn == null
          ? 'Nomor pertama'
          : fillsGap
          ? 'Mengisi nomor kosong setelah $basedOn'
          : 'Lanjutan dari $basedOn'}'
      '${category == null ? '' : ' · kategori $category'}';
}

/// Barcode berikutnya untuk centang "Otomatis" di form barang dan tombol
/// Barcode Otomatis di Input Tabel.
///
/// **Seri** (awalan huruf + jumlah digit) diambil dari barcode barang di
/// kategori yang dipilih ([series]); bila kategori itu belum punya barcode
/// bernomor, dari barang terbaru ([newestFirst]). Barcode yang seluruhnya
/// angka (mis. EAN-13 pabrik) hanya dipakai bila tidak ada barcode
/// berawalan huruf.
///
/// **Nomor**: nomor terkecil yang belum dipakai, mulai setelah nomor
/// terkecil seri itu — jadi nomor yang terlewat (BRG019 → BRG025) diisi
/// dulu (BRG020 … BRG024), baru setelah itu melanjutkan nomor terbesar + 1.
/// "Dipakai" = barcode barang mana pun dengan awalan sama (tanpa peduli
/// huruf besar), ditambah [alsoTaken] (mis. barcode kemasan, isian tabel).
abstract final class CodeSequence {
  static final _pattern = RegExp(r'^(.*?)(\d+)$');

  static List<({String code, String prefix, String digits})> _parse(
    Iterable<String> codes,
  ) => [
    for (final code in codes)
      if (_pattern.firstMatch(code.trim()) case final m?)
        (code: code.trim(), prefix: m[1]!, digits: m[2]!),
  ];

  /// `null` bila belum ada barcode yang berakhiran angka.
  ///
  /// [minWidth] = jumlah digit minimal (diatur per kategori).
  ///
  /// [fixedPrefix] = awalan yang ditetapkan untuk kategori: seri = semua barcode
  /// berawalan itu; belum ada = nomor 1 dengan [defaultWidth] digit (bawaan:
  /// lebar seri barang terbaru, atau 4).
  static CodeSuggestion? next(
    List<String> newestFirst, {
    List<String> series = const [],
    String? category,
    String? fixedPrefix,
    int? defaultWidth,
    int? minWidth,
    Iterable<String> alsoTaken = const [],
  }) {
    final all = _parse([...newestFirst, ...alsoTaken]);
    if (fixedPrefix != null && fixedPrefix.trim().isNotEmpty) {
      final p = fixedPrefix.trim();
      final own = all.where((c) => c.prefix.toUpperCase() == p.toUpperCase());
      if (own.isEmpty) {
        final latest = _parse(newestFirst).where((c) => c.prefix.isNotEmpty);
        final width =
            minWidth ?? defaultWidth ?? latest.firstOrNull?.digits.length ?? 4;
        return CodeSuggestion(
          next: '$p${'1'.padLeft(width, '0')}',
          category: category,
        );
      }
      series = [for (final c in own) c.code];
    }
    final fromCategory = _parse(series);
    final source = fromCategory.isNotEmpty ? fromCategory : _parse(newestFirst);
    if (source.isEmpty) return null;

    final pattern = source.firstWhere(
      (p) => p.prefix.isNotEmpty,
      orElse: () => source.first,
    );
    final prefix = pattern.prefix.toUpperCase();
    bool same(({String code, String prefix, String digits}) p) =>
        p.prefix.toUpperCase() == prefix;

    // Rentang seri: dari nomor terkecil; lebar digit dari nomor terbesar.
    final inSeries = source.where(same).toList();
    var lowest = inSeries.first;
    var highest = inSeries.first;
    for (final p in inSeries) {
      final v = BigInt.parse(p.digits);
      if (v < BigInt.parse(lowest.digits)) lowest = p;
      if (v > BigInt.parse(highest.digits)) highest = p;
    }

    final used = <BigInt, String>{
      for (final p in all.where(same)) BigInt.parse(p.digits): p.code,
    };
    final takenCodes = {
      for (final c in [...newestFirst, ...alsoTaken]) c.trim().toUpperCase(),
    };
    // Jumlah digit kategori (bila diatur) = lebar minimal.
    final width = minWidth != null && minWidth > highest.digits.length
        ? minWidth
        : highest.digits.length;
    var n = BigInt.parse(lowest.digits);
    String candidate;
    do {
      n += BigInt.one;
      candidate = '${pattern.prefix}${n.toString().padLeft(width, '0')}';
    } while (used.containsKey(n) ||
        takenCodes.contains(candidate.toUpperCase()));

    final before = used[n - BigInt.one] ?? highest.code;
    return CodeSuggestion(
      next: candidate,
      basedOn: before,
      fillsGap: used.keys.any((v) => v > n),
      category: fromCategory.isEmpty ? null : category,
    );
  }
}
