import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/inset_grouped_list.dart';
import '../../../../core/widgets/large_title_page.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../auth/data/role_permission_repository.dart';
import '../../../auth/domain/permission.dart';
import '../../../auth/domain/user_role.dart';
import '../../../auth/presentation/auth_controller.dart';

/// Pengaturan › Hak Akses Peran (khusus admin): apa saja yang boleh dibuka
/// dan dilakukan Supervisor dan Kasir. Admin selalu boleh semuanya.
class RolePermissionsPage extends ConsumerStatefulWidget {
  const RolePermissionsPage({super.key});

  @override
  ConsumerState<RolePermissionsPage> createState() =>
      _RolePermissionsPageState();
}

class _RolePermissionsPageState extends ConsumerState<RolePermissionsPage> {
  UserRole _role = UserRole.supervisor;
  bool _saving = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await action();
    } on PermissionFailure catch (e) {
      if (mounted) {
        await AppDialogs.alert(context, title: 'Gagal', message: e.message);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _set(Permission p, bool granted) => _run(
    () => ref
        .read(rolePermissionRepositoryProvider)
        .set(
          actor: ref.read(authControllerProvider)!,
          role: _role,
          permission: p,
          granted: granted,
        ),
  );

  Future<void> _reset() async {
    final ok = await AppDialogs.confirm(
      context,
      title: 'Kembalikan hak akses ${_role.label}?',
      message: 'Semua pilihan untuk ${_role.label} kembali seperti bawaan.',
      confirmLabel: 'Kembalikan',
    );
    if (!ok) return;
    await _run(
      () => ref
          .read(rolePermissionRepositoryProvider)
          .resetDefaults(actor: ref.read(authControllerProvider)!, role: _role),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final all = ref.watch(rolePermissionsProvider);

    return LargeTitlePage(
      title: 'Hak Akses Peran',
      backLabel: 'Pengaturan',
      onBack: () => context.go(AppRoutes.pengaturan),
      actions: [
        AppButton(
          label: 'Kembalikan Bawaan',
          icon: CupertinoIcons.arrow_counterclockwise,
          variant: AppButtonVariant.gray,
          onPressed: _saving ? null : _reset,
        ),
      ],
      bottom: Align(
        alignment: Alignment.centerLeft,
        child: CupertinoSlidingSegmentedControl<UserRole>(
          groupValue: _role,
          padding: const EdgeInsets.all(3),
          onValueChanged: (r) {
            if (r != null) setState(() => _role = r);
          },
          children: {
            for (final r in PermissionRules.editableRoles)
              r: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 6,
                ),
                child: Text(r.label, style: AppTypography.subheadline),
              ),
          },
        ),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: all.when(
                loading: () =>
                    const SizedBox(height: 240, child: LoadingState()),
                error: (e, _) =>
                    ErrorBanner(message: 'Gagal memuat hak akses: $e'),
                data: (map) {
                  final granted = map[_role] ?? const <Permission>{};
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final group in PermissionGroup.values) ...[
                        InsetGroupedSection(
                          header: group.label,
                          footer: switch (group) {
                            PermissionGroup.pages =>
                              'Halaman Kasir dan Pengaturan versi ringkas '
                                  'selalu bisa dibuka. Data yang tampil '
                                  'hanya toko akun itu.',
                            PermissionGroup.cashier => null,
                          },
                          children: [
                            for (final p in Permission.values)
                              if (p.group == group)
                                InsetGroupedTile(
                                  title: p.label,
                                  subtitle: p.description,
                                  trailing: CupertinoSwitch(
                                    value: granted.contains(p),
                                    activeTrackColor: c.success,
                                    onChanged: _saving
                                        ? null
                                        : (v) => _set(p, v),
                                  ),
                                ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xl),
                      ],
                      Text(
                        'Admin selalu punya semua hak akses. Perubahan '
                        'berlaku saat akun ${_role.label} login berikutnya, '
                        'dan tercatat di Laporan › Aktivitas.',
                        style: AppTypography.footnote.copyWith(
                          color: c.labelSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
