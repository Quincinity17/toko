/// Barcode berikutnya untuk centang "Otomatis" di form barang:
/// BMM0000001 → BMM0000002.
///
/// Pola (awalan huruf + angka) mengikuti barang terbaru yang barcodenya
/// berakhiran angka, lalu diambil angka terbesar dengan awalan itu + 1.
/// Jumlah digit (nol di depan) dipertahankan. Dengan begitu barang contoh
/// (BRG001 …) tidak mengganggu setelah toko memakai pola sendiri.
///
/// Barcode yang seluruhnya angka (mis. EAN-13 pabrik) hanya dipakai bila
/// tidak ada barcode berawalan huruf, supaya nomor tidak melompat ke angka
/// pabrik.
abstract final class CodeSequence {
  static final _pattern = RegExp(r'^(.*?)(\d+)$');

  /// [newestFirst]: semua barcode (kode) barang, terbaru dulu. `null` bila
  /// belum ada barcode yang berakhiran angka.
  static ({String next, String basedOn})? next(List<String> newestFirst) {
    final parsed = [
      for (final code in newestFirst)
        if (_pattern.firstMatch(code.trim()) case final m?)
          (code: code.trim(), prefix: m[1]!, digits: m[2]!),
    ];
    if (parsed.isEmpty) return null;

    final pattern = parsed.firstWhere(
      (p) => p.prefix.isNotEmpty,
      orElse: () => parsed.first,
    );
    final prefix = pattern.prefix.toUpperCase();
    final sameSeries = parsed.where((p) => p.prefix.toUpperCase() == prefix);

    var best = pattern;
    for (final p in sameSeries) {
      if (BigInt.parse(p.digits) > BigInt.parse(best.digits)) best = p;
    }

    final taken = {for (final c in newestFirst) c.trim().toUpperCase()};
    var n = BigInt.parse(best.digits);
    String candidate;
    do {
      n += BigInt.one;
      candidate =
          '${pattern.prefix}${n.toString().padLeft(best.digits.length, '0')}';
    } while (taken.contains(candidate.toUpperCase()));
    return (next: candidate, basedOn: best.code);
  }
}
