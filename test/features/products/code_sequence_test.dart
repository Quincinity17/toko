import 'package:flutter_test/flutter_test.dart';
import 'package:toko/features/products/domain/code_sequence.dart';

void main() {
  String? next(List<String> codes) => CodeSequence.next(codes)?.next;

  test('angka terakhir + 1, nol di depan dipertahankan', () {
    expect(next(['BMM0000001']), 'BMM0000002');
    expect(next(['BMM0000009']), 'BMM0000010');
    expect(next(['A99']), 'A100');
  });

  test('pola mengikuti barang terbaru, angka terbesar di seri itu', () {
    // Barang contoh BRG020 punya angka lebih besar, tetapi barang terbaru
    // memakai seri BMM.
    final r = CodeSequence.next(['BMM0000003', 'BMM0000007', 'BRG020']);
    expect(r?.next, 'BMM0000008');
    expect(r?.basedOn, 'BMM0000007');
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
