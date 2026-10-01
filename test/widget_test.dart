import 'package:bcrypt/bcrypt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:toko/app.dart';
import 'package:toko/core/database/app_database.dart';
import 'package:toko/core/security/password_hasher.dart';

import 'helpers/test_app.dart';

/// Verifikasi bcrypt tanpa isolate, karena isolate tidak berjalan di dalam
/// waktu palsu (fake async) milik testWidgets.
class _SyncHasher extends PasswordHasher {
  const _SyncHasher() : super(logRounds: 4);

  @override
  Future<bool> verify(String password, String hash) async =>
      BCrypt.checkpw(password, hash);
}

/// Kursor teks berkedip terus, jadi pumpAndSettle tidak bisa dipakai.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> login(WidgetTester tester, String name, String password) async {
  await tester.tap(find.text(name));
  await settle(tester);
  await tester.enterText(find.byType(EditableText), password);
  await settle(tester); // tombol Masuk aktif setelah frame berikutnya
  await tester.tap(find.text('Masuk'));
  await settle(tester);
}

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  testWidgets('Login membedakan admin dan kasir', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final db = (await tester.runAsync(createSeededDb))!;
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          passwordHasherProvider.overrideWithValue(const _SyncHasher()),
        ],
        child: const TokoApp(),
      ),
    );
    await settle(tester);

    expect(find.text('Masuk ke Toko'), findsOneWidget);
    expect(find.text('Administrator'), findsOneWidget);
    expect(find.text('Kasir Satu'), findsOneWidget);

    // Password salah: tetap di login dan muncul pesan.
    await login(tester, 'Kasir Satu', 'salah');
    expect(find.text('Password salah. Coba lagi.'), findsOneWidget);

    // Kasir masuk ke layar kasir; menu admin tidak tampil.
    await login(tester, 'Kasir Satu', 'kasir123');
    expect(find.text('Layar kasir belum tersedia'), findsOneWidget);
    expect(find.text('Produk'), findsNothing);
    expect(find.text('Pengaturan'), findsNothing);

    // Keluar lewat menu user di sidebar.
    await tester.tap(find.text('Kasir Satu'));
    await settle(tester);
    await tester.tap(find.text('Keluar'));
    await settle(tester);
    expect(find.text('Masuk ke Toko'), findsOneWidget);

    // Admin masuk ke dashboard dengan menu lengkap.
    await login(tester, 'Administrator', 'admin123');
    expect(find.text('Omzet Hari Ini'), findsOneWidget);
    expect(find.text('Produk'), findsOneWidget);
    expect(find.text('Pengaturan'), findsOneWidget);
  });
}
