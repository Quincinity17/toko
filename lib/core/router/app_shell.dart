import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/app_user.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/password_sheet.dart';
import '../../features/auth/presentation/widgets/user_avatar.dart';
import '../../features/stores/presentation/store_scope.dart';
import '../theme/app_theme.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/pressable_scale.dart';
import '../widgets/app_sidebar.dart';
import 'routes.dart';

class SidebarCollapsedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

final sidebarCollapsedProvider =
    NotifierProvider<SidebarCollapsedNotifier, bool>(
      SidebarCollapsedNotifier.new,
    );

const appDestinations = [
  SidebarDestination(
    label: 'Dashboard',
    icon: CupertinoIcons.square_grid_2x2,
    selectedIcon: CupertinoIcons.square_grid_2x2_fill,
    path: AppRoutes.dashboard,
  ),
  SidebarDestination(
    label: 'Kasir',
    icon: CupertinoIcons.cart,
    selectedIcon: CupertinoIcons.cart_fill,
    path: AppRoutes.kasir,
  ),
  SidebarDestination(
    label: 'Produk',
    icon: CupertinoIcons.cube_box,
    selectedIcon: CupertinoIcons.cube_box_fill,
    path: AppRoutes.produk,
  ),
  SidebarDestination(
    label: 'Stok',
    icon: CupertinoIcons.archivebox,
    selectedIcon: CupertinoIcons.archivebox_fill,
    path: AppRoutes.stok,
  ),
  SidebarDestination(
    label: 'Laporan',
    icon: CupertinoIcons.chart_bar,
    selectedIcon: CupertinoIcons.chart_bar_fill,
    path: AppRoutes.laporan,
  ),
  SidebarDestination(
    label: 'Pengaturan',
    icon: CupertinoIcons.gear,
    selectedIcon: CupertinoIcons.gear_solid,
    path: AppRoutes.pengaturan,
  ),
];

const _digitKeys = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
];

