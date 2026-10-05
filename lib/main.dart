import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'app.dart';
import 'core/database/app_database.dart';
import 'core/database/database_bootstrap.dart';
import 'core/database/tables/audit.dart';
import 'core/database/seed.dart';
import 'core/security/password_hasher.dart';
import 'features/backup/data/backup_service.dart';
import 'features/backup/data/restore_service.dart';
import 'features/backup/presentation/database_locked_app.dart';
import 'features/sales/data/held_cart_repository.dart';
import 'features/sync/data/terminal_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'id_ID';
  await initializeDateFormatting('id_ID');

  // Pemulihan backup yang disiapkan sebelumnya: tukar file database sebelum
  // dibuka.
  final restored = await RestoreService.applyPending();
  // Database terenkripsi dengan kunci perangkat; tanpa kunci yang cocok →
  // layar pemulihan dari backup.
  final opened = await openDeviceDatabase();
  if (opened is DatabaseLocked) {
    runApp(DatabaseLockedApp(locked: opened));
    return;
  }
  final db = (opened as DatabaseOpened).db;
  if (restored != null) {
    await db.settingsDao.set(
      RestoreService.kLastRestore,
      '${DateTime.now().toIso8601String()}|$restored',
    );
    // Backup (mungkin dari perangkat lain) disegel ulang dengan kunci
    // perangkat ini; tercatat di catatan aktivitas.
    await db.sealsDao.resealAll();
    await db.auditDao.append(
      type: AuditType.restoreApplied,
      summary: 'Data dipulihkan dari $restored; segel data dibuat ulang',
    );
  }
  await DatabaseSeeder(db, const PasswordHasher()).seed();
  await TerminalRepository(db).ensureInitialized();
  // Transaksi tertahan hanya berlaku hari itu.
  await HeldCartRepository(db).purgeExpired();
  // Backup database + Excel barang seminggu sekali (2 terbaru disimpan).
  BackupScheduler(BackupService(db)).start();

  runApp(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: const TokoApp(),
    ),
  );
}
