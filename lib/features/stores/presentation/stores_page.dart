import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/inset_grouped_list.dart';
import '../../../core/widgets/large_title_page.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/store_repository.dart';
import '../domain/store.dart';

/// Pengaturan › Kelola Toko (khusus admin).
class StoresPage extends ConsumerWidget {
  const StoresPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stores = ref.watch(storesProvider);

    return LargeTitlePage(
      title: 'Kelola Toko',
      backLabel: 'Pengaturan',
      onBack: () => context.go(AppRoutes.pengaturan),
      actions: [
        AppButton(
          label: 'Tambah Toko',
          icon: CupertinoIcons.add,
          onPressed: () => _showForm(context),
        ),
      ],
      slivers: [
        stores.when(
          loading: () => const SliverToBoxAdapter(
            child: SizedBox(height: 240, child: LoadingState()),
          ),
          error: (e, _) =>
              SliverToBoxAdapter(child: ErrorBanner(message: '$e')),
          data: (list) => SliverToBoxAdapter(
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: InsetGroupedSection(
                  footer:
                      'Setiap toko punya stok dan harga jualnya sendiri. '
                      'Supervisor dan kasir terikat ke satu toko (atur di '
                      'Kelola Akun); admin bisa melihat semua toko. Toko yang '
                      'sudah dipakai tidak bisa dihapus, cukup dinonaktifkan.',
                  dividerIndent: 58,
                  children: [for (final s in list) _StoreTile(store: s)],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StoreTile extends StatelessWidget {
  const _StoreTile({required this.store});

  final Store store;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = store;
    return InsetGroupedTile(
      leading: TileIcon(
        icon: CupertinoIcons.building_2_fill,
        color: s.isActive ? c.accent : c.labelTertiary,
      ),
      title: s.name,
      subtitle: [
        if (s.address != null) s.address!,
        if (!s.isActive) 'Nonaktif',
      ].join(' · '),
      showChevron: true,
      onPressed: () => _showForm(context, existing: s),
    );
  }
}

Future<void> _showForm(BuildContext context, {Store? existing}) {
  return AppDialogs.sheet<void>(
    context,
    title: existing == null ? 'Toko Baru' : 'Ubah Toko',
    builder: (_) => _StoreForm(existing: existing),
  );
}

class _StoreForm extends ConsumerStatefulWidget {
  const _StoreForm({this.existing});

  final Store? existing;

  @override
  ConsumerState<_StoreForm> createState() => _StoreFormState();
}

class _StoreFormState extends ConsumerState<_StoreForm> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _address = TextEditingController(text: widget.existing?.address);
  late bool _active = widget.existing?.isActive ?? true;
  String? _nameError, _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<T?> _run<T>(Future<T> Function() action) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await action();
      if (mounted) Navigator.pop(context);
      return result;
    } on StoreFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
      return null;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    setState(
      () => _nameError = _name.text.trim().isEmpty
          ? 'Nama toko wajib diisi.'
          : null,
    );
    if (_nameError != null) return;
    await _run(
      () => ref
          .read(storeRepositoryProvider)
          .save(
            actor: ref.read(authControllerProvider)!,
            id: widget.existing?.id,
            name: _name.text,
            address: _address.text,
            isActive: _active,
          ),
    );
  }

  Future<void> _remove() async {
    final s = widget.existing!;
    final ok = await AppDialogs.confirm(
      context,
      title: 'Hapus ${s.name}?',
      message:
          'Toko yang belum punya akun, transaksi, atau riwayat stok dihapus '
          'permanen. Toko yang sudah dipakai hanya dinonaktifkan.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final nav = Navigator.of(context);
    final result = await _run(
      () => ref
          .read(storeRepositoryProvider)
          .remove(actor: ref.read(authControllerProvider)!, id: s.id),
    );
    if (result == StoreRemoval.deactivated && nav.mounted) {
      await AppDialogs.alert(
        nav.context,
        title: 'Toko dinonaktifkan',
        message:
            '${s.name} sudah punya akun atau transaksi, jadi tidak dihapus. '
            'Akun supervisor/kasir toko ini tidak bisa login sampai tokonya '
            'diaktifkan lagi.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _name,
            label: 'Nama toko',
            placeholder: 'mis. Toko Cabang Pasar',
            autofocus: widget.existing == null,
            errorText: _nameError,
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _address,
            label: 'Alamat (opsional)',
            placeholder: 'mis. Jl. Merdeka No. 10',
            onSubmitted: (_) => _save(),
          ),
          if (widget.existing != null) ...[
            const SizedBox(height: AppSpacing.lg),
            InsetGroupedSection(
              children: [
                InsetGroupedTile(
                  title: 'Toko aktif',
                  subtitle: _active
                      ? 'Akun toko ini bisa login dan berjualan'
                      : 'Akun supervisor/kasir toko ini tidak bisa login',
                  trailing: CupertinoSwitch(
                    value: _active,
                    activeTrackColor: c.success,
                    onChanged: (v) => setState(() => _active = v),
                  ),
                ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            ErrorBanner(message: _error!),
          ],
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: 'Simpan',
            size: AppButtonSize.large,
            expand: true,
            loading: _saving,
            onPressed: _save,
          ),
          if (widget.existing != null) ...[
            const SizedBox(height: AppSpacing.xs),
            AppButton(
              label: 'Hapus Toko',
              variant: AppButtonVariant.plain,
              destructive: true,
              expand: true,
              onPressed: _saving ? null : _remove,
            ),
          ],
        ],
      ),
    );
  }
}
