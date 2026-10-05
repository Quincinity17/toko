import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:toko/features/products/domain/similar_names.dart';

void main() {
  const existing = [
    (name: 'Indomie Goreng 85g', code: 'BRG001'),
    (name: 'Aqua Botol 600ml', code: 'BRG009'),
    (name: 'Sabun Lifebuoy 110g', code: 'BRG015'),
  ];

  test('sama persis (tanpa peduli huruf besar/spasi) ditandai exact', () {
    final r = SimilarNames.find([(1, 'indomie  GORENG 85g')], existing);
    expect(r.first.exact, isTrue);
    expect(r.first.matchLabel, 'Indomie Goreng 85g (BRG001)');
  });

  test('mirip dua arah: lebih pendek, lebih panjang, salah ketik', () {
    expect(
      SimilarNames.find([(1, 'Indomie Goreng')], existing).single.match,
      'Indomie Goreng 85g',
    );
    expect(
      SimilarNames.find([
        (1, 'Aqua Botol 600ml Dingin'),
      ], existing).single.match,
      'Aqua Botol 600ml',
    );
    expect(
      SimilarNames.find([(1, 'Sabun Lifeboy')], existing).single.match,
      'Sabun Lifebuoy 110g',
    );
  });

  test('nama berbeda tidak ditandai', () {
    expect(
      SimilarNames.find([(1, 'Boneka Beruang'), (2, 'Mobil Remote')], existing),
      isEmpty,
    );
  });

  test('dobel di dalam tabel dilaporkan di baris yang lebih bawah', () {
    final r = SimilarNames.find([
      (1, 'Boneka Beruang'),
      (3, 'boneka beruang'),
    ], existing);
    expect(r.single.key, 3);
    expect(r.single.inTable, isTrue);
    expect(r.single.exact, isTrue);
    expect(r.single.matchLabel, 'baris 1: Boneka Beruang');
  });

  test('ribuan baris × ribuan barang tetap cepat', () {
    // Kosakata ±600 kata acak dari suku kata, nama 2–4 kata + ukuran.
    final rnd = Random(1);
    const syl = [
      'ka',
      'ra',
      'mi',
      'to',
      'su',
      'be',
      'li',
      'no',
      'pa',
      'de',
      'go',
      'ti',
      'ma',
      'ro',
      'se',
      'bu',
      'la',
      'ne',
      'ko',
      'ji',
    ];
    String word() => [
      for (var i = 0; i < 2 + rnd.nextInt(2); i++) syl[rnd.nextInt(syl.length)],
    ].join();
    final vocab = [for (var i = 0; i < 600; i++) word()];
    String name() => [
      for (var i = 0; i < 2 + rnd.nextInt(3); i++)
        vocab[rnd.nextInt(vocab.length)],
      '${(1 + rnd.nextInt(20)) * 50}g',
    ].join(' ');
    final existing = [
      for (var i = 0; i < 3000; i++) (name: name(), code: 'X$i'),
    ];
    final names = [for (var i = 0; i < 3000; i++) (i + 2, name())];
    final watch = Stopwatch()..start();
    SimilarNames.find(names, existing);
    watch.stop();
    // ignore: avoid_print
    print('3000 × 3000: ${watch.elapsedMilliseconds} ms');
    expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
  });
}
