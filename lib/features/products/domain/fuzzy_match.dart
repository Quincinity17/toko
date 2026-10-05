import 'dart:math' as math;

/// Pencocokan nama "yang mendekati" untuk saran barang saat pencarian biasa
/// tidak menemukan apa pun, misalnya salah ketik `indomei` → Indomie,
/// `aqau` → Aqua, `lifeboy` → Lifebuoy.
///
/// Fungsi murni tanpa database supaya mudah dites.
class FuzzyMatch {
  const FuzzyMatch._();

  /// Skor minimal agar dianggap mirip (0–1).
  static const threshold = 0.7;

  /// Huruf kecil, selain huruf/angka jadi spasi: "Teh Botol 450ml" →
  /// ["teh", "botol", "450ml"].
  static List<String> tokens(String text) => text
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((t) => t.isNotEmpty)
      .toList();

  /// Kemiripan [query] dengan nama barang [name] (0–1). Setiap kata di query
  /// dicari padanan terbaiknya di nama, lalu dirata-rata.
  static double score(String query, String name) =>
      scoreTokens(tokens(query), tokens(name));

  /// [score] untuk kata yang sudah dipecah ([tokens]); dipakai saat
  /// membandingkan banyak nama supaya tidak memecah ulang.
  static double scoreTokens(List<String> q, List<String> n) {
    if (q.isEmpty || n.isEmpty) return 0;

    // Query yang ditulis tanpa spasi, mis. "indomiegoreng".
    final compactQ = q.join();
    final compactN = n.join();
    if (compactQ.length >= 4 && compactN.contains(compactQ)) return 0.95;

    var total = 0.0;
    for (final qt in q) {
      var best = 0.0;
      for (final nt in n) {
        best = math.max(best, tokenSimilarity(qt, nt));
        if (best == 1) break;
      }
      // Satu kata yang sama sekali tidak mirip membatalkan kecocokan.
      if (best < 0.5) return 0;
      total += best;
    }
    return total / q.length;
  }

  /// Kemiripan dua kata (0–1).
  static double tokenSimilarity(String a, String b) {
    if (a == b) return 1;
    // Kata pendek (mis. "2l", "5kg") harus sama persis.
    if (a.length <= 2 || b.length <= 2) return 0;
    // Awalan kata: "pepso" → "pepsodent".
    if (b.startsWith(a) || a.startsWith(b)) return 0.9;
    final d = _osaDistance(a, b);
    return 1 - d / math.max(a.length, b.length);
  }

  /// Jarak edit Damerau-Levenshtein (versi optimal string alignment):
  /// sisip, hapus, ganti, dan tukar dua huruf bersebelahan = 1 langkah.
  static int _osaDistance(String a, String b) {
    final m = a.length, n = b.length;
    var prev2 = List<int>.filled(n + 1, 0);
    var prev = List<int>.generate(n + 1, (j) => j);
    var curr = List<int>.filled(n + 1, 0);
    for (var i = 1; i <= m; i++) {
      curr[0] = i;
      for (var j = 1; j <= n; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        var v = math.min(
          math.min(prev[j] + 1, curr[j - 1] + 1),
          prev[j - 1] + cost,
        );
        if (i > 1 &&
            j > 1 &&
            a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
            a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
          v = math.min(v, prev2[j - 2] + 1);
        }
        curr[j] = v;
      }
      final t = prev2;
      prev2 = prev;
      prev = curr;
      curr = t;
    }
    return prev[n];
  }

  /// Mengurutkan [candidates] dari yang paling mirip dengan [query], hanya
  /// yang skornya ≥ [threshold], maksimal [limit].
  static List<T> rank<T>(
    String query,
    Iterable<T> candidates,
    String Function(T) nameOf, {
    int limit = 8,
  }) {
    final scored = <(T, double)>[];
    for (final c in candidates) {
      final s = score(query, nameOf(c));
      if (s >= threshold) scored.add((c, s));
    }
    scored.sort((x, y) => y.$2.compareTo(x.$2));
    return scored.take(limit).map((e) => e.$1).toList();
  }
}
