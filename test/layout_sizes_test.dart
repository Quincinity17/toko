import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:toko/core/router/routes.dart';
import 'package:toko/core/widgets/large_title_page.dart';

import 'helpers/app_harness.dart';

/// Pengumpul error tata letak untuk satu tes.
class _LayoutErrors {
  _LayoutErrors() {
    _previous = FlutterError.onError;
    FlutterError.onError = (d) {
      // Lokasi kode penyebab, mis. "lib/…/tag_chip.dart:49".
      final where = RegExp(r'lib/[^\s:]+:\d+')
          .firstMatch(d.toString())
          ?.group(0);
      _add('${d.exceptionAsString().split('\n').first} ($where)');
    };
    addTearDown(_restore);
  }

  FlutterExceptionHandler? _previous;
  final _errors = <String>[];
  String _label = '';

  void _add(String e) => _errors.add(_label.isEmpty ? e : '$_label: $e');
  void _restore() => FlutterError.onError = _previous;

  /// Langkah berlabel: error selama [action] diberi label itu.
  Future<void> step(
    WidgetTester tester,
    String label,
    Future<void> Function() action,
  ) async {
    _label = label;
    await action();
    await settle(tester);
    _label = '';
  }

  /// Pemeriksaan di tengah alur (tanpa `expect`, yang tidak boleh dipakai
  /// selama error ditangkap).
  void check(Finder finder, String what) {
    if (finder.evaluate().isEmpty) _add('tidak terlihat: $what');
  }

  /// Melepas penangkap error lalu memastikan tidak ada luapan.
  void finish() {
    _restore();
    expect(_errors.toSet().toList(), isEmpty);
  }
}

/// Membuka halaman & alur utama di ukuran HP dan tablet; teks/kotak yang
/// meluap (RenderFlex overflow) atau error tata letak lain membuat tes gagal.
void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  GoRouter router(WidgetTester tester) =>
      GoRouter.of(tester.element(find.byType(Navigator).first));

  const sizes = {
    'HP 390×844': Size(390, 844),
    'HP mendatar 844×390': Size(844, 390),
    'tablet tegak 800×1280': Size(800, 1280),
    'tablet mendatar 1280×800': Size(1280, 800),
  };
  const adminPages = [
    AppRoutes.dashboard,
    AppRoutes.kasir,
    AppRoutes.produk,
    AppRoutes.inputTabel,
    AppRoutes.importProduk,
    AppRoutes.stok,
    AppRoutes.laporan,
    AppRoutes.pengaturan,
    AppRoutes.kelolaAkun,
    AppRoutes.metodeBayar,
    AppRoutes.kelolaToko,
    AppRoutes.strukPrinter,
    AppRoutes.kelolaKategori,
  ];

  for (final MapEntry(key: name, value: size) in sizes.entries) {
    testWidgets('semua halaman admin tanpa luapan: $name', (tester) async {
      final errors = _LayoutErrors();
      await pumpApp(tester, size: size);
      await login(tester, 'admin', 'admin123');
      for (final path in adminPages) {
        await errors.step(tester, path, () async => router(tester).go(path));
      }
      await unmount(tester);
      errors.finish();
    });
  }

  testWidgets('alur kasir di HP tanpa luapan', (tester) async {
    final errors = _LayoutErrors();
    await pumpApp(tester, size: const Size(390, 844));
    await login(tester, 'kasir', 'kasir123');

    await errors.step(tester, 'scan', () async {
      for (final code in ['BRG001', 'BRG013', 'BRG016']) {
        await fill(tester, 'Barcode', code);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await settle(tester);
      }
    });
    errors.check(find.text('Chitato Sapi Panggang 68g'), 'barang di keranjang');
    await errors.step(
      tester,
      'cari',
      () => tester.tap(find.byTooltip('Cari barang')),
    );
    await errors.step(
      tester,
      'tutup cari',
      () => tester.sendKeyEvent(LogicalKeyboardKey.escape),
    );
    await errors.step(tester, 'bayar', () => tester.tap(find.text('Bayar')));
    errors.check(find.text('Pembayaran'), 'popup bayar');
    await errors.step(
      tester,
      'uang pas',
      () => tester.testTextInput.receiveAction(TextInputAction.done),
    );
    errors.check(find.text('Transaksi Berhasil'), 'transaksi berhasil');
    await errors.step(
      tester,
      'transaksi baru',
      () => tester.tap(find.textContaining('Transaksi Baru  (Enter)')),
    );
    await errors.step(
      tester,
      'hari ini',
      () => tester.tap(find.text('Hari Ini')),
    );
    await errors.step(
      tester,
      'rincian',
      () => tester.tap(find.textContaining('INV-')),
    );
    errors.check(find.textContaining('Kasir: Kasir Satu'), 'rincian faktur');

    await unmount(tester);
    errors.finish();
  });

  testWidgets('form barang & bagian laporan di HP tanpa luapan', (
    tester,
  ) async {
    final errors = _LayoutErrors();
    await pumpApp(tester, size: const Size(390, 844));
    await login(tester, 'admin', 'admin123');

    await errors.step(
      tester,
      'produk',
      () async => router(tester).go(AppRoutes.produk),
    );
    await errors.step(
      tester,
      'form barang',
      () => tester.tap(find.text('Tambah')),
    );
    errors.check(find.text('Barang Baru'), 'form barang');
    await errors.step(
      tester,
      'tutup form',
      () => tester.sendKeyEvent(LogicalKeyboardKey.escape),
    );

    await errors.step(
      tester,
      'laporan',
      () async => router(tester).go(AppRoutes.laporan),
    );
    for (final section in [
      'Ringkasan',
      'Tren',
      'Produk',
      'Kategori',
      'Stok',
      'Pembayaran',
      'Kasir & Terminal',
      'Faktur',
      'Aktivitas',
    ]) {
      await errors.step(tester, 'laporan $section', () async {
        final chip = find.descendant(
          of: find.byType(LargeTitlePage),
          matching: find.text(section),
        );
        await tester.ensureVisible(chip.first);
        await tester.tap(chip.first);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
      });
    }

    await unmount(tester);
    errors.finish();
  });
}
