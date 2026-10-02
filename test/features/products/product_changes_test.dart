import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:toko/features/products/domain/product.dart';
import 'package:toko/features/products/domain/product_changes.dart';
import 'package:toko/features/products/domain/tag.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  const before = Product(
    id: 1,
    code: 'BRG001',
    name: 'Indomie Goreng 85g',
    categoryName: 'Makanan',
    unitName: 'PCS',
    purchasePrice: 2800,
    sellingPrice: 3500,
    stock: 120,
    minStock: 24,
    tags: [
      Tag(id: 1, name: 'Laris'),
      Tag(id: 2, name: 'Sarapan'),
    ],
  );
  const same = ProductDraft(
    code: 'BRG001',
    name: 'Indomie Goreng 85g',
    categoryName: 'Makanan',
    unitName: 'pcs',
    purchasePrice: 2800,
    sellingPrice: 3500,
    minStock: 24,
    tagNames: ['sarapan', 'Laris'],
  );
  const stores = {1: (stock: 120.0, price: null), 2: (stock: 5.0, price: 4000)};

  List<FieldChange> diff(
    ProductDraft after, [
    List<StoreProductValues> afterStores = const [
      StoreProductValues(storeId: 1, stock: 120),
      StoreProductValues(storeId: 2, stock: 5, price: 4000),
    ],
  ]) => productChanges(
    before: before,
    beforeStores: stores,
    after: after,
    afterStores: afterStores,
    storeNames: {1: 'Toko Utama', 2: 'Toko B'},
  );

  test('isian sama (beda huruf besar satuan / urutan tag) = tidak berubah', () {
    expect(diff(same), isEmpty);
  });

  test('perubahan ditampilkan lama → baru', () {
    final changes = diff(
      const ProductDraft(
        code: 'BRG001',
        name: 'Indomie Goreng Jumbo',
        barcode: '899',
        categoryName: null,
        unitName: 'PCS',
        purchasePrice: 2800,
        sellingPrice: 3700,
        minStock: 24,
        isActive: false,
        tagNames: ['Laris'],
      ),
      const [
        StoreProductValues(storeId: 1, stock: 100),
        StoreProductValues(storeId: 2, stock: 5, price: 3700),
      ],
    );
    expect(changes.map((c) => c.toString()), [
      'Nama: Indomie Goreng 85g → Indomie Goreng Jumbo',
      'Barcode: – → 899',
      'Kategori: Makanan → Tanpa kategori',
      'Harga jual: Rp 3.500 → Rp 3.700',
      'Status: Aktif → Nonaktif',
      'Tag: Laris, Sarapan → Laris',
      'Stok Toko Utama: 120 PCS → 100 PCS',
      // Harga khusus = harga default baru → disimpan sebagai harga default.
      'Harga Toko B: Rp 4.000 → Harga default',
    ]);
  });

  test('tagNames null = tag tidak dibandingkan', () {
    const draft = ProductDraft(
      code: 'BRG001',
      name: 'Indomie Goreng 85g',
      categoryName: 'Makanan',
      unitName: 'PCS',
      purchasePrice: 2800,
      sellingPrice: 3500,
      minStock: 24,
    );
    expect(diff(draft), isEmpty);
  });

  group('TagColor', () {
    test('preset dan warna hex bebas', () {
      expect(TagColor.of('pink'), TagColor.pink);
      final custom = TagColor.of('#ff8800');
      expect(custom.isCustom, isTrue);
      expect(custom.name, '#FF8800');
      expect(custom.color, const Color(0xFFFF8800));
      expect(custom.label, '#FF8800');
      expect(TagColor.of(custom.name), custom);
      // Warna bebas yang sama dengan preset = preset itu.
      expect(TagColor.custom(const Color(0xFFFF3B30)), TagColor.red);
      expect(TagColor.of('ngawur'), TagColor.blue);
      expect(TagColor.parseHex('#0f8'), const Color(0xFF00FF88));
      expect(TagColor.parseHex('12345'), isNull);
    });

    test('teks chip kontras otomatis', () {
      expect(TagColor.yellow.onColor, const Color(0xFF1C1C1E));
      expect(
        TagColor.custom(const Color(0xFF102030)).onColor,
        const Color(0xFFFFFFFF),
      );
      expect(
        TagColor.custom(const Color(0xFFF0F0E0)).onColor,
        const Color(0xFF1C1C1E),
      );
    });
  });
}
