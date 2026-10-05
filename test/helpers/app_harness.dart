import 'dart:io';

import 'package:bcrypt/bcrypt.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:toko/app.dart';
import 'package:toko/core/database/app_database.dart';
import 'package:toko/core/security/password_hasher.dart';
import 'package:toko/features/backup/data/backup_service.dart';
import 'package:toko/features/backup/data/restore_service.dart';

import 'test_app.dart';

// Bantuan tes widget yang menjalankan seluruh aplikasi (dipakai
// widget_test.dart dan layout_sizes_test.dart).

/// Hash/verifikasi bcrypt tanpa isolate, karena isolate tidak berjalan di dalam
/// waktu palsu (fake async) milik testWidgets.
class SyncHasher extends PasswordHasher {
  const SyncHasher() : super(logRounds: 4);

  @override
  Future<bool> verify(String password, String hash) async =>
      BCrypt.checkpw(password, hash);

  @override
  Future<String> hash(String password) async =>
      BCrypt.hashpw(password, BCrypt.gensalt(logRounds: logRounds));
}

/// Kursor teks berkedip terus, jadi pumpAndSettle tidak bisa dipakai.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> login(
  WidgetTester tester,
  String username,
  String password,
) async {
  final fields = find.byType(EditableText);
  await tester.enterText(fields.at(0), username);
  await tester.enterText(fields.at(1), password);
  await settle(tester); // tombol Masuk aktif setelah frame berikutnya
  await tester.tap(find.text('Masuk'));
  await settle(tester);
}

/// Menjalankan aplikasi dengan database seed di memori. [size] = ukuran
/// layar (bawaan desktop 1440 × 1000; mis. HP 390 × 844).
Future<AppDatabase> pumpApp(
  WidgetTester tester, {
  List<Override> overrides = const [],
  Size size = const Size(1440, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final db = (await tester.runAsync(createSeededDb))!;
  addTearDown(db.close);
  // Backup ke folder sementara (path_provider tidak ada di tes).
  final backupDir = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('toko-backup-'),
  ))!;
  addTearDown(() => backupDir.deleteSync(recursive: true));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        passwordHasherProvider.overrideWithValue(const SyncHasher()),
        backupServiceProvider.overrideWithValue(
          BackupService(db, defaultFolder: () async => backupDir),
        ),
        restoreServiceProvider.overrideWithValue(
          RestoreService(
            db,
            BackupService(db, defaultFolder: () async => backupDir),
            supportDir: () async => backupDir,
          ),
        ),
        ...overrides,
      ],
      child: const TokoApp(),
    ),
  );
  await settle(tester);
  return db;
}

/// Membongkar aplikasi di akhir tes supaya stream drift sempat ditutup
/// dan tidak ada timer yang tertinggal.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

/// Gulir sampai [finder] terlihat, lalu ketuk.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

/// Seperti [tapVisible], tetapi digulir ke tengah layar supaya tidak
/// tertutup toolbar kaca halaman panjang.
Future<void> tapCentered(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pump();
  await tester.tap(finder);
}

/// Mengisi AppTextField berdasarkan labelnya. Label yang sama bisa muncul di
/// tempat lain (mis. "Stok" di sidebar), jadi dipilih label pertama yang
/// Column induknya berisi kolom isian.
Future<void> fill(WidgetTester tester, String label, String text) async {
  for (final candidate in find.text(label).evaluate()) {
    final field = find.descendant(
      of: find
          .ancestor(
            of: find.byWidget(candidate.widget),
            matching: find.byType(Column),
          )
          .first,
      matching: find.byType(EditableText),
    );
    if (field.evaluate().isNotEmpty) {
      await tester.enterText(field.first, text);
      await tester.pump();
      return;
    }
  }
  fail('Kolom isian "$label" tidak ditemukan.');
}
