import 'package:flutter_test/flutter_test.dart';
import 'package:toko/features/sales/domain/day_total.dart';
import 'package:toko/features/sales/domain/sale.dart';
import 'package:toko/features/sales/domain/split_payment.dart';

void main() {
  const cash = PaymentPart(methodId: 1, name: 'Tunai', isCash: true, amount: 0);
  const qris = PaymentPart(methodId: 2, name: 'QRIS', isCash: false, amount: 0);
  const card = PaymentPart(
    methodId: 4,
    name: 'Kartu',
    isCash: false,
    amount: 0,
  );

  group('SplitPayment.settle', () {
    test('tunai menutup sisa, kelebihannya kembalian; tunai di depan', () {
      final r = SplitPayment.settle([
        qris.copyWith(amount: 30000),
        cash.copyWith(amount: 50000),
      ], 75000);
      expect(r.change, 5000);
      expect(r.parts.map((p) => (p.part.name, p.applied)), [
        ('Tunai', 45000),
        ('QRIS', 30000),
      ]);
    });

    test('tanpa tunai harus pas', () {
      final r = SplitPayment.settle([
        qris.copyWith(amount: 40000),
        card.copyWith(amount: 35000),
      ], 75000);
      expect(r.change, 0);
      expect(
        () => SplitPayment.settle([
          qris.copyWith(amount: 40000),
          card.copyWith(amount: 30000),
        ], 75000),
        throwsA(
          isA<SplitPaymentFailure>().having(
            (e) => e.message,
            'message',
            contains('kurang Rp 5.000'),
          ),
        ),
      );
    });

    test(
      'ditolak: satu metode, metode dobel, non-tunai lebih, tunai kurang',
      () {
        expect(
          () => SplitPayment.settle([cash.copyWith(amount: 9)], 5),
          throwsA(isA<SplitPaymentFailure>()),
        );
        expect(
          () => SplitPayment.settle([
            qris.copyWith(amount: 1),
            qris.copyWith(amount: 4),
          ], 5),
          throwsA(isA<SplitPaymentFailure>()),
        );
        expect(
          () => SplitPayment.settle([
            qris.copyWith(amount: 80000),
            cash.copyWith(amount: 1000),
          ], 75000),
          throwsA(
            isA<SplitPaymentFailure>().having(
              (e) => e.message,
              'message',
              contains('melebihi'),
            ),
          ),
        );
        expect(
          () => SplitPayment.settle([
            qris.copyWith(amount: 30000),
            cash.copyWith(amount: 40000),
          ], 75000),
          throwsA(
            isA<SplitPaymentFailure>().having(
              (e) => e.message,
              'message',
              contains('Uang tunai kurang Rp 5.000'),
            ),
          ),
        );
        expect(
          () => SplitPayment.settle([
            qris.copyWith(amount: 75000),
            cash.copyWith(amount: 1000),
          ], 75000),
          throwsA(isA<SplitPaymentFailure>()),
        );
      },
    );
  });

  test('uang kembali dibagi: tunai dulu, lalu metode lain', () {
    const remaining = [
      SalePart(methodId: 2, name: 'QRIS', amount: 30000, isCash: false),
      SalePart(methodId: 1, name: 'Tunai', amount: 45000, isCash: true),
    ];
    expect(
      SplitPayment.allocateRefund(
        remaining,
        20000,
      ).map((p) => (p.name, p.amount)),
      [('Tunai', -20000)],
    );
    expect(
      SplitPayment.allocateRefund(
        remaining,
        75000,
      ).map((p) => (p.name, p.amount)),
      [('Tunai', -45000), ('QRIS', -30000)],
    );
  });

  test('DayTotal membagi faktur split ke tiap metode', () {
    SaleSummary sale(
      int total,
      String method, {
      List<SalePart> parts = const [],
    }) => SaleSummary(
      id: total,
      invoiceNo: 'INV-$total',
      date: DateTime(2026, 10, 16),
      cashierName: 'Kasir',
      itemCount: 1,
      subtotal: total,
      discount: 0,
      total: total,
      paid: total,
      change: 0,
      paymentMethod: method,
      payments: parts,
    );
    final day = DayTotal.of([
      sale(
        75000,
        'Tunai + QRIS',
        parts: const [
          SalePart(name: 'Tunai', amount: 45000, isCash: true),
          SalePart(name: 'QRIS', amount: 30000, isCash: false),
        ],
      ),
      sale(10000, 'Tunai'),
    ]);
    expect(day.total, 85000);
    expect(day.byMethod, {'Tunai': 55000, 'QRIS': 30000});
  });
}
