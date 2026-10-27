import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/products.dart';
import '../tables/role_permissions.dart';
import '../tables/stores.dart';
import '../tables/users.dart';
import 'role_permissions_dao.dart';

part 'seals_dao.g.dart';

/// Segel (`Sealer`) baris akun, barang, dan stok/harga per toko. Dihitung
/// ulang oleh DAO setiap kali aplikasi menulis baris itu; diperiksa oleh
/// `IntegrityService` dan saat login (akun).
@DriftAccessor(
  tables: [
    Users,
    Products,
    StoreProducts,
    RolePermissions,
    ProductUnits,
    PriceTiers,
    StoreUnitPrices,
  ],
)
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

  static List<Object?> productUnitFields(ProductUnitRow r) => [
    r.id,
    r.productId,
    r.name,
    r.factor,
    r.sellingPrice,
  ];

  static List<Object?> priceTierFields(PriceTierRow r) => [
    r.id,
    r.productId,
    r.minQty,
    r.price,
    r.storeId,
  ];

  static List<Object?> storeUnitPriceFields(StoreUnitPriceRow r) => [
    r.storeId,
    r.productUnitId,
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

  /// Satuan lain & harga grosir barang [productId] (setelah diganti).
  Future<void> resealPricing(int productId) async {
    for (final r in await (select(
      productUnits,
    )..where((t) => t.productId.equals(productId))).get()) {
      await (update(productUnits)..where((t) => t.id.equals(r.id))).write(
        ProductUnitsCompanion(seal: Value(_seal(productUnitFields(r)))),
      );
    }
    for (final r in await (select(
      priceTiers,
    )..where((t) => t.productId.equals(productId))).get()) {
      await (update(priceTiers)..where((t) => t.id.equals(r.id))).write(
        PriceTiersCompanion(seal: Value(_seal(priceTierFields(r)))),
      );
    }
    for (final r in await customSelect(
      'SELECT sup.* FROM store_unit_prices sup JOIN product_units pu '
      'ON pu.id = sup.product_unit_id WHERE pu.product_id = ?',
      variables: [Variable.withInt(productId)],
      readsFrom: {storeUnitPrices, productUnits},
    ).map((r) => storeUnitPrices.map(r.data)).get()) {
      await (update(storeUnitPrices)..where((t) => t.id.equals(r.id))).write(
        StoreUnitPricesCompanion(seal: Value(_seal(storeUnitPriceFields(r)))),
      );
    }
  }

  Future<void> resealRolePermission(int id) async {
    final r = await (select(
      rolePermissions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (r == null) return;
    await (update(rolePermissions)..where((t) => t.id.equals(id))).write(
      RolePermissionsCompanion(
        seal: Value(_seal(RolePermissionsDao.fields(r))),
      ),
    );
  }

  Future<bool> _hasTable(String name) async => (await customSelect(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
    variables: [Variable.withString(name)],
  ).get()).isNotEmpty;

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
    // Migrasi v12 (dari v11) berjalan sebelum tabel hak akses v14 dan
    // tabel harga v16 dibuat.
    if (await _hasTable('role_permissions')) {
      for (final r in await select(rolePermissions).get()) {
        await (update(rolePermissions)..where((t) => t.id.equals(r.id))).write(
          RolePermissionsCompanion(
            seal: Value(_seal(RolePermissionsDao.fields(r))),
          ),
        );
      }
    }
    if (await _hasTable('product_units')) {
      for (final r in await select(productUnits).get()) {
        await (update(productUnits)..where((t) => t.id.equals(r.id))).write(
          ProductUnitsCompanion(seal: Value(_seal(productUnitFields(r)))),
        );
      }
    }
    if (await _hasTable('store_unit_prices')) {
      for (final r in await select(storeUnitPrices).get()) {
        await (update(storeUnitPrices)..where((t) => t.id.equals(r.id))).write(
          StoreUnitPricesCompanion(seal: Value(_seal(storeUnitPriceFields(r)))),
        );
      }
    }
    if (await _hasTable('price_tiers')) {
      for (final r in await select(priceTiers).get()) {
        await (update(priceTiers)..where((t) => t.id.equals(r.id))).write(
          PriceTiersCompanion(seal: Value(_seal(priceTierFields(r)))),
        );
      }
    }
  });
}
