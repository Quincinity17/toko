import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:toko/core/router/routes.dart';
import 'package:toko/core/widgets/large_title_page.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:toko/core/database/tables/sales.dart';
import 'package:toko/features/stock/presentation/stock_alert_list.dart';

import 'helpers/app_harness.dart';
import 'helpers/test_app.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  for (final size in [const Size(1440, 1000), const Size(390, 844)]) {
    testWidgets('Stok › Peringatan: stok minus & pecahan (${size.width})', (
      tester,
    ) async {
      final db = await pumpApp(tester, size: size);
      await tester.runAsync(() async {
        final store = await mainStoreId(db);
        final rows = await db.select(db.products).get();
        Future<void> setStock(String code, double delta) =>
            db.storesDao.changeStock(
              storeId: store,
              productId: rows.firstWhere((p) => p.code == code).id,
              delta: delta,
              type: StockMovementType.import,
              userId: null,
            );
        final indomie = await db.storesDao.entry(
          store,
          rows.firstWhere((p) => p.code == 'BRG001').id,
        );
        await setStock('BRG001', -indomie!.stock - 3); // → −3
        await setStock('BRG010', 0.5); // pecahan
      });
      await login(tester, 'admin', 'admin123');
      // Seperti kartu "Peringatan stok" di Dashboard.
      GoRouter.of(tester.element(find.byType(LargeTitlePage).first))
          .go('${AppRoutes.stok}?view=peringatan');
      await settle(tester);
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await settle(tester);
      }
      expect(find.byType(StockAlertList), findsOneWidget);
      expect(find.text('SEGERA DITANGANI (1)'), findsOneWidget);
      expect(find.textContaining('Stok tercatat -3 PCS'), findsOneWidget);
      expect(find.text('CEK STOK NYATA (1)'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });
  }
}
