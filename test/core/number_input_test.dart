import 'package:flutter_test/flutter_test.dart';
import 'package:toko/core/utils/formatters.dart';
import 'package:toko/core/utils/number_input.dart';

void main() {
  test('angka format Indonesia', () {
    expect(parseIdNumber('1.500'), 1500);
    expect(parseIdNumber('1.250.000'), 1250000);
    expect(parseIdNumber('Rp 10.000'), 10000);
    expect(parseIdNumber('0,5'), 0.5);
    expect(parseIdNumber('1.250,75'), 1250.75);
    expect(parseIdNumber('1.5'), 1.5);
    expect(parseIdNumber('12'), 12);
    expect(parseIdNumber(''), isNull);
    expect(parseIdNumber('abc'), isNull);
  });

  test('format ringkas dan persen', () {
    expect(Fmt.compact(950), '950');
    expect(Fmt.compact(12500), '12,5 rb');
    expect(Fmt.compact(1250000), '1,25 jt');
    expect(Fmt.compact(2000000000), '2 M');
    expect(Fmt.percent(0.1234), '12,3%');
  });
}
