import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:toko/app.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  testWidgets('App shell tampil dan navigasi sidebar berjalan', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ProviderScope(child: TokoApp()));
    await tester.pumpAndSettle();

    // Judul besar halaman awal.
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Omzet Hari Ini'), findsOneWidget);

    await tester.tap(find.text('Produk'));
    await tester.pumpAndSettle();
    expect(find.text('Belum ada produk'), findsOneWidget);

    // Pengaturan berisi spinner yang terus berputar, jadi tidak bisa settle.
    await tester.tap(find.text('Pengaturan'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Rp 1.250.000'), findsOneWidget);
  });
}
