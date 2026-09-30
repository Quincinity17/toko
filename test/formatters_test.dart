import 'package:flutter_test/flutter_test.dart';
import 'package:toko/core/utils/formatters.dart';

void main() {
  test('Format Rupiah memakai titik ribuan tanpa desimal', () {
    expect(Fmt.rupiah(10000), 'Rp 10.000');
    expect(Fmt.rupiah(0), 'Rp 0');
    expect(Fmt.rupiah(1250000), 'Rp 1.250.000');
  });
}
