import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'app.dart';
import 'core/database/app_database.dart';
import 'core/database/seed.dart';
import 'core/security/password_hasher.dart';
import 'features/sales/data/held_cart_repository.dart';
import 'features/sync/data/terminal_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'id_ID';
  await initializeDateFormatting('id_ID');

  final db = AppDatabase();
  await DatabaseSeeder(db, const PasswordHasher()).seed();
  await TerminalRepository(db).ensureInitialized();
  // Transaksi tertahan hanya berlaku hari itu.
  await HeldCartRepository(db).purgeExpired();

  runApp(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: const TokoApp(),
    ),
  );
}
