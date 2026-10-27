import 'package:flutter_test/flutter_test.dart';
import 'package:toko/core/utils/scan_debouncer.dart';

void main() {
  test('kode sama selama masih di depan kamera tidak dihitung dua kali', () {
    var now = DateTime(2026, 10, 7, 10);
    final d = ScanDebouncer(clock: () => now);

    expect(d.accept('BRG001'), isTrue);
    now = now.add(const Duration(milliseconds: 200));
    expect(d.accept('BRG001'), isFalse); // masih terbaca terus
    now = now.add(const Duration(milliseconds: 1000));
    expect(d.accept('BRG001'), isFalse); // jeda dihitung dari bacaan terakhir

    // Barang lain langsung diterima.
    expect(d.accept('BRG009'), isTrue);

    // Barang pertama dijauhkan > 1,5 detik lalu di-scan lagi = tambah jumlah.
    now = now.add(const Duration(seconds: 2));
    expect(d.accept('BRG001'), isTrue);
  });
}
