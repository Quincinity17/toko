import 'package:flutter_test/flutter_test.dart';
import 'package:toko/features/products/domain/product.dart';
import 'package:toko/features/sales/domain/cart.dart';
import 'package:toko/features/sales/domain/cash_suggestions.dart';
import 'package:toko/features/sales/domain/invoice_number.dart';

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
    test('subtotal dan total', () {
      final cart = const Cart()
          .add(product(1, 1500), qty: 5)
          .add(product(2, 1700), qty: 5);
      expect(cart.subtotal, 16000);
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
  });

  group('InvoiceNumber', () {
    final day = DateTime(2026, 9, 30, 14, 5);

    test('nomor pertama hari itu memuat kode terminal', () {
      expect(InvoiceNumber.next(day, 'K01', null), 'INV-K01-20260930-0001');
    });

    test('lanjut dari nomor terakhir terminal yang sama', () {
      expect(
        InvoiceNumber.next(day, 'K01', 'INV-K01-20260930-0041'),
        'INV-K01-20260930-0042',
      );
    });

    test('nomor hari lain, terminal lain, atau format lama diabaikan', () {
      expect(
        InvoiceNumber.next(day, 'K01', 'INV-K01-20260929-0099'),
        'INV-K01-20260930-0001',
      );
      expect(
        InvoiceNumber.next(day, 'K01', 'INV-K02-20260930-0099'),
        'INV-K01-20260930-0001',
      );
      expect(
        InvoiceNumber.next(day, 'K01', 'INV-20260930-0099'),
        'INV-K01-20260930-0001',
      );
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
