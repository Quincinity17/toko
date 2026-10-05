import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/products.dart';
import '../tables/stores.dart';
import '../tables/users.dart';

part 'seals_dao.g.dart';

/// Segel (`Sealer`) baris akun, barang, dan stok/harga per toko. Dihitung
/// ulang oleh DAO setiap kali aplikasi menulis baris itu; diperiksa oleh
/// `IntegrityService` dan saat login (akun).
@DriftAccessor(tables: [Users, Products, StoreProducts])
class SealsDao extends DatabaseAccessor<AppDatabase> with _$SealsDaoMixin {
  SealsDao(super.attachedDatabase);

  // Kolom yang disegel. Mengubah daftar ini = semua segel lama tidak cocok:
  // tambahkan langkah `resealAll()` di migrasi.
  static List<Object?> userFields(UserRow u) => [
    u.id,
    u.username,
    u.role,
    u.storeId,
    u.isActive,
    u.passwordHash,
  ];

  static List<Object?> productFields(ProductRow p) => [
    p.id,
    p.code,
    p.purchasePrice,
    p.sellingPrice,
    p.isActive,
  ];

  static List<Object?> storeProductFields(StoreProductRow r) => [
    r.storeId,
    r.productId,
    r.stock,
    r.sellingPrice,
  ];

  String _seal(List<Object?> fields) => attachedDatabase.sealer.seal(fields);

  Future<void> resealUser(int id) async {
    final u = await (select(
      users,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (u == null) return;
    await (update(users)..where((t) => t.id.equals(id))).write(
      UsersCompanion(seal: Value(_seal(userFields(u)))),
    );
  }

  Future<void> resealProduct(int id) async {
    final p = await (select(
      products,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (p == null) return;
    await (update(products)..where((t) => t.id.equals(id))).write(
      ProductsCompanion(seal: Value(_seal(productFields(p)))),
    );
  }

  Future<void> resealStoreProduct(int storeId, int productId) async {
    final r =
        await (select(storeProducts)..where(
              (t) => t.storeId.equals(storeId) & t.productId.equals(productId),
            ))
            .getSingleOrNull();
    if (r == null) return;
    await (update(storeProducts)..where((t) => t.id.equals(r.id))).write(
      StoreProductsCompanion(seal: Value(_seal(storeProductFields(r)))),
    );
  }

  /// Menyegel ulang semua baris (database baru, migrasi, setelah memulihkan
  /// backup dari perangkat lain).
  Future<void> resealAll() => transaction(() async {
    for (final u in await select(users).get()) {
      await (update(users)..where((t) => t.id.equals(u.id))).write(
        UsersCompanion(seal: Value(_seal(userFields(u)))),
      );
    }
    for (final p in await select(products).get()) {
      await (update(products)..where((t) => t.id.equals(p.id))).write(
        ProductsCompanion(seal: Value(_seal(productFields(p)))),
      );
    }
    for (final r in await select(storeProducts).get()) {
      await (update(storeProducts)..where((t) => t.id.equals(r.id))).write(
        StoreProductsCompanion(seal: Value(_seal(storeProductFields(r)))),
      );
    }
  });
}
