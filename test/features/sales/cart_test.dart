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
    test('contoh dari layar iPOS: 2 barang, potongan 2%', () {
      final cart = const Cart()
          .add(product(1, 1500), qty: 5)
          .add(product(2, 1700), qty: 5)
          .setDiscount(DiscountType.percent, 2);
      expect(cart.subtotal, 16000);
      expect(cart.discount, 320);
      expect(cart.total, 15680);
    });

    test('barang yang sama digabung, bukan baris baru', () {
      final cart = const Cart()
          .add(product(1, 1000))
          .add(product(1, 1000), qty: 2);
      expect(cart.lines, hasLength(1));
      expect(cart.lines.single.qty, 3);
    });

    test('potongan per barang dan qty desimal dibulatkan ke Rupiah', () {
      final cart = const Cart()
          .add(product(1, 29000), qty: 0.75) // 21.750
          .add(product(2, 3333), qty: 3) // 9.999
          .setLineDiscount(1, 10); // 9.999 × 0,9 = 8.999,1 → 8.999
      expect(cart.lines[0].total, 21750);
      expect(cart.lines[1].total, 8999);
      expect(cart.subtotal, 30749);
    });

    test('potongan nominal tidak boleh melebihi subtotal', () {
      final cart = const Cart()
          .add(product(1, 5000))
          .setDiscount(DiscountType.amount, 999999);
      expect(cart.discount, 5000);
      expect(cart.total, 0);
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
