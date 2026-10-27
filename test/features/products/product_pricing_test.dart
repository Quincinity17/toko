import 'package:flutter_test/flutter_test.dart';
import 'package:toko/features/products/domain/product.dart';
import 'package:toko/features/products/domain/product_pricing.dart';
import 'package:toko/features/sales/domain/cart.dart';

void main() {
  const dus = ProductUnit(id: 7, name: 'DUS', factor: 24, price: 80000);
  const tiers = [
    PriceTier(minQty: 12, price: 3200),
    PriceTier(minQty: 6, price: 3400),
  ];
  const indomie = Product(
    id: 1,
    code: 'BRG001',
    name: 'Indomie',
    unitName: 'PCS',
    purchasePrice: 2800,
    sellingPrice: 3500,
    stock: 30,
    minStock: 0,
    units: [dus],
    tiers: tiers,
  );

  group('PricingRules', () {
    test('tierFor memilih jumlah minimal terbesar yang tercapai', () {
      expect(PricingRules.tierFor(tiers, 5), isNull);
      expect(PricingRules.tierFor(tiers, 6)?.price, 3400);
      expect(PricingRules.tierFor(tiers, 11.5)?.price, 3400);
      expect(PricingRules.tierFor(tiers, 12)?.price, 3200);
      expect(PricingRules.tierFor(tiers, 100)?.price, 3200);
    });

    test('satuan lain: nama, isi, barcode', () {
      String? check(List<ProductUnit> units) => PricingRules.units(
        units,
        baseUnit: 'PCS',
        code: 'BRG001',
        barcode: '8991',
      );
      expect(check([dus]), isNull);
      expect(
        check([const ProductUnit(name: 'pcs', factor: 2, price: 1)]),
        contains('sama dengan satuan dasar'),
      );
      expect(
        check([const ProductUnit(name: 'PAK', factor: 1, price: 1)]),
        contains('bukan 1'),
      );
      expect(
        check([dus, const ProductUnit(name: 'dus', factor: 12, price: 1)]),
        contains('lebih dari sekali'),
      );
      expect(
        check([
          const ProductUnit(
            name: 'PAK',
            factor: 5,
            price: 1,
            barcode: 'brg001',
          ),
        ]),
        contains('sama dengan barcode barang'),
      );
      expect(
        check([
          const ProductUnit(name: 'PAK', factor: 5, price: 1, barcode: 'A B'),
        ]),
        contains('spasi'),
      );
    });

    test('harga grosir harus > 1 dan lebih murah dari harga jual', () {
      expect(PricingRules.tiers(tiers, sellingPrice: 3500), isNull);
      expect(
        PricingRules.tiers([
          const PriceTier(minQty: 1, price: 3000),
        ], sellingPrice: 3500),
        contains('lebih dari 1'),
      );
      expect(
        PricingRules.tiers([
          const PriceTier(minQty: 6, price: 3500),
        ], sellingPrice: 3500),
        contains('lebih murah'),
      );
      expect(
        PricingRules.tiers([
          const PriceTier(minQty: 6, price: 3000),
          const PriceTier(minQty: 6, price: 2900),
        ], sellingPrice: 3500),
        contains('lebih dari sekali'),
      );
    });
  });

  group('Keranjang multi-satuan & grosir', () {
    test('harga grosir otomatis saat qty mencapai minimal', () {
      var cart = const Cart().add(indomie, qty: 5);
      expect(cart.lines.single.price, 3500);
      expect(cart.lines.single.nextTier?.minQty, 6);
      cart = cart.setQty(0, 6);
      expect(cart.lines.single.price, 3400);
      expect(cart.lines.single.tier?.minQty, 6);
      cart = cart.setQty(0, 12);
      expect(cart.total, 12 * 3200);
      expect(cart.lines.single.nextTier, isNull);
    });

    test('satuan DUS: harga DUS, stok & harga beli dikali isi', () {
      final cart = const Cart().add(indomie, qty: 2, unit: dus);
      final line = cart.lines.single;
      expect(line.price, 80000);
      expect(line.unitName, 'DUS');
      expect(line.baseQty, 48);
      expect(line.purchasePrice, 2800 * 24);
      expect(line.exceedsStock, isTrue); // stok 30 PCS < 48
      // Grosir hanya untuk satuan dasar.
      expect(line.tier, isNull);
    });

    test('PCS dan DUS jadi baris terpisah; ganti satuan menggabung', () {
      var cart = const Cart()
          .add(indomie, qty: 3)
          .add(indomie, unit: dus)
          .add(indomie, unit: dus);
      expect(cart.lines, hasLength(2));
      expect(cart.lines[1].qty, 2);
      cart = cart.setUnit(0, dus);
      expect(cart.lines, hasLength(1));
      expect(cart.lines.single.qty, 5);
      expect(cart.lines.single.unit?.id, 7);
      cart = cart.setUnit(0, null);
      expect(cart.lines.single.unit, isNull);
      expect(cart.lines.single.price, 3500); // 5 PCS: belum grosir (min. 6)
    });
  });

  test('grosir dihitung dari gabungan baris: 1 DUS + 2 PCS = 26 PCS', () {
    var cart = const Cart().add(indomie, qty: 2);
    expect(cart.lines.single.price, 3500);
    cart = cart.add(indomie, unit: dus);
    final pcs = cart.lines.firstWhere((l) => l.unit == null);
    expect(pcs.groupBaseQty, 26);
    expect(pcs.price, 3200); // min. 12
    // Baris DUS tetap harga DUS.
    expect(cart.lines.firstWhere((l) => l.unit != null).price, 80000);
    // DUS dihapus → kembali harga normal.
    cart = cart.removeAt(cart.indexOf(indomie, dus));
    expect(cart.lines.single.price, 3500);
  });
}
