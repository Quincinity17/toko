import 'package:flutter_test/flutter_test.dart';
import 'package:toko/features/products/domain/product.dart';
import 'package:toko/features/sales/domain/cart.dart';
import 'package:toko/features/sales/domain/cash_suggestions.dart';
import 'package:toko/features/sales/domain/invoice_number.dart';
import 'package:toko/features/vouchers/domain/voucher.dart';

Voucher voucher(
  VoucherType type,
  double value, {
  int? maxDiscount,
  int minPurchase = 0,
  DateTime? start,
  DateTime? end,
  int? quota,
  int used = 0,
}) => Voucher(
  id: 1,
  code: 'TES',
  type: type,
  value: value,
  maxDiscount: maxDiscount,
  minPurchase: minPurchase,
  startDate: start,
  endDate: end,
  quota: quota,
  usedCount: used,
);

Product product(int id, int price, {double stock = 100}) => Product(
  id: id,
  code: 'B$id',
  name: 'Barang $id',
  purchasePrice: price - 500,
  sellingPrice: price,
  stock: stock,
  minStock: 0,
);

void main() {
  group('Cart', () {
    test('subtotal dan total tanpa voucher', () {
      final cart = const Cart()
          .add(product(1, 1500), qty: 5)
          .add(product(2, 1700), qty: 5);
      expect(cart.subtotal, 16000);
      expect(cart.discount, 0);
      expect(cart.total, 16000);
    });

    test('barang yang sama digabung, bukan baris baru', () {
      final cart = const Cart()
          .add(product(1, 1000))
          .add(product(1, 1000), qty: 2);
      expect(cart.lines, hasLength(1));
      expect(cart.lines.single.qty, 3);
    });

    test('qty desimal dibulatkan ke Rupiah', () {
      final cart = const Cart().add(product(1, 3333), qty: 0.75);
      expect(cart.lines.single.total, 2500); // 2.499,75
    });

    test('qty 0 menghapus baris', () {
      final cart = const Cart().add(product(1, 5000)).setQty(0, 0);
      expect(cart.isEmpty, isTrue);
    });

    test('tanda stok kurang', () {
      final cart = const Cart().add(product(1, 5000, stock: 2), qty: 3);
      expect(cart.lines.single.exceedsStock, isTrue);
    });

    test('voucher persen dengan batas maksimal', () {
      final cart = const Cart()
          .add(product(1, 10000), qty: 10)
          .withVoucher(voucher(VoucherType.percent, 10, maxDiscount: 5000));
      expect(cart.discount, 5000); // 10% dari 100.000 = 10.000 → dibatasi
      expect(cart.total, 95000);
    });

    test('voucher belum berlaku sampai minimal belanja terpenuhi', () {
      var cart = const Cart()
          .add(product(1, 10000))
          .withVoucher(voucher(VoucherType.amount, 5000, minPurchase: 25000));
      expect(cart.voucherShortfall, 15000);
      expect(cart.discount, 0);
      cart = cart.setQty(0, 3);
      expect(cart.voucherShortfall, 0);
      expect(cart.discount, 5000);
    });

    test('voucher nominal tidak melebihi subtotal', () {
      final cart = const Cart()
          .add(product(1, 3000))
          .withVoucher(voucher(VoucherType.amount, 10000));
      expect(cart.discount, 3000);
      expect(cart.total, 0);
    });
  });

  group('Voucher', () {
    final now = DateTime(2026, 10, 15, 13);

    test('status mengikuti tanggal, kuota, dan aktif', () {
      expect(
        voucher(VoucherType.amount, 1000).statusAt(now),
        VoucherStatus.active,
      );
      expect(
        voucher(
          VoucherType.amount,
          1000,
          start: DateTime(2026, 10, 16),
        ).statusAt(now),
        VoucherStatus.scheduled,
      );
      // Berlaku sampai akhir hari tanggal berakhir.
      expect(
        voucher(
          VoucherType.amount,
          1000,
          end: DateTime(2026, 10, 15),
        ).statusAt(now),
        VoucherStatus.active,
      );
      expect(
        voucher(
          VoucherType.amount,
          1000,
          end: DateTime(2026, 10, 14),
        ).statusAt(now),
        VoucherStatus.expired,
      );
      expect(
        voucher(VoucherType.amount, 1000, quota: 2, used: 2).statusAt(now),
        VoucherStatus.exhausted,
      );
    });

    test('aturan isian form', () {
      expect(VoucherRules.code('hemat 10'), isNotNull);
      expect(VoucherRules.code('hemat10'), isNull);
      expect(VoucherRules.value(VoucherType.percent, 120), isNotNull);
      expect(VoucherRules.value(VoucherType.amount, 0), isNotNull);
      expect(VoucherRules.quota(3, 5), isNotNull);
      expect(
        VoucherRules.period(DateTime(2026, 10, 2), DateTime(2026, 10, 1)),
        isNotNull,
      );
    });
  });

  group('InvoiceNumber', () {
    final day = DateTime(2026, 9, 30, 14, 5);

    test('nomor pertama hari itu', () {
      expect(InvoiceNumber.next(day, null), 'INV-20260930-0001');
    });

    test('lanjut dari nomor terakhir', () {
      expect(InvoiceNumber.next(day, 'INV-20260930-0041'), 'INV-20260930-0042');
    });

    test('nomor hari lain diabaikan', () {
      expect(InvoiceNumber.next(day, 'INV-20260929-0099'), 'INV-20260930-0001');
    });
  });

  group('cashSuggestions', () {
    test('nominal pecahan di atas total', () {
      expect(cashSuggestions(15680), [16000, 20000, 50000, 100000]);
      expect(cashSuggestions(3500), [4000, 5000, 10000, 20000]);
      expect(cashSuggestions(20000), [50000, 100000]);
      expect(cashSuggestions(0), isEmpty);
    });
  });
}
