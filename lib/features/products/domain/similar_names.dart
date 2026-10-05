import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'fuzzy_match.dart';

/// Barang yang sudah ada, bahan pengecekan nama.
typedef NamedProduct = ({String name, String code});

/// Nama baru yang sama / mirip dengan barang lain.
@immutable
class SimilarName {
  const SimilarName({
    required this.key,
    required this.name,
    required this.match,
    this.matchCode,
    required this.exact,
  });

  /// Penanda nama baru (nomor baris tabel; 0 untuk form).
  final int key;
  final String name;

  /// Nama barang yang mirip.
  final String match;

  /// Barcode barang yang mirip; `null` = baris lain di tabel yang sama.
  final String? matchCode;
  final bool exact;

  bool get inTable => matchCode == null;

  /// "Indomie Goreng 85g (BRG001)" / "baris 4: Indomie Goreng".
  String get matchLabel => inTable ? match : '$match ($matchCode)';
}

/// Peringatan (bukan larangan) sebelum menyimpan barang baru: nama sama
/// persis atau mirip dengan barang yang sudah ada, atau dengan baris lain di
/// tabel. Dihitung sekali saat Simpan, bukan sambil mengetik.
abstract final class SimilarNames {
  /// Kemiripan dua arah: [FuzzyMatch.score] mencari kata nama pertama di nama
  /// kedua, jadi "Indomie Goreng" vs "Indomie Goreng 85g" hanya cocok satu
  /// arah.
  static double score(String a, String b) =>
      _score(FuzzyMatch.tokens(a), FuzzyMatch.tokens(b));

  static double _score(List<String> a, List<String> b) =>
      math.max(FuzzyMatch.scoreTokens(a, b), FuzzyMatch.scoreTokens(b, a));

  /// Kunci indeks: 2 huruf awal kata (kata ≤ 2 huruf utuh). Kata yang
  /// dianggap mirip ([FuzzyMatch.tokenSimilarity] ≥ 0,5) hampir selalu
  /// berawalan sama; salah ketik di 2 huruf pertama bisa terlewat (hanya
  /// peringatan).
  static Set<String> _keys(List<String> tokens) => {
    for (final t in tokens) t.length <= 2 ? t : t.substring(0, 2),
  };

  /// [names]: (penanda, nama baru). Maksimal [perName] kecocokan per nama,
  /// sama persis dulu lalu yang paling mirip.
  ///
  /// Supaya ribuan × ribuan nama tetap cepat, pasangan disaring lewat kunci
  /// paling jarang: agar A mirip B (arah A→B), SEMUA kata A harus punya
  /// padanan di B, termasuk kata A yang kuncinya paling jarang. Jadi
  /// pembanding untuk A = nama yang memuat kunci terjarang A, ditambah nama
  /// yang kunci terjarangnya ada di A (arah sebaliknya).
  static List<SimilarName> find(
    List<(int, String)> names,
    List<NamedProduct> existing, {
    int perName = 2,
  }) {
    final exTokens = [for (final p in existing) FuzzyMatch.tokens(p.name)];
    final exKeys = [for (final t in exTokens) _keys(t)];
    final nTokens = [for (final (_, n) in names) FuzzyMatch.tokens(n)];
    final nKeys = [for (final t in nTokens) _keys(t)];

    // Seberapa sering setiap kunci muncul (semua nama).
    final df = <String, int>{};
    for (final keys in [...exKeys, ...nKeys]) {
      for (final k in keys) {
        df[k] = (df[k] ?? 0) + 1;
      }
    }
    String? rarest(Set<String> keys) =>
        keys.isEmpty ? null : keys.reduce((a, b) => df[a]! <= df[b]! ? a : b);

    // Indeks barang: semua kunci, dan kunci terjarang saja.
    final exByKey = <String, List<int>>{};
    final exByRare = <String, List<int>>{};
    for (final (j, keys) in exKeys.indexed) {
      for (final k in keys) {
        (exByKey[k] ??= []).add(j);
      }
      if (rarest(keys) case final r?) (exByRare[r] ??= []).add(j);
    }
    // Indeks baris sebelumnya di tabel/file, diisi sambil jalan.
    final nByKey = <String, List<int>>{};
    final nByRare = <String, List<int>>{};

    Set<int> candidates(
      Set<String> keys,
      Map<String, List<int>> byKey,
      Map<String, List<int>> byRare,
    ) => {...?byKey[rarest(keys)], for (final k in keys) ...?byRare[k]};

    final result = <SimilarName>[];
    for (final (i, (key, name)) in names.indexed) {
      final tokens = nTokens[i];
      if (tokens.isEmpty) continue;
      final keys = nKeys[i];
      final norm = tokens.join(' ');
      final found = <(SimilarName, double)>[];

      void check(List<String> other, SimilarName Function(bool exact) make) {
        final exact = other.join(' ') == norm;
        final s = exact ? 1.0 : _score(tokens, other);
        if (exact || s >= FuzzyMatch.threshold) {
          found.add((make(exact), exact ? 2 : s));
        }
      }

      for (final j in candidates(keys, exByKey, exByRare)) {
        final p = existing[j];
        check(
          exTokens[j],
          (exact) => SimilarName(
            key: key,
            name: name,
            match: p.name,
            matchCode: p.code,
            exact: exact,
          ),
        );
      }
      // Baris sebelumnya (setiap pasangan dilaporkan sekali, di baris yang
      // lebih bawah).
      for (final o in candidates(keys, nByKey, nByRare).toList()..sort()) {
        final (otherKey, other) = names[o];
        check(
          nTokens[o],
          (exact) => SimilarName(
            key: key,
            name: name,
            match: 'baris $otherKey: $other',
            exact: exact,
          ),
        );
      }
      for (final k in keys) {
        (nByKey[k] ??= []).add(i);
      }
      if (rarest(keys) case final r?) (nByRare[r] ??= []).add(i);

      found.sort((a, b) => b.$2.compareTo(a.$2));
      result.addAll(found.take(perName).map((f) => f.$1));
    }
    return result;
  }
}
