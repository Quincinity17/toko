import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:toko/core/widgets/app_button.dart';
import 'package:toko/core/widgets/large_title_page.dart';

import 'helpers/app_harness.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  testWidgets('Admin menambah satuan DUS + harga grosir; kasir scan DUS, '
      'grosir otomatis, lalu bayar terpisah tunai + QRIS', (tester) async {
    final db = await pumpApp(tester);
    await login(tester, 'admin', 'admin123');
    await tester.tap(find.text('Produk'));
    await settle(tester);

    // Form barang: satuan DUS isi 24 + harga grosir min. 10.
    await tester.tap(find.text('Indomie Goreng 85g'));
    await settle(tester);
    await tapCentered(tester, find.widgetWithText(AppButton, 'Tambah Satuan'));
    await settle(tester);
    await fill(tester, 'Nama satuan', 'dus');
    await fill(tester, 'Isi (PCS)', '24');
    await fill(tester, 'Harga satuan ini (Rp)', '78000');
    await fill(tester, 'Barcode kemasan (opsional)', 'DUS-IDM');
    await settle(tester);
    expect(find.textContaining('Setara Rp 3.250 per PCS'), findsOneWidget);
    await tapCentered(
      tester,
      find.widgetWithText(AppButton, 'Tambah Harga Grosir'),
    );
    await settle(tester);
    await fill(tester, 'Beli minimal (PCS)', '10');
    await fill(tester, 'Harga per PCS (Rp)', '3300');
    await tapCentered(tester, find.widgetWithText(AppButton, 'Simpan'));
    await settle(tester);
    expect(find.text('Simpan perubahan?'), findsOneWidget);
    expect(find.text('Satuan lain'), findsOneWidget);
    expect(find.text('Harga grosir'), findsOneWidget);
    await tester.tap(find.widgetWithText(AppButton, 'Simpan').last);
    await settle(tester);
    expect(find.text('Ubah Barang'), findsNothing);
    final units = await tester.runAsync(() => db.select(db.productUnits).get());
    expect(units!.single.name, 'DUS');

    // Kasir: scan barcode kemasan = 1 DUS.
    await tester.tap(find.text('Kasir'));
    await settle(tester);
    Future<void> scan(String code) async {
      await fill(tester, 'Barcode', code);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
    }

    await scan('DUS-IDM');
    expect(find.text('DUS'), findsOneWidget);
    expect(find.text('Rp 78.000'), findsWidgets);

    // 10 PCS → harga grosir.
    await fill(tester, 'Jumlah', '10');
    await scan('BRG001');
    expect(find.text('Harga grosir (min. 10)'), findsOneWidget);
    // 78.000 + 10 × 3.300 = 111.000
    expect(find.text('Rp 111.000'), findsWidgets);

    // Bayar terpisah: QRIS 100.000, tunai = sisa (kolom kosong).
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await settle(tester);
    await tester.tap(find.text('Bayar terpisah (beberapa metode)'));
    await settle(tester);
    final qrisField = find.byWidgetPredicate(
      (w) =>
          w is CupertinoTextField &&
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('split-amount-') &&
          w.placeholder == 'Jumlah',
    );
    await tester.enterText(qrisField, '100000');
    await settle(tester);
    expect(find.text('Kembalian'), findsOneWidget);
    await tester.tap(find.widgetWithText(AppButton, 'Selesaikan Transaksi'));
    await settle(tester);
    expect(find.text('Transaksi Berhasil'), findsOneWidget);
    expect(find.textContaining('Tunai + QRIS'), findsOneWidget);

    final parts = await tester.runAsync(() => db.select(db.salePayments).get());
    expect(parts!.map((p) => (p.methodName, p.amount)), [
      ('Tunai', 11000),
      ('QRIS', 100000),
    ]);

    await unmount(tester);
  });

  testWidgets('Cetak Label: scan barang, atur jumlah, ringkasan halaman', (
    tester,
  ) async {
    await pumpApp(tester);
    await login(tester, 'admin', 'admin123');
    await tester.tap(find.text('Produk'));
    await settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(LargeTitlePage),
        matching: find.text('Cetak Label'),
      ),
    );
    await settle(tester);
    expect(find.text('Contoh tampilan label.'), findsOneWidget);

    final entry = find.byWidgetPredicate(
      (w) =>
          w is CupertinoTextField &&
          w.placeholder == 'Scan / ketik barcode lalu Enter',
    );
    await tester.enterText(entry, 'BRG001');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    await tester.enterText(entry, 'brg001');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(find.text('Indomie Goreng 85g'), findsWidgets);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('2 label · 1 halaman'), findsOneWidget);

    await tester.tap(find.byTooltip('Tambah'));
    await settle(tester);
    expect(find.text('3 label · 1 halaman'), findsOneWidget);

    await unmount(tester);
  });
}
