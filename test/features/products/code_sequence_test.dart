import 'package:flutter_test/flutter_test.dart';
import 'package:toko/features/products/domain/code_sequence.dart';

void main() {
  String? next(List<String> codes) => CodeSequence.next(codes)?.next;

  test('angka terakhir + 1, nol di depan dipertahankan', () {
    expect(next(['BMM0000001']), 'BMM0000002');
    expect(next(['BMM0000009']), 'BMM0000010');
    expect(next(['A99']), 'A100');
  });

  test('pola mengikuti barang terbaru; nomor terlewat diisi dulu', () {
    // Barang contoh BRG020 punya angka lebih besar, tetapi barang terbaru
    // memakai seri BMM. BMM0000004–6 belum dipakai → diisi dulu.
    final r = CodeSequence.next(['BMM0000003', 'BMM0000007', 'BRG020']);
    expect(r?.next, 'BMM0000004');
    expect(r?.basedOn, 'BMM0000003');
    expect(r?.fillsGap, isTrue);
    expect(r?.note, 'Mengisi nomor kosong setelah BMM0000003');
  });

  test('BRG019 lalu BRG025: isi BRG020–024 dulu, baru BRG026', () {
    final codes = [
      for (var i = 1; i <= 19; i++) 'BRG${i.toString().padLeft(3, '0')}',
      'BRG025',
    ];
    final got = <String>[];
    for (var i = 0; i < 6; i++) {
      final r = CodeSequence.next([...codes.reversed, ...got.reversed])!;
      got.add(r.next);
      expect(r.fillsGap, i < 5);
    }
    expect(got, ['BRG020', 'BRG021', 'BRG022', 'BRG023', 'BRG024', 'BRG026']);
  });

  test('seri mengikuti kategori; nomor seri lain dengan awalan sama '
      'tetap dianggap terpakai', () {
    final all = ['BRG020', 'MNN005', 'MNN003', 'BNK101', 'BNK100'];
    final r = CodeSequence.next(
      all,
      series: ['MNN005', 'MNN003'],
      category: 'Mainan',
    )!;
    expect(r.next, 'MNN004');
    expect(r.category, 'Mainan');
    expect(r.note, 'Mengisi nomor kosong setelah MNN003 · kategori Mainan');
    // Kategori Boneka mulai dari 100: tidak mengisi nomor di bawahnya.
    expect(
      CodeSequence.next(all, series: ['BNK101', 'BNK100'])!.next,
      'BNK102',
    );
    // Kategori tanpa barcode bernomor → seri barang terbaru.
    final none = CodeSequence.next(all, series: ['ABC'], category: 'Baru')!;
    expect(none.next, 'BRG021');
    expect(none.category, isNull);
  });

  test('barcode kemasan & isian lain ikut dianggap terpakai', () {
    expect(
      CodeSequence.next(['A1', 'A5'], alsoTaken: ['a2', 'A3'])!.next,
      'A4',
    );
  });

  test('awalan tanpa peduli huruf besar, hasil tidak bentrok', () {
    expect(next(['bmm0000005', 'BMM0000004']), 'bmm0000006');
    expect(next(['X1', 'X2', 'x3']), 'X4');
  });

  test('barcode pabrik (angka saja) diabaikan bila ada seri berawalan', () {
    expect(next(['8991234567890', 'BMM0000001']), 'BMM0000002');
    expect(next(['8991234567890']), '8991234567891');
  });

  test('tanpa barcode berakhiran angka → null', () {
    expect(next([]), isNull);
    expect(next(['GULA', 'KOPI-A']), isNull);
  });
}
