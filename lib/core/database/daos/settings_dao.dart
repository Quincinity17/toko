import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/sync.dart';

part 'settings_dao.g.dart';

@DriftAccessor(tables: [AppSettings])
class SettingsDao extends DatabaseAccessor<AppDatabase>
    with _$SettingsDaoMixin {
  SettingsDao(super.attachedDatabase);

  Future<String?> get(String key) async {
    final row = await (select(
      appSettings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Stream<String?> watch(String key) => (select(
    appSettings,
  )..where((s) => s.key.equals(key))).watchSingleOrNull().map((r) => r?.value);

  /// Beberapa pengaturan sekaligus sebagai map `key → value`.
  Stream<Map<String, String>> watchMany(List<String> keys) =>
      (select(appSettings)..where((s) => s.key.isIn(keys))).watch().map(
        (rows) => {for (final r in rows) r.key: r.value},
      );

  Future<void> set(String key, String value) => into(
    appSettings,
  ).insertOnConflictUpdate(AppSettingsCompanion.insert(key: key, value: value));
}
