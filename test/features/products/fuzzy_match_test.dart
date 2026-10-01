import 'package:flutter_test/flutter_test.dart';
import 'package:toko/features/products/domain/fuzzy_match.dart';

const names = [
  'Indomie Goreng 85g',
  'Indomie Ayam Bawang 69g',
  'Mie Sedaap Soto 75g',
  'Aqua Botol 600ml',
  'Teh Botol Sosro 450ml',
  'Chitato Sapi Panggang 68g',
  'Sabun Lifebuoy 110g',
  'Minyak Goreng Bimoli 2L',
  'Pepsodent 190g',
  'Rinso Anti Noda 770g',
];

List<String> suggest(String q) => FuzzyMatch.rank(q, names, (n) => n);

void main() {
  test('salah ketik satu huruf / tertukar', () {
    expect(suggest('indomei').take(2), [
      'Indomie Goreng 85g',
      'Indomie Ayam Bawang 69g',
    ]);
    expect(suggest('aqau').first, 'Aqua Botol 600ml');
    expect(suggest('chitatoo').first, 'Chitato Sapi Panggang 68g');
    expect(suggest('lifeboy').first, 'Sabun Lifebuoy 110g');
    expect(suggest('minyk goreng').first, 'Minyak Goreng Bimoli 2L');
  });

  test('beberapa kata dengan salah ketik', () {
    expect(suggest('teh botl').first, 'Teh Botol Sosro 450ml');
    expect(suggest('indomi goreng').first, 'Indomie Goreng 85g');
  });

  test('ditulis tanpa spasi', () {
    expect(suggest('indomiegoreng').first, 'Indomie Goreng 85g');
  });

  test('tidak ada yang mirip → kosong', () {
    expect(suggest('xyzq'), isEmpty);
    expect(suggest('kulkas'), isEmpty);
  });

  test('satu kata tidak mirip sama sekali membatalkan kecocokan', () {
    expect(FuzzyMatch.score('indomie kulkas', 'Indomie Goreng 85g'), 0);
  });
}
