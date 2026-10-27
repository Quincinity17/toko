import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/choice_chips.dart';
import '../data/store_repository.dart';
import '../domain/store.dart';
import 'store_scope.dart';

/// Toko aktif, urut seperti di Kelola Toko.
List<Store> activeStores(WidgetRef ref) =>
    (ref.watch(storesProvider).value ?? const <Store>[])
        .where((s) => s.isActive)
        .toList();

/// Chip "Semua toko" + tiap toko aktif; menulis ke [storeScopeProvider]
/// (sama dengan pemilih di sidebar). Dipakai Dashboard & Laporan; hanya
/// ditampilkan pemanggil bila ada > 1 toko aktif.
class StoreScopeChips extends ConsumerWidget {
  const StoreScopeChips({super.key, required this.stores});

  final List<Store> stores;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ChoiceChips<int?>(
      values: [null, for (final st in stores) st.id],
      selected: ref.watch(storeScopeProvider),
      label: (id) => id == null
          ? 'Semua toko'
          : stores.firstWhere((st) => st.id == id).name,
      icon: (id) => id == null
          ? CupertinoIcons.square_grid_2x2
          : CupertinoIcons.house_fill,
      onSelected: (id) => ref.read(storeScopeProvider.notifier).select(id),
    );
  }
}
