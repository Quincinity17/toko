import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/inset_grouped_list.dart';
import '../../../../core/widgets/large_title_page.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../auth/data/user_repository.dart';
import '../../../auth/domain/app_user.dart';
import '../../../auth/domain/user_role.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../auth/presentation/widgets/user_avatar.dart';
import 'account_form_sheet.dart';
import '../../../stores/data/store_repository.dart';
import '../../../stores/domain/store.dart';

/// Semua akun, diperbarui otomatis saat database berubah.
final accountsProvider = StreamProvider.autoDispose<List<AppUser>>(
  (ref) => ref.watch(userRepositoryProvider).watchAll(),
);

/// Pengaturan › Kelola Akun (khusus admin).
class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    final me = ref.watch(authControllerProvider);
    final stores = ref.watch(storesProvider).value ?? const <Store>[];

    return LargeTitlePage(
      title: 'Kelola Akun',
      backLabel: 'Pengaturan',
      onBack: () => context.go(AppRoutes.pengaturan),
      actions: [
        AppButton(
          label: 'Tambah Akun',
          icon: CupertinoIcons.person_add_solid,
          onPressed: () => showAccountFormSheet(context),
        ),
      ],
      slivers: [
        accounts.when(
          loading: () => const SliverToBoxAdapter(
            child: SizedBox(height: 240, child: LoadingState()),
          ),
          error: (e, _) => SliverToBoxAdapter(
            child: ErrorBanner(message: 'Gagal memuat akun: $e'),
          ),
          data: (list) => SliverToBoxAdapter(
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: _AccountGroups(accounts: list, stores: stores, me: me),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Admin, lalu satu bagian per toko (supervisor dulu, lalu kasir), lalu
/// akun nonaktif.
class _AccountGroups extends StatelessWidget {
  const _AccountGroups({
    required this.accounts,
    required this.stores,
    required this.me,
  });

  final List<AppUser> accounts;
  final List<Store> stores;
  final AppUser? me;

  @override
  Widget build(BuildContext context) {
    final admins = accounts
        .where((u) => u.isActive && u.role == UserRole.admin)
        .toList();
    final inactive = accounts.where((u) => !u.isActive).toList();
    List<AppUser> staffOf(int storeId) =>
        accounts
            .where((u) => u.isActive && !u.isAdmin && u.storeId == storeId)
            .toList()
          ..sort((a, b) => a.role.index.compareTo(b.role.index));

    final sections = [
      if (admins.isNotEmpty)
        _section(
          context,
          'Admin',
          admins,
          'Admin tidak terikat toko: bisa membuka semua menu dan mengelola '
              'akun.',
        ),
      for (final store in stores)
        if (store.isActive || staffOf(store.id).isNotEmpty)
          _section(
            context,
            store.isActive ? store.name : '${store.name} (nonaktif)',
            staffOf(store.id),
            staffOf(store.id).isEmpty
                ? 'Belum ada supervisor atau kasir di toko ini.'
                : 'Supervisor: Kasir + Stok. Kasir: hanya layar Kasir.',
          ),
      if (inactive.isNotEmpty)
        _section(
          context,
          'Nonaktif',
          inactive,
          'Akun nonaktif tidak bisa login. Ketuk untuk mengaktifkan lagi.',
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final s in sections) ...[s, const SizedBox(height: AppSpacing.xl)],
      ],
    );
  }

  Widget _section(
    BuildContext context,
    String header,
    List<AppUser> users,
    String footer,
  ) {
    return InsetGroupedSection(
      header: header,
      footer: footer,
      dividerIndent: 64,
      children: [
        for (final u in users)
          InsetGroupedTile(
            leading: Opacity(
              opacity: u.isActive ? 1 : 0.45,
              child: UserAvatar(user: u, size: 36),
            ),
            title: u.id == me?.id ? '${u.fullName} (Anda)' : u.fullName,
            subtitle: _subtitle(u),
            trailing: RoleBadge(role: u.role),
            showChevron: true,
            onPressed: () => showAccountFormSheet(context, existing: u),
          ),
      ],
    );
  }

  String _subtitle(AppUser u) {
    final last = u.lastLoginAt == null
        ? 'Belum pernah masuk'
        : 'Terakhir masuk ${Fmt.dateTime(u.lastLoginAt!)}';
    return '@${u.username} · $last';
  }
}
