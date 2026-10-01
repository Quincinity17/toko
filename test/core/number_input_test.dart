import 'package:flutter_test/flutter_test.dart';
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
}
