import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:toko/core/utils/device.dart';
import 'package:toko/features/receipt/data/android_bluetooth.dart';
import 'package:toko/features/receipt/data/printer_transport.dart';

import 'helpers/app_harness.dart';
import 'helpers/fake_printer.dart';

/// Perilaku khusus HP/tablet Android (disimulasikan lewat
/// [Device.debugAndroidOverride]).
void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));
  setUp(() => Device.debugAndroidOverride = true);
  tearDown(() => Device.debugAndroidOverride = null);

  test('alamat MAC dari teks perangkat Bluetooth', () {
    expect(
      AndroidBluetooth.macOf('RPP02N (66:22:AB:cd:01:F9)'),
      '66:22:AB:cd:01:F9',
    );
    expect(AndroidBluetooth.macOf('COM5'), isNull);
    expect(Device.withShortcut('Bayar', 'F2'), 'Bayar');
    Device.debugAndroidOverride = false;
    expect(Device.withShortcut('Bayar', 'F2'), 'Bayar  (F2)');
  });

  testWidgets('pengaturan printer: tanpa USB, Bluetooth = pilih printer', (
    tester,
  ) async {
    await pumpApp(
      tester,
      size: const Size(390, 844),
      overrides: [printerTransportProvider.overrideWithValue(FakeTransport())],
    );
    await login(tester, 'kasir', 'kasir123');
    await tester.tap(find.byTooltip('Atur Printer'));
    await settle(tester);
    expect(find.text('Terpasang (USB)'), findsNothing);
    await tester.tap(find.text('Bluetooth'));
    await settle(tester);
    expect(find.text('Pilih printer…'), findsOneWidget);
    expect(find.text('Baud rate'), findsNothing);
    expect(find.textContaining('Pengaturan HP › Bluetooth'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('backup: Simpan Salinan menggantikan Buka Folder', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(390, 844));
    await login(tester, 'admin', 'admin123');
    await tester.tap(find.byTooltip('Menu'));
    await settle(tester);
    await tester.tap(find.text('Pengaturan'));
    await settle(tester);
    for (
      var i = 0;
      i < 30 && find.text('Backup Sekarang').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.scrollUntilVisible(find.text('Simpan Salinan…'), 300);
    expect(find.text('Simpan Salinan…'), findsOneWidget);
    expect(find.text('Buka Folder'), findsNothing);
    await unmount(tester);
  });
}
