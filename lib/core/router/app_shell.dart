import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
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
];

/// Kerangka utama: sidebar di kiri, halaman aktif di kanan.
///
/// Shortcut: Ctrl+1..5 pindah halaman, Ctrl+\ ciutkan sidebar.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final collapsed = ref.watch(sidebarCollapsedProvider);
    final selected = appDestinations.indexWhere(
      (d) => location.startsWith(d.path),
    );

    void go(int i) => context.go(appDestinations[i].path);

    return CallbackShortcuts(
      bindings: {
        for (var i = 0; i < appDestinations.length; i++)
          SingleActivator(_digitKeys[i], control: true): () => go(i),
        const SingleActivator(
          LogicalKeyboardKey.backslash,
          control: true,
        ): () =>
            ref.read(sidebarCollapsedProvider.notifier).toggle(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: c.background,
          body: Row(
            children: [
              AppSidebar(
                destinations: appDestinations,
                selectedIndex: selected,
                onSelected: go,
                collapsed: collapsed,
                onToggleCollapsed: () =>
                    ref.read(sidebarCollapsedProvider.notifier).toggle(),
                header: const _StoreHeader(),
                footer: _UserFooter(collapsed: collapsed),
              ),
              Expanded(child: ClipRect(child: child)),
            ],
          ),
        ),
      ),
    );
  }
}

class _StoreHeader extends StatelessWidget {
  const _StoreHeader();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
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
            'Toko',
            maxLines: 1,
            overflow: TextOverflow.clip,
            softWrap: false,
            style: AppTypography.headline.copyWith(color: c.label),
          ),
        ),
      ],
    );
  }
}

/// Info user yang login. Masih data statis sampai fitur login (Langkah 2).
class _UserFooter extends StatelessWidget {
  const _UserFooter({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final avatar = CircleAvatar(
      radius: 18,
      backgroundColor: c.fill,
      child: Text(
        'A',
        style: AppTypography.headline.copyWith(color: c.labelSecondary),
      ),
    );
    if (collapsed) return Center(child: avatar);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Administrator',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.subheadline.copyWith(
                    color: c.label,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Admin',
                  style: AppTypography.caption.copyWith(
                    color: c.labelSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
