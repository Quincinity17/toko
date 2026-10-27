import 'package:flutter_test/flutter_test.dart';
import 'package:toko/features/sales/domain/day_total.dart';
import 'package:toko/features/sales/domain/sale.dart';

SaleSummary _sale(int id, int total, String method, {int? returnOf}) =>
    SaleSummary(
      id: id,
      invoiceNo: 'INV-$id',
      date: DateTime(2026, 10, 12, 8 + id),
      cashierName: 'Kasir',
      itemCount: 1,
      subtotal: total,
      discount: 0,
      total: total,
      paid: total,
      change: 0,
      paymentMethod: method,
      returnOfId: returnOf,
    );

void main() {
  test('total bersih per metode; nota retur memotong, tidak dihitung', () {
    // Terbaru dulu, seperti daftar Hari Ini.
    final t = DayTotal.of([
      _sale(4, -3000, 'Tunai', returnOf: 1),
      _sale(3, 7000, 'Tunai'),
      _sale(2, 5500, 'QRIS'),
      _sale(1, 10000, 'Tunai'),
    ]);
    expect(t.total, 19500);
    expect(t.transactions, 3);
    expect(t.byMethod, {'Tunai': 14000, 'QRIS': 5500});
    expect(t.byMethod.keys.first, 'Tunai'); // urut pertama kali dipakai
  });

  test('daftar kosong = nol', () {
    final t = DayTotal.of(const []);
    expect(t.total, 0);
    expect(t.transactions, 0);
    expect(t.byMethod, isEmpty);
  });
}
