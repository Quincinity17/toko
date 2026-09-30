import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_card.dart';
import 'pressable_scale.dart';

class SidebarDestination {
  const SidebarDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.path,
    this.shortcutHint,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String path;
  final String? shortcutHint;
}

/// Sidebar kaca bergaya iPadOS/macOS yang bisa diciutkan menjadi ikon saja.
class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.collapsed,
    required this.onToggleCollapsed,
    this.header,
    this.footer,
  });

  final List<SidebarDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;

  /// Konten atas saat terbuka (misalnya nama toko).
  final Widget? header;

  /// Konten bawah (misalnya info user yang login).
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedContainer(
      duration: AppDurations.slow,
      curve: SpringCurve.smooth,
      width: collapsed ? AppSizes.sidebarCollapsed : AppSizes.sidebarExpanded,
      child: GlassPanel(
        border: Border(right: BorderSide(color: c.separator, width: 0.5)),
        child: SafeArea(
          right: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TopRow(
                  collapsed: collapsed,
                  onToggle: onToggleCollapsed,
                  header: header,
                ),
                const SizedBox(height: AppSpacing.lg),
                for (var i = 0; i < destinations.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: _SidebarItem(
                      destination: destinations[i],
                      selected: i == selectedIndex,
                      collapsed: collapsed,
                      onPressed: () => onSelected(i),
                    ),
                  ),
                const Spacer(),
                ?footer,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopRow extends StatelessWidget {
  const _TopRow({required this.collapsed, required this.onToggle, this.header});

  final bool collapsed;
  final VoidCallback onToggle;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final toggle = Tooltip(
      message: collapsed ? 'Tampilkan sidebar' : 'Sembunyikan sidebar',
      child: PressableScale(
        onPressed: onToggle,
        pressedScale: 0.9,
        borderRadius: AppRadius.smAll,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(CupertinoIcons.sidebar_left, size: 22, color: c.accent),
        ),
      ),
    );

    return SizedBox(
      height: 40,
      child: collapsed
          ? Center(child: toggle)
          : Row(
              children: [
                const SizedBox(width: AppSpacing.xs),
                Expanded(child: header ?? const SizedBox.shrink()),
                toggle,
              ],
            ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.destination,
    required this.selected,
    required this.collapsed,
    required this.onPressed,
  });

  final SidebarDestination destination;
  final bool selected;
  final bool collapsed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = selected ? c.accent : c.label;

    final item = PressableScale(
      onPressed: onPressed,
      pressedScale: 0.96,
      borderRadius: AppRadius.mdAll,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        height: AppSizes.touchTarget,
        decoration: BoxDecoration(
          color: selected ? c.accentTint : Colors.transparent,
          borderRadius: AppRadius.mdAll,
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 2),
        child: Row(
          mainAxisAlignment: collapsed
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          children: [
            Icon(
              selected ? destination.selectedIcon : destination.icon,
              size: 22,
              color: selected ? c.accent : c.labelSecondary,
            ),
            if (!collapsed) ...[
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  softWrap: false,
                  style: AppTypography.body.copyWith(
                    color: fg,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              if (destination.shortcutHint != null)
                Text(
                  destination.shortcutHint!,
                  style: AppTypography.caption.copyWith(color: c.labelTertiary),
                ),
            ],
          ],
        ),
      ),
    );

    return collapsed
        ? Tooltip(message: destination.label, preferBelow: false, child: item)
        : item;
  }
}
