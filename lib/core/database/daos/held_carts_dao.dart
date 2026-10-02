import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/held_carts.dart';
import '../tables/users.dart';

part 'held_carts_dao.g.dart';

@DriftAccessor(tables: [HeldCarts, Users])
class HeldCartsDao extends DatabaseAccessor<AppDatabase>
    with _$HeldCartsDaoMixin {
  HeldCartsDao(super.attachedDatabase);

  Future<int> insertCart(HeldCartsCompanion row) => into(heldCarts).insert(row);

  /// Transaksi tertahan di toko [storeId] sejak [since] beserta nama
  /// kasirnya, terlama dulu (urutan antrian).
  Stream<List<(HeldCartRow, String)>> watchSince(
    DateTime since, {
    required int storeId,
  }) {
    final query =
        select(heldCarts)
            .join([innerJoin(users, users.id.equalsExp(heldCarts.userId))])
          ..where(
            heldCarts.createdAt.isBiggerOrEqualValue(since) &
                heldCarts.storeId.equals(storeId),
          )
          ..orderBy([OrderingTerm.asc(heldCarts.id)]);
    return query
        .map((r) => (r.readTable(heldCarts), r.readTable(users).fullName))
        .watch();
  }

  Future<HeldCartRow?> byId(int id) =>
      (select(heldCarts)..where((h) => h.id.equals(id))).getSingleOrNull();

  Future<int> deleteById(int id) =>
      (delete(heldCarts)..where((h) => h.id.equals(id))).go();

  Future<int> deleteBefore(DateTime time) => (delete(
    heldCarts,
  )..where((h) => h.createdAt.isSmallerThanValue(time))).go();
}