/// Kerangka utama: sidebar di kiri, halaman aktif di kanan.
///
/// Menu sidebar disaring sesuai peran user yang login.
///
/// Shortcut: Ctrl+1..6 pindah halaman, Ctrl+\ ciutkan sidebar.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final collapsed = ref.watch(sidebarCollapsedProvider);
    final user = ref.watch(authControllerProvider);
    // Saat logout, shell masih dirender sesaat sebelum router pindah ke login.
    if (user == null) return ColoredBox(color: c.background);

    final destinations = [
      for (final d in appDestinations)
        if (user.canAccess(d.path)) d,
    ];
    final selected = destinations.indexWhere(
      (d) => location.startsWith(d.path),
    );

    void go(int i) => context.go(destinations[i].path);

    return CallbackShortcuts(
      bindings: {
        for (var i = 0; i < destinations.length; i++)
          SingleActivator(_digitKeys[i], control: true): () => go(i),
        const SingleActivator(
          LogicalKeyboardKey.backslash,
          control: true,
        ): () =>
            ref.read(sidebarCollapsedProvider.notifier).toggle(),
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            // HP: sidebar jadi laci (☰). Tablet tegak: ikon saja.
            if (width < AppBreakpoints.compact) {
              return _CompactShell(
                user: user,
                destinations: destinations,
                selected: selected,
                onSelected: go,
                child: child,
              );
            }
            final narrow = collapsed || width < AppBreakpoints.medium;
            return Scaffold(
              backgroundColor: c.background,
              body: Row(
                children: [
                  AppSidebar(
                    destinations: destinations,
                    selectedIndex: selected,
                    onSelected: go,
                    collapsed: narrow,
                    onToggleCollapsed: () =>
                        ref.read(sidebarCollapsedProvider.notifier).toggle(),
                    header: _StoreHeader(user: user),
                    footer: _UserFooter(user: user, collapsed: narrow),
                  ),
                  Expanded(child: ClipRect(child: child)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Tata letak HP: bilah atas (☰ + nama toko) dan sidebar sebagai laci yang
/// tertutup setelah memilih halaman.
class _CompactShell extends StatelessWidget {
  const _CompactShell({
    required this.user,
    required this.destinations,
    required this.selected,
    required this.onSelected,
    required this.child,
  });

  final AppUser user;
  final List<SidebarDestination> destinations;
  final int selected;
  final ValueChanged<int> onSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      drawerScrimColor: CupertinoColors.black.withValues(alpha: 0.3),
      drawer: Builder(
        builder: (drawerContext) {
          void close() => Navigator.of(drawerContext).pop();
          return Drawer(
            width: AppSizes.sidebarExpanded + 16,
            backgroundColor: c.background,
            shape: const RoundedRectangleBorder(),
            child: AppSidebar(
              destinations: destinations,
              selectedIndex: selected,
              onSelected: (i) {
                close();
                onSelected(i);
              },
              collapsed: false,
              onToggleCollapsed: close,
              header: _StoreHeader(user: user),
              footer: _UserFooter(user: user, collapsed: false),
            ),
          );
        },
      ),
      body: Builder(
        builder: (scaffoldContext) => Column(
          children: [
            ColoredBox(
              color: c.background,
              child: SafeArea(
                bottom: false,
                child: SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      const SizedBox(width: AppSpacing.xs),
                      Tooltip(
                        message: 'Menu',
                        child: PressableScale(
                          onPressed: () =>
                              Scaffold.of(scaffoldContext).openDrawer(),
                          pressedScale: 0.9,
                          borderRadius: AppRadius.smAll,
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: Icon(
                              CupertinoIcons.line_horizontal_3,
                              size: 24,
                              color: c.accent,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(child: _StoreHeader(user: user)),
                      const SizedBox(width: AppSpacing.md),
                    ],
                  ),
                ),
              ),
            ),
            // Ruang aman bawah: garis navigasi gestur Android/iOS.
            Expanded(
              child: SafeArea(top: false, child: ClipRect(child: child)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Nama toko yang sedang dipakai. Admin bisa mengklik untuk berpindah toko
/// (atau "Semua toko"); supervisor/kasir selalu di tokonya sendiri.
class _StoreHeader extends ConsumerWidget {
  const _StoreHeader({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final store = ref.watch(activeStoreProvider);
    final name = store?.name ?? (user.isAdmin ? 'Semua Toko' : 'Toko');
    final row = Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: c.accent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            CupertinoIcons.bag_fill,
            size: 17,
            color: CupertinoColors.white,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: AppTypography.headline.copyWith(color: c.label),
          ),
        ),
        if (user.isAdmin)
          Icon(
            CupertinoIcons.chevron_up_chevron_down,
            size: 14,
            color: c.labelSecondary,
          ),
      ],
    );
    if (!user.isAdmin) return row;
    return Tooltip(
      message: 'Pilih toko',
      child: PressableScale(
        onPressed: () => pickStoreScope(context, ref),
        pressedScale: 0.97,
        borderRadius: AppRadius.smAll,
        child: row,
      ),
    );
  }
}

/// User yang login. Diklik untuk ganti password atau keluar.
class _UserFooter extends ConsumerWidget {
  const _UserFooter({required this.user, required this.collapsed});

  final AppUser user;
  final bool collapsed;

  Future<void> _showMenu(BuildContext context, WidgetRef ref) async {
    final action = await AppDialogs.actionSheet<String>(
      context,
      title: user.fullName,
      message: 'Masuk sebagai ${user.role.label}',
      options: [
        // Hanya admin yang boleh mengganti password (kebijakan toko).
        if (user.isAdmin)
          const ActionSheetOption(label: 'Ganti Password', value: 'password'),
        const ActionSheetOption(
          label: 'Keluar',
          value: 'logout',
          destructive: true,
        ),
      ],
    );
    if (!context.mounted) return;
    switch (action) {
      case 'password':
        await showChangeOwnPasswordSheet(context);
      case 'logout':
        ref.read(authControllerProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final avatar = UserAvatar(user: user);

    return Tooltip(
      message: collapsed ? '${user.fullName} (${user.role.label})' : '',
      child: PressableScale(
        onPressed: () => _showMenu(context, ref),
        pressedScale: 0.97,
        borderRadius: AppRadius.mdAll,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: collapsed
              ? Center(child: avatar)
              : Row(
                  children: [
                    avatar,
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.subheadline.copyWith(
                              color: c.label,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          RoleBadge(role: user.role),
                        ],
                      ),
                    ),
                    Icon(
                      CupertinoIcons.ellipsis_circle,
                      size: 20,
                      color: c.labelSecondary,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
