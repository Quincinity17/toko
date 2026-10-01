import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/sales.dart';
import '../tables/vouchers.dart';

part 'vouchers_dao.g.dart';

@DriftAccessor(tables: [Vouchers, Sales])
class VouchersDao extends DatabaseAccessor<AppDatabase>
    with _$VouchersDaoMixin {
  VouchersDao(super.attachedDatabase);

  /// Aktif dulu, lalu terbaru.
  Stream<List<VoucherRow>> watchAll() {
    return (select(vouchers)..orderBy([
          (v) => OrderingTerm.desc(v.isActive),
          (v) => OrderingTerm.desc(v.createdAt),
          (v) => OrderingTerm.desc(v.id),
        ]))
        .watch();
  }

  Future<VoucherRow?> findById(int id) =>
      (select(vouchers)..where((v) => v.id.equals(id))).getSingleOrNull();

  Future<VoucherRow?> findByCode(String code) => (select(
    vouchers,
  )..where((v) => v.code.equals(code.trim().toUpperCase()))).getSingleOrNull();

  Future<int> insertVoucher(VouchersCompanion v) => into(vouchers).insert(v);

  Future<void> updateVoucher(int id, VouchersCompanion v) =>
      (update(vouchers)..where((t) => t.id.equals(id))).write(v);

  Future<int> deleteVoucher(int id) =>
      (delete(vouchers)..where((t) => t.id.equals(id))).go();

  /// Menambah pemakaian hanya jika kuota masih ada. Mengembalikan `false`
  /// jika kuota sudah habis (mis. dipakai kasir lain di detik yang sama).
  Future<bool> tryConsume(int id) async {
    final changed = await customUpdate(
      'UPDATE vouchers SET used_count = used_count + 1 '
      'WHERE id = ? AND (quota IS NULL OR used_count < quota)',
      variables: [Variable.withInt(id)],
      updates: {vouchers},
    );
    return changed == 1;
  }

  Future<int> countSalesUsing(int id) async {
    final count = sales.id.count();
    final row =
        await (selectOnly(sales)
              ..addColumns([count])
              ..where(sales.voucherId.equals(id)))
            .getSingle();
    return row.read(count) ?? 0;
  }
}
