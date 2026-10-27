import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:toko/core/router/routes.dart';
import 'package:toko/core/widgets/app_button.dart';
import 'package:toko/core/widgets/large_title_page.dart';
import 'package:toko/server/server_store.dart';
import 'package:toko/server/toko_server.dart';

import 'helpers/app_harness.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  testWidgets('Admin menyambungkan komputer ini sebagai master lewat '
      'Pengaturan', (tester) async {
    // flutter_test mengganti HttpClient dengan tiruan (selalu 400); tes ini
    // memakai server sungguhan.
    HttpOverrides.global = null;
    final store = ServerStore(sqlite3.openInMemory());
    final server = TokoServer(store, log: (_) {});
    await tester.runAsync(
      () => server.start(port: 0, address: InternetAddress.loopbackIPv4),
    );
    final db = await pumpApp(tester);
    await login(tester, 'admin', 'admin123');
    GoRouter.of(tester.element(find.byType(LargeTitlePage).first))
        .go(AppRoutes.pengaturan);
    await settle(tester);

    await tapCentered(tester, find.text('Server pusat'));
    await settle(tester);
    await fill(tester, 'Alamat server', '127.0.0.1:${server.port}');
    await fill(tester, 'Kode pairing', store.pairingCode);
    await tester.tap(find.text('Komputer server (master)'));
    await settle(tester);

    Future<void> waitIo() async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      await settle(tester);
    }

    await tester.tap(find.widgetWithText(AppButton, 'Cek Sambungan'));
    await waitIo();
    expect(find.textContaining('Server ditemukan'), findsOneWidget);

    await tester.tap(find.widgetWithText(AppButton, 'Sambungkan'));
    await waitIo();
    await waitIo();
    expect(find.text('Sambungkan ke Server'), findsNothing);
    expect(find.textContaining('· Master'), findsOneWidget);
    expect(find.text('Sinkron Sekarang'), findsOneWidget);
    expect(store.terminals().single.code, 'K01');
    // Data master terkirim ke server.
    expect(store.lastSeq, greaterThan(20));
    expect((await tester.runAsync(() => db.outboxDao.pending()))!, isEmpty);

    await unmount(tester);
    await tester.runAsync(server.stop);
    store.close();
  });
}
