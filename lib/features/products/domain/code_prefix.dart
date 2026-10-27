/// Awalan barcode otomatis per kategori (mis. Boneka → BNK → BNK0001).
abstract final class CodePrefix {
  static const maxLength = 8;
  static final _valid = RegExp(r'^[A-Z][A-Z0-9-]*$');
  static final _code = RegExp(r'^(.*?)(\d+)$');

  /// Disimpan huruf besar tanpa spasi; kosong = `null`.
  static String? normalize(String? v) {
    final t = v?.trim().toUpperCase() ?? '';
    return t.isEmpty ? null : t;
  }

  /// Pesan error atau `null`. Awalan tidak boleh diakhiri angka (angka di
  /// ujung barcode adalah nomor urutnya).
  static String? validate(String? v) {
    final p = normalize(v);
    if (p == null) return null;
    if (p.length < 2) return 'Awalan barcode minimal 2 huruf.';
    if (p.length > maxLength) {
      return 'Awalan barcode maksimal $maxLength karakter.';
    }
    if (!_valid.hasMatch(p)) {
      return 'Awalan barcode diawali huruf, hanya huruf/angka/tanda -.';
    }
    if (RegExp(r'\d$').hasMatch(p)) {
      return 'Awalan barcode tidak boleh diakhiri angka.';
    }
    return null;
  }

  /// Awalan huruf dari barcode (BRG001 → BRG); `null` bila tidak bernomor
  /// atau angka saja.
  static String? of(String code) {
    final m = _code.firstMatch(code.trim());
    final p = m?[1]?.toUpperCase() ?? '';
    return p.isEmpty ? null : p;
  }

  /// Saran awalan untuk kategori [name], terbaik dulu (maks. [limit]):
  /// 1. awalan yang sudah paling banyak dipakai barang di kategori itu
  ///    ([categoryCodes]);
  /// 2. singkatan nama: huruf depan tiap kata (Alat Tulis Kantor → ATK),
  ///    atau huruf pertama + konsonan (Boneka → BNK, Minuman → MNM);
  /// 3. variasi 4 huruf bila yang pendek sudah terpakai.
  /// Awalan di [taken] (kategori lain / seri barang lain) dilewati.
  static List<String> suggest(
    String name, {
    Iterable<String> categoryCodes = const [],
    Iterable<String> taken = const [],
    int limit = 3,
  }) {
    final used = {for (final t in taken) t.toUpperCase()};
    final out = <String>[];
    void add(String? p) {
      if (p == null || out.contains(p) || used.contains(p)) return;
      if (validate(p) != null) return;
      out.add(p);
    }

    // 1. Awalan yang sudah dipakai di kategori ini.
    final counts = <String, int>{};
    for (final c in categoryCodes) {
      if (of(c) case final p?) counts[p] = (counts[p] ?? 0) + 1;
    }
    final ranked = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    ranked.forEach(add);

    final words = name
        .toUpperCase()
        .split(RegExp(r'[^A-Z0-9]+'))
        .where((w) => w.isNotEmpty && RegExp(r'^[A-Z]').hasMatch(w))
        .toList();
    if (words.isEmpty) return out.take(limit).toList();

    String consonants(String w, int length) {
      final buf = StringBuffer(w[0]);
      for (final ch in w.substring(1).split('')) {
        if (buf.length >= length) break;
        if (!'AEIOU'.contains(ch) && RegExp('[A-Z]').hasMatch(ch)) {
          buf.write(ch);
        }
      }
      // Konsonan kurang (mis. KOPI → KP): lengkapi dengan huruf berikutnya.
      for (final ch in w.substring(1).split('')) {
        if (buf.length >= length) break;
        if (!buf.toString().substring(1).contains(ch)) buf.write(ch);
      }
      return buf.toString();
    }

    // 2. Singkatan.
    if (words.length >= 2) {
      final initials = words.take(4).map((w) => w[0]).join();
      add(
        initials.length >= 3
            ? initials
            : initials + consonants(words.last, 2).substring(1),
      );
      add(words.first[0] + consonants(words.last, 2));
    }
    add(consonants(words.first, 3));
    add(words.first.length >= 3 ? words.first.substring(0, 3) : null);

    // 3. Variasi 4 huruf.
    add(consonants(words.first, 4));
    if (words.length >= 2) {
      add(consonants(words.first, 2) + consonants(words[1], 2));
    }
    add(words.first.length >= 4 ? words.first.substring(0, 4) : null);
    // Terakhir: tambah huruf X, Y, Z.
    for (final suffix in ['X', 'Y', 'Z']) {
      if (out.length >= limit) break;
      add(consonants(words.first, 3) + suffix);
    }
    return out.take(limit).toList();
  }
}
