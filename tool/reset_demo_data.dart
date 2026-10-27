// Mengosongkan barang & transaksi percobaan di database development lalu
// mengisi barang contoh berkategori dengan barcode sesuai awalan kategori.
//
// Jalankan (aplikasi harus ditutup):
//   fvm flutter test tool/reset_demo_data.dart
// Folder database bawaan = aplikasi macOS development; ganti lewat
// TOKO_DB_DIR=/path/ke/folder. Database & kunci dibackup dulu ke
// TOKO_BACKUP_DIR (bawaan: folder yang sama, subfolder reset-backup).
//
// Akun, toko, metode bayar, voucher, dan pengaturan TIDAK diubah.
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:toko/core/database/database_bootstrap.dart';
import 'package:toko/core/database/tables/audit.dart';
import 'package:toko/features/auth/domain/app_user.dart';
import 'package:toko/features/auth/domain/user_role.dart';
import 'package:toko/features/products/data/product_repository.dart';
import 'package:toko/features/products/data/tag_repository.dart';
import 'package:toko/features/products/domain/product.dart';
import 'package:toko/features/products/domain/product_pricing.dart';
import 'package:toko/features/products/domain/tag.dart';

typedef _Item = ({
  String name,
  String unit,
  int buy,
  int sell,
  double stock,
  double min,
  String? factory,
  List<ProductUnit> units,
  List<PriceTier> tiers,
});

_Item _i(
  String name,
  int buy,
  int sell, {
  String unit = 'PCS',
  double stock = 50,
  double min = 10,
  String? factory,
  List<ProductUnit> units = const [],
  List<PriceTier> tiers = const [],
}) => (
  name: name,
  unit: unit,
  buy: buy,
  sell: sell,
  stock: stock,
  min: min,
  factory: factory,
  units: units,
  tiers: tiers,
);

/// Kategori: (nama, warna, awalan, barang).
final _catalog = <(String, TagColor, String, List<_Item>)>[
  (
    'Makanan & Minuman',
    TagColor.orange,
    'MKN',
    [
      _i(
        'Indomie Goreng 85g',
        2800,
        3500,
        stock: 120,
        min: 24,
        factory: '089686010947',
        units: const [ProductUnit(name: 'DUS', factor: 40, price: 128000)],
        tiers: const [PriceTier(minQty: 10, price: 3300)],
      ),
      _i('Indomie Soto 70g', 2700, 3400, stock: 80, min: 24),
      _i(
        'Aqua Botol 600ml',
        3000,
        4000,
        unit: 'BTL',
        stock: 96,
        min: 24,
        units: const [ProductUnit(name: 'DUS', factor: 24, price: 84000)],
      ),
      _i('Teh Botol Sosro 450ml', 4200, 5500, unit: 'BTL', stock: 48),
      _i('Kopi Kapal Api 165g', 13500, 16000, stock: 20, min: 5),
      _i('Roti Tawar Sari Roti', 14000, 17500, stock: 12, min: 4),
    ],
  ),
  (
    'Kebutuhan Rumah',
    TagColor.teal,
    'RMH',
    [
      _i('Sabun Lifebuoy 85g', 3500, 4500, stock: 60),
      _i('Pasta Gigi Pepsodent 190g', 11000, 13500, stock: 30, min: 6),
      _i('Rinso Anti Noda 770g', 21000, 25000, stock: 18, min: 5),
      _i('Sunlight Jeruk Nipis 755ml', 14500, 17000, stock: 24, min: 6),
      _i('Tisu Paseo 250 lembar', 9000, 11500, stock: 3, min: 6),
    ],
  ),
  (
    'Alat Tulis',
    TagColor.blue,
    'ATK',
    [
      _i(
        'Pulpen Standard AE7 Hitam',
        1800,
        2500,
        stock: 144,
        min: 24,
        units: const [ProductUnit(name: 'LUSIN', factor: 12, price: 27000)],
        tiers: const [PriceTier(minQty: 12, price: 2250)],
      ),
      _i(
        'Buku Tulis Sidu 38 Lembar',
        2800,
        3500,
        stock: 200,
        min: 20,
        units: const [ProductUnit(name: 'PAK', factor: 10, price: 33000)],
      ),
      _i('Pensil 2B Faber-Castell', 3000, 4000, stock: 72),
      _i('Penghapus Joyko', 1500, 2000, stock: 60),
      _i('Spidol Snowman Hitam', 6000, 8000, stock: 0, min: 6),
    ],
  ),
  (
    'Mainan',
    TagColor.purple,
    'MNN',
    [
      _i('Mobil-mobilan Tarik', 15000, 25000, stock: 15, min: 3),
      _i('Yoyo Lampu', 5000, 10000, stock: 30, min: 5),
      _i('Puzzle Kayu Hewan', 18000, 30000, stock: 8, min: 2),
      _i('Bola Plastik Kecil', 4000, 7500, stock: 40, min: 10),
    ],
  ),
  (
    'Boneka',
    TagColor.pink,
    'BNK',
    [
      _i('Boneka Beruang 30cm', 35000, 55000, stock: 10, min: 2),
      _i('Boneka Kelinci 25cm', 30000, 48000, stock: 6, min: 2),
      _i('Boneka Kucing Mini', 12000, 20000, stock: 25, min: 5),
    ],
  ),
];

