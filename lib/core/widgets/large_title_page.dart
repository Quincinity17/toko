import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_card.dart';
import 'pressable_scale.dart';

/// Kerangka halaman bergaya iPadOS: judul besar di atas konten yang ikut
/// tergulir, lalu toolbar kaca dengan judul kecil muncul saat digulir ke bawah.
///
/// Isi halaman diberikan sebagai [slivers], atau [child] untuk konten biasa.
class LargeTitlePage extends StatefulWidget {
  const LargeTitlePage({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.bottom,
    this.slivers,
    this.child,
    this.backLabel,
    this.onBack,
  }) : assert(slivers != null || child != null);

  final String title;
  final String? subtitle;

  /// Tombol di kanan judul (misalnya Tambah, Import).
  final List<Widget> actions;

  /// Widget di bawah judul besar, biasanya kolom pencarian atau segmented
  /// control.
  final Widget? bottom;
  final List<Widget>? slivers;
  final Widget? child;

  /// Jika diisi, muncul tautan kembali "‹ [backLabel]" di atas judul,
  /// untuk sub-halaman seperti Pengaturan › Kelola Akun.
  final String? backLabel;
  final VoidCallback? onBack;

  @override
  State<LargeTitlePage> createState() => _LargeTitlePageState();
}

class _LargeTitlePageState extends State<LargeTitlePage> {
  static const _collapseOffset = 44.0;
  final _scroll = ScrollController();
  bool _collapsed = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final collapsed = _scroll.offset > _collapseOffset;
      if (collapsed != _collapsed) setState(() => _collapsed = collapsed);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const gutter = AppSpacing.pageGutter;

    return ColoredBox(
      color: c.background,
      child: Stack(
        children: [
          Scrollbar(
            controller: _scroll,
            child: CustomScrollView(
              controller: _scroll,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    gutter,
                    AppSpacing.xxxl + 8,
                    gutter,
                    AppSpacing.md,
                  ),
                  sliver: SliverToBoxAdapter(child: _buildHeader(c)),
                ),
                if (widget.bottom != null)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      gutter,
                      0,
                      gutter,
                      AppSpacing.lg,
                    ),
                    sliver: SliverToBoxAdapter(child: widget.bottom),
                  ),
                if (widget.slivers != null)
                  for (final s in widget.slivers!)
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: gutter),
                      sliver: s,
                    )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: gutter),
                    sliver: SliverFillRemaining(
                      hasScrollBody: false,
                      child: widget.child,
                    ),
                  ),
                const SliverToBoxAdapter(
                  child: SizedBox(height: AppSpacing.xxxl),
                ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: !_collapsed,
              child: AnimatedOpacity(
                opacity: _collapsed ? 1 : 0,
                duration: AppDurations.fast,
                child: _buildCompactBar(c),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(AppColors c) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.onBack != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: _BackLink(
                    label: widget.backLabel ?? 'Kembali',
                    onPressed: widget.onBack!,
                  ),
                ),
              Text(
                widget.title,
                style: AppTypography.largeTitle.copyWith(color: c.label),
              ),
              if (widget.subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    widget.subtitle!,
                    style: AppTypography.subheadline.copyWith(
                      color: c.labelSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        ..._spaced(widget.actions),
      ],
    );
  }

  Widget _buildCompactBar(AppColors c) {
    return GlassPanel(
      tint: c.background,
      border: Border(bottom: BorderSide(color: c.separator, width: 0.5)),
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.pageGutter,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (widget.onBack != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: _BackLink(
                    label: widget.backLabel ?? 'Kembali',
                    onPressed: widget.onBack!,
                  ),
                ),
              Text(
                widget.title,
                style: AppTypography.headline.copyWith(color: c.label),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _spaced(List<Widget> items) => [
    for (final a in items) ...[const SizedBox(width: AppSpacing.xs), a],
  ];
}

class _BackLink extends StatelessWidget {
  const _BackLink({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PressableScale(
      onPressed: onPressed,
      pressedScale: 0.96,
      showHover: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.chevron_back, size: 20, color: c.accent),
            Text(label, style: AppTypography.body.copyWith(color: c.accent)),
          ],
        ),
      ),
    );
  }
}
