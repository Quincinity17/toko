import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/widgets/option_picker.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/store_repository.dart';
import '../domain/store.dart';

/// Toko yang sedang dipakai di semua halaman (kasir, stok, produk, laporan).
///
/// - Supervisor & kasir: selalu tokonya sendiri, tidak bisa diganti.
/// - Admin: dipilih lewat sidebar; `null` = semua toko. Pilihan disimpan per
///   komputer di `settings` supaya tidak perlu memilih ulang setiap login.
///   Belum pernah memilih + hanya satu toko aktif = toko itu.
class StoreScopeController extends Notifier<int?> {
  static const kSetting = 'admin.store_scope';

  @override
  int? build() {
    final user = ref.watch(authControllerProvider);
    if (user == null) return null;
    if (!user.isAdmin) return user.storeId;
    _restore();
    return null;
  }

  /// Pilihan tersimpan; jika belum pernah memilih dan hanya ada satu toko
  /// aktif, langsung toko itu (toko tunggal tidak perlu memilih).
  Future<void> _restore() async {
    final db = ref.read(appDatabaseProvider);
    final saved = await db.settingsDao.get(kSetting);
    if (saved == null) {
      final active = (await db.storesDao.watchAll().first)
          .where((s) => s.isActive)
          .toList();
      if (ref.mounted && active.length == 1) state = active.first.id;
      return;
    }
    final id = int.tryParse(saved);
    if (id == null) return;
    final store = await db.storesDao.findById(id);
    if (ref.mounted && store != null && store.isActive) state = id;
  }

  /// Hanya admin yang bisa berpindah toko.
  Future<void> select(int? storeId) async {
    if (!(ref.read(authControllerProvider)?.isAdmin ?? false)) return;
    state = storeId;
    await ref
        .read(appDatabaseProvider)
        .settingsDao
        .set(kSetting, storeId?.toString() ?? '');
  }
}

final storeScopeProvider = NotifierProvider<StoreScopeController, int?>(
  StoreScopeController.new,
);

/// Data toko yang sedang dipakai; `null` = semua toko (admin) atau belum
/// termuat.
final activeStoreProvider = Provider<Store?>((ref) {
  final id = ref.watch(storeScopeProvider);
  if (id == null) return null;
  final stores = ref.watch(storesProvider).value ?? const [];
  for (final s in stores) {
    if (s.id == id) return s;
  }
  return null;
});

/// Popup memilih toko aktif (admin). Dengan [allowAll], ada opsi
/// "Semua toko". Mengembalikan `true` jika pilihan berubah.
Future<bool> pickStoreScope(
  BuildContext context,
  WidgetRef ref, {
  bool allowAll = true,
}) async {
  final stores = (ref.read(storesProvider).value ?? const <Store>[])
      .where((s) => s.isActive)
      .toList();
  final current = ref.read(activeStoreProvider);
  final pick = await showOptionPicker(
    context,
    title: 'Pilih Toko',
    options: [for (final s in stores) s.name],
    selected: current?.name,
    clearLabel: allowAll ? 'Semua toko' : null,
  );
  if (pick == null) return false;
  final id = pick.value == null
      ? null
      : stores.firstWhere((s) => s.name == pick.value).id;
  if (id == ref.read(storeScopeProvider)) return false;
  await ref.read(storeScopeProvider.notifier).select(id);
  return true;
}
