import 'package:drift/drift.dart';

import 'app_database.dart';

/// 20 barang contoh untuk toko baru. Dimasukkan sekali saja, saat database
/// dibuat atau di-upgrade ke v2, jadi tidak muncul lagi bila sudah dihapus.
Future<void> insertSampleProducts(AppDatabase db) async {
  // dart format off
  const data = [
    // kode, nama, kategori, satuan, harga beli, harga jual, stok, stok min, ada barcode
    ('BRG001', 'Indomie Goreng 85g', 'Makanan', 'PCS', 2800, 3500, 120.0, 24.0, true),
    ('BRG002', 'Indomie Ayam Bawang 69g', 'Makanan', 'PCS', 2700, 3300, 96.0, 24.0, true),
    ('BRG003', 'Mie Sedaap Soto 75g', 'Makanan', 'PCS', 2600, 3200, 80.0, 24.0, true),
    ('BRG004', 'Roti Tawar Sari Roti', 'Makanan', 'PCS', 14500, 17000, 8.0, 4.0, true),
    ('BRG005', 'Beras Pandan Wangi 5kg', 'Sembako', 'SAK', 68000, 76000, 15.0, 5.0, true),
    ('BRG006', 'Gula Pasir Gulaku 1kg', 'Sembako', 'PCS', 15500, 17500, 30.0, 10.0, true),
    ('BRG007', 'Minyak Goreng Bimoli 2L', 'Sembako', 'PCS', 34000, 38500, 4.0, 6.0, true),
    ('BRG008', 'Telur Ayam', 'Sembako', 'KG', 26000, 29000, 12.5, 5.0, false),
    ('BRG009', 'Aqua Botol 600ml', 'Minuman', 'BTL', 2800, 3500, 48.0, 24.0, true),
    ('BRG010', 'Teh Botol Sosro 450ml', 'Minuman', 'BTL', 4200, 5500, 36.0, 12.0, true),
    ('BRG011', 'Kopi Kapal Api Special Mix', 'Minuman', 'SCT', 1250, 1500, 200.0, 50.0, true),
    ('BRG012', 'Ultra Milk Coklat 250ml', 'Minuman', 'PCS', 5200, 6500, 3.0, 12.0, true),
    ('BRG013', 'Chitato Sapi Panggang 68g', 'Snack', 'PCS', 9500, 11500, 20.0, 6.0, true),
    ('BRG014', 'Oreo Original 133g', 'Snack', 'PCS', 8200, 9800, 18.0, 6.0, true),
    ('BRG015', 'Sabun Lifebuoy 110g', 'Perawatan Diri', 'PCS', 3800, 4800, 40.0, 12.0, true),
    ('BRG016', 'Shampoo Pantene 170ml', 'Perawatan Diri', 'BTL', 22000, 26500, 10.0, 4.0, true),
    ('BRG017', 'Pepsodent 190g', 'Perawatan Diri', 'PCS', 11000, 13500, 25.0, 8.0, true),
    ('BRG018', 'Rinso Anti Noda 770g', 'Kebutuhan Rumah', 'PCS', 21000, 24500, 2.0, 5.0, true),
    ('BRG019', 'Sunlight Jeruk Nipis 755ml', 'Kebutuhan Rumah', 'PCS', 14000, 16500, 14.0, 5.0, true),
    ('BRG020', 'Tisu Paseo 250 Sheet', 'Kebutuhan Rumah', 'PCS', 12500, 15000, 22.0, 6.0, true),
  ];
  // dart format on

  final categoryIds = <String, int>{};
  final unitIds = <String, int>{};
  for (final d in data) {
    categoryIds[d.$3] ??= await db
        .into(db.categories)
        .insert(CategoriesCompanion.insert(name: d.$3));
    unitIds[d.$4] ??= await db
        .into(db.units)
        .insert(UnitsCompanion.insert(name: d.$4));
  }

  await db.batch((b) {
    for (var i = 0; i < data.length; i++) {
      final d = data[i];
      b.insert(
        db.products,
        ProductsCompanion.insert(
          code: d.$1,
          name: d.$2,
          barcode: Value(d.$9 ? sampleBarcode(i + 1) : null),
          categoryId: Value(categoryIds[d.$3]),
          unitId: Value(unitIds[d.$4]),
          purchasePrice: Value(d.$5),
          sellingPrice: Value(d.$6),
          stock: Value(d.$7),
          minStock: Value(d.$8),
        ),
      );
    }
  });
}

/// Barcode EAN-13 contoh (`8991234` + nomor urut + check digit yang valid).
String sampleBarcode(int n) {
  final base = '8991234${n.toString().padLeft(5, '0')}';
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    sum += int.parse(base[i]) * (i.isEven ? 1 : 3);
  }
  return '$base${(10 - sum % 10) % 10}';
}

/// Tag contoh untuk barang contoh (warna = nama `TagColor`). Hanya dibuat
/// bila belum ada tag sama sekali, dan hanya dipasang ke barang contoh yang
/// masih ada — jadi aman untuk database yang sudah dipakai.
Future<void> insertSampleTags(AppDatabase db) async {
  final hasTags = await (db.select(db.tags)..limit(1)).getSingleOrNull();
  if (hasTags != null) return;

  // dart format off
  const tags = [
    ('Laris', 'red'),
    ('Promo', 'orange'),
    ('Anak-anak', 'pink'),
    ('Sarapan', 'yellow'),
    ('Kebutuhan Pokok', 'green'),
    ('Dingin', 'cyan'),
    ('Mandi & Cuci', 'blue'),
  ];
  const assign = {
    'BRG001': ['Laris', 'Sarapan'],
    'BRG002': ['Laris'],
    'BRG003': ['Promo'],
    'BRG004': ['Sarapan'],
    'BRG005': ['Kebutuhan Pokok', 'Laris'],
    'BRG006': ['Kebutuhan Pokok'],
    'BRG007': ['Kebutuhan Pokok', 'Promo'],
    'BRG008': ['Kebutuhan Pokok', 'Sarapan'],
    'BRG009': ['Dingin', 'Laris'],
    'BRG010': ['Dingin'],
    'BRG011': ['Sarapan', 'Laris'],
    'BRG012': ['Anak-anak', 'Dingin'],
    'BRG013': ['Anak-anak', 'Promo'],
    'BRG014': ['Anak-anak'],
    'BRG015': ['Mandi & Cuci'],
    'BRG016': ['Mandi & Cuci', 'Promo'],
    'BRG017': ['Mandi & Cuci'],
    'BRG018': ['Mandi & Cuci', 'Kebutuhan Pokok'],
    'BRG019': ['Mandi & Cuci'],
  };
  // dart format on

  final products = await (db.select(
    db.products,
  )..where((p) => p.code.isIn(assign.keys))).get();
  if (products.isEmpty) return; // barang contoh sudah dihapus semua

  final ids = <String, int>{};
  for (final (name, color) in tags) {
    ids[name] = await db
        .into(db.tags)
        .insert(TagsCompanion.insert(name: name, color: Value(color)));
  }
  await db.batch((b) {
    for (final p in products) {
      for (final name in assign[p.code]!) {
        b.insert(
          db.productTags,
          ProductTagsCompanion.insert(productId: p.id, tagId: ids[name]!),
        );
      }
    }
  });
}
