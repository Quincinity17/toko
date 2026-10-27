import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/payment_methods.dart';
import '../tables/sales.dart';

part 'payment_methods_dao.g.dart';

@DriftAccessor(tables: [PaymentMethods, Sales])
class PaymentMethodsDao extends DatabaseAccessor<AppDatabase>
    with _$PaymentMethodsDaoMixin {
  PaymentMethodsDao(super.attachedDatabase);

  Stream<List<PaymentMethodRow>> watchAll({bool activeOnly = false}) {
    final query = select(paymentMethods)
      ..orderBy([
        (m) => OrderingTerm.asc(m.sortOrder),
        (m) => OrderingTerm.asc(m.id),
      ]);
    if (activeOnly) query.where((m) => m.isActive.equals(true));
    return query.watch();
  }

  Future<PaymentMethodRow?> findById(int id) =>
      (select(paymentMethods)..where((m) => m.id.equals(id))).getSingleOrNull();

  Future<PaymentMethodRow?> findByName(String name) =>
      (select(paymentMethods)
            ..where((m) => m.name.lower().equals(name.trim().toLowerCase())))
          .getSingleOrNull();

  Future<int> countActive() async {
    final count = paymentMethods.id.count();
    final row =
        await (selectOnly(paymentMethods)
              ..addColumns([count])
              ..where(paymentMethods.isActive.equals(true)))
            .getSingle();
    return row.read(count) ?? 0;
  }

  Future<int> nextSortOrder() async {
    final max = paymentMethods.sortOrder.max();
    final row = await (selectOnly(
      paymentMethods,
    )..addColumns([max])).getSingle();
    return (row.read(max) ?? 0) + 1;
  }

  Future<int> insertMethod(PaymentMethodsCompanion m) =>
      into(paymentMethods).insert(m);

  Future<void> updateMethod(int id, PaymentMethodsCompanion m) =>
      (update(paymentMethods)..where((t) => t.id.equals(id))).write(m);

  Future<int> deleteMethod(int id) =>
      (delete(paymentMethods)..where((t) => t.id.equals(id))).go();

  Future<int> countSalesUsing(int id) async {
    final count = sales.id.count();
    final row =
        await (selectOnly(sales)
              ..addColumns([count])
              ..where(sales.paymentMethodId.equals(id)))
            .getSingle();
    // Bagian split payment (metode kedua dst. tidak ada di sales).
    final split = await customSelect(
      'SELECT COUNT(*) AS n FROM sale_payments WHERE payment_method_id = ?',
      variables: [Variable.withInt(id)],
    ).getSingle();
    return (row.read(count) ?? 0) + split.read<int>('n');
  }
}