void main() {
  test('reset data contoh', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final dir = Directory(
      Platform.environment['TOKO_DB_DIR'] ??
          p.join(
            Platform.environment['HOME']!,
            'Library/Containers/id.toko.toko/Data/Library/'
                'Application Support/id.toko.toko',
          ),
    );
    final dbFile = File(p.join(dir.path, 'toko.sqlite'));
    if (!dbFile.existsSync()) fail('Database tidak ada: ${dbFile.path}');

    // 1. Backup dulu (database + kunci).
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-');
    final backup = Directory(
      Platform.environment['TOKO_BACKUP_DIR'] ??
          p.join(dir.path, 'reset-backup', stamp),
    )..createSync(recursive: true);
    for (final name in [
      'toko.sqlite',
      'toko.sqlite-wal',
      'toko.sqlite-shm',
      'toko.key',
    ]) {
      final f = File(p.join(dir.path, name));
      if (f.existsSync()) f.copySync(p.join(backup.path, name));
    }
    stdout.writeln('Backup: ${backup.path}');

    // 2. Buka dengan kunci perangkat (sama seperti aplikasi).
    final opened = await openDeviceDatabase(directory: () async => dir);
    if (opened is! DatabaseOpened) fail('Database tidak bisa dibuka.');
    final db = opened.db;

    // 3. Kosongkan barang, kategori, dan transaksi percobaan.
    await db.transaction(() async {
      for (final t in [
        'sale_payments',
        'sale_items',
        'stock_movements',
        'held_carts',
        'sync_outbox',
        'promo_actions',
        'remote_audit_log',
        'sales',
        'store_unit_prices',
        'price_tiers',
        'product_units',
        'product_tags',
        'store_products',
        'products',
        'categories',
        'tags',
        'units',
      ]) {
        await db.customStatement('DELETE FROM $t');
      }
      // Transaksi lama sudah dihapus: catatan aktivitas dimulai dari jangkar
      // baru supaya pemeriksaan keutuhan tidak melaporkannya.
      await db.sealsDao.resealAll();
      await db.auditDao.append(
        type: AuditType.sealsRebuilt,
        summary: 'Data contoh direset (barang & transaksi percobaan dihapus)',
      );
    });

    // 4. Isi barang contoh lewat repository (segel & catatan aktivitas).
    final adminRow = await (db.select(db.users)
          ..where((u) => u.role.equalsValue(UserRole.admin))
          ..limit(1))
        .getSingle();
    final admin = AppUser(
      id: adminRow.id,
      username: adminRow.username,
      fullName: adminRow.fullName,
      role: UserRole.admin,
    );
    final stores = await (db.select(
      db.stores,
    )..where((s) => s.isActive.equals(true))).get();
    final tags = TagRepository(db);
    final products = ProductRepository(db);
    var count = 0;
    for (final (category, color, prefix, items) in _catalog) {
      await tags.save(
        actor: admin,
        name: category,
        color: color,
        codePrefix: prefix,
        codeDigits: 4,
      );
      for (final (i, item) in items.indexed) {
        await products.save(
          actor: admin,
          draft: ProductDraft(
            code: '$prefix${'${i + 1}'.padLeft(4, '0')}',
            barcode: item.factory,
            name: item.name,
            unitName: item.unit,
            purchasePrice: item.buy,
            sellingPrice: item.sell,
            minStock: item.min,
            tagNames: [category],
            units: item.units,
            tiers: item.tiers,
          ),
          stores: [
            for (final s in stores)
              StoreProductValues(storeId: s.id, stock: item.stock),
          ],
        );
        count++;
      }
    }
    await db.close();
    stdout.writeln(
      'Selesai: $count barang di ${_catalog.length} kategori, '
      'stok di ${stores.length} toko.',
    );
  });
}
