import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/state_views.dart';
import '../../domain/cart.dart';

/// Lebar kolom tabel keranjang. `null` = mengisi sisa ruang.
const _cols = <(String, double?, TextAlign)>[
  ('No', 36, TextAlign.left),
  ('Barcode', 120, TextAlign.left),
  ('Nama Barang', null, TextAlign.left),
  ('Jumlah', 132, TextAlign.center),
  ('Satuan', 64, TextAlign.left),
  ('Harga', 110, TextAlign.right),
  ('Total', 130, TextAlign.right),
  ('', 44, TextAlign.center),
];

/// Tabel barang di keranjang, mirip daftar item di iPOS tapi bergaya iOS.
class CartTable extends StatelessWidget {
  const CartTable({
    super.key,
    required this.cart,
    required this.selectedIndex,
    required this.scrollController,
    required this.onSelect,
    required this.onQtyChanged,
    required this.onEditQty,
    required this.onRemove,
    this.onChangeUnit,
    this.canReduce = true,
  });

  final Cart cart;

  /// `false` = tidak punya hak mengurangi/menghapus barang: tombol − mati
  /// dan tombol hapus disembunyikan.
  final bool canReduce;
  final int? selectedIndex;
  final ScrollController scrollController;
  final ValueChanged<int> onSelect;
  final void Function(int index, double qty) onQtyChanged;
  final ValueChanged<int> onEditQty;
  final ValueChanged<int> onRemove;

  /// Ganti satuan baris (hanya barang yang punya satuan lain).
  final ValueChanged<int>? onChangeUnit;

  /// Di bawah lebar ini (HP) keranjang tampil sebagai daftar ringkas.
  static const compactWidth = 560.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < compactWidth;
        return _build(c, compact);
      },
    );
  }

  Widget _build(AppColors c, bool compact) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          if (!compact) ...[
            _Header(),
            Container(height: 0.5, color: c.separator),
          ],
          Expanded(
            child: cart.isEmpty
                ? EmptyState(
                    icon: CupertinoIcons.barcode_viewfinder,
                    title: 'Belum ada barang',
                    message: compact
                        ? 'Scan atau ketik barcode, atau ketuk ikon cari '
                              'untuk mencari berdasarkan nama.'
                        : 'Scan atau ketik barcode barang lalu tekan Enter. '
                              'Tekan F3 untuk mencari berdasarkan nama.',
                  )
                : ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: cart.lines.length,
                    separatorBuilder: (_, _) => Padding(
                      padding: EdgeInsets.only(left: compact ? 16 : 52),
                      child: Container(height: 0.5, color: c.separator),
                    ),
                    itemBuilder: (context, i) => _Row(
                      compact: compact,
                      key: ValueKey(
                        '${cart.lines[i].product.id}-${cart.lines[i].unit?.id}',
                      ),
                      index: i,
                      line: cart.lines[i],
                      selected: i == selectedIndex,
                      onTap: () => onSelect(i),
                      onMinus: canReduce
                          ? () => onQtyChanged(i, cart.lines[i].qty - 1)
                          : null,
                      onPlus: () => onQtyChanged(i, cart.lines[i].qty + 1),
                      onEditQty: () => onEditQty(i),
                      onRemove: canReduce ? () => onRemove(i) : null,
                      onChangeUnit:
                          onChangeUnit == null ||
                              cart.lines[i].product.units.isEmpty
                          ? null
                          : () => onChangeUnit!(i),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Row(
        children: [
          for (final (label, width, align) in _cols)
            _cell(
              width,
              Text(
                label.toUpperCase(),
                textAlign: align,
                style: AppTypography.caption.copyWith(
                  color: c.labelSecondary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Widget _cell(double? width, Widget child) => width == null
    ? Expanded(child: child)
    : SizedBox(width: width, child: child);

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    this.compact = false,
    required this.index,
    required this.line,
    required this.selected,
    required this.onTap,
    required this.onMinus,
    required this.onPlus,
    required this.onEditQty,
    required this.onRemove,
    this.onChangeUnit,
  });

  /// HP: nama + barcode·harga, ± jumlah, total. Hapus barang = kurangi
  /// sampai 0.
  final bool compact;
  final int index;
  final CartLine line;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onMinus;
  final VoidCallback onPlus;
  final VoidCallback onEditQty;
  final VoidCallback? onRemove;
  final VoidCallback? onChangeUnit;

  /// Keterangan harga grosir / stok di bawah nama barang.
  List<Widget> _notes(AppColors c) {
    final caption = AppTypography.caption;
    final tier = line.tier;
    final next = line.nextTier;
    return [
      if (tier != null)
        Text(
          'Harga grosir (min. ${Fmt.number(tier.minQty)})',
          style: caption.copyWith(color: c.success),
        )
      else if (next != null)
        Text(
          'Grosir ${Fmt.number(next.price)} mulai ${Fmt.number(next.minQty)}',
          style: caption.copyWith(color: c.labelSecondary),
        ),
      if (line.exceedsStock)
        Text(
          'Stok tercatat ${Fmt.number(line.product.stock)}'
          '${line.unit == null ? '' : ' ${line.product.unitName ?? ''}'.trimRight()}',
          style: caption.copyWith(color: c.warning),
        ),
    ];
  }

  Widget _unit(AppColors c, TextStyle body) {
    final name = line.unitName ?? '–';
    if (onChangeUnit == null) {
      return Text(name, style: body.copyWith(color: c.labelSecondary));
    }
    return Tooltip(
      message: 'Ganti satuan',
      child: PressableScale(
        onPressed: onChangeUnit,
        pressedScale: 0.92,
        borderRadius: AppRadius.smAll,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: body.copyWith(
                  color: c.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(CupertinoIcons.chevron_down, size: 11, color: c.accent),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final body = AppTypography.subheadline.copyWith(color: c.label);
    final num = body.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final p = line.product;

    final row = PressableScale(
      onPressed: onTap,
      pressedScale: 1,
      borderRadius: AppRadius.smAll,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        constraints: const BoxConstraints(minHeight: 52),
        decoration: BoxDecoration(
          color: selected ? c.accentTint : Colors.transparent,
          borderRadius: AppRadius.smAll,
        ),
        child: compact
            ? _compactRow(c, body, num)
            : Row(
                children: [
                  _cell(
                    _cols[0].$2,
                    Text(
                      '${index + 1}',
                      style: num.copyWith(color: c.labelSecondary),
                    ),
                  ),
                  _cell(
                    _cols[1].$2,
                    Text(
                      p.code,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: num.copyWith(color: c.labelSecondary),
                    ),
                  ),
                  _cell(
                    null,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: body.copyWith(fontWeight: FontWeight.w500),
                        ),
                        ..._notes(c),
                      ],
                    ),
                  ),
                  _cell(
                    _cols[3].$2,
                    _QtyStepper(
                      qty: line.qty,
                      onMinus: onMinus,
                      onPlus: onPlus,
                      onTapValue: onEditQty,
                    ),
                  ),
                  _cell(_cols[4].$2, _unit(c, body)),
                  _cell(
                    _cols[5].$2,
                    Text(
                      Fmt.number(line.price),
                      textAlign: TextAlign.right,
                      style: num,
                    ),
                  ),
                  _cell(
                    _cols[6].$2,
                    AnimatedSwitcher(
                      duration: AppDurations.medium,
                      switchInCurve: SpringCurve.bouncy,
                      transitionBuilder: (child, a) =>
                          ScaleTransition(scale: a, child: child),
                      child: Text(
                        Fmt.number(line.total),
                        key: ValueKey(line.total),
                        textAlign: TextAlign.right,
                        style: num.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  _cell(
                    _cols[7].$2,
                    onRemove == null
                        ? const SizedBox.shrink()
                        : Tooltip(
                            message: 'Hapus barang',
                            child: CupertinoButton(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(36, 36),
                              onPressed: onRemove,
                              child: Icon(
                                CupertinoIcons.minus_circle_fill,
                                size: 20,
                                color: c.danger.withValues(alpha: 0.85),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
      ),
    );

    // Animasi pegas saat barang baru masuk keranjang.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppDurations.slow,
      curve: SpringCurve.bouncy,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 12),
          child: child,
        ),
      ),
      child: row,
    );
  }

  Widget _compactRow(AppColors c, TextStyle body, TextStyle num) {
    final p = line.product;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                p.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: body.copyWith(fontWeight: FontWeight.w500),
              ),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      '${p.code} · ${Fmt.number(line.price)}'
                      '${line.unitName == null || onChangeUnit != null ? '' : '/${line.unitName}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(
                        color: c.labelSecondary,
                      ),
                    ),
                  ),
                  if (onChangeUnit != null) ...[
                    Text(
                      '/',
                      style: AppTypography.caption.copyWith(
                        color: c.labelSecondary,
                      ),
                    ),
                    _unit(c, AppTypography.caption),
                  ],
                ],
              ),
              ..._notes(c),
            ],
          ),
        ),
        SizedBox(
          width: 108,
          child: _QtyStepper(
            qty: line.qty,
            onMinus: onMinus,
            onPlus: onPlus,
            onTapValue: onEditQty,
          ),
        ),
        SizedBox(
          width: 76,
          child: Text(
            Fmt.number(line.total),
            textAlign: TextAlign.right,
            style: num.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _QtyStepper extends StatelessWidget {
  const _QtyStepper({
    required this.qty,
    required this.onMinus,
    required this.onPlus,
    required this.onTapValue,
  });

  final double qty;
  final VoidCallback? onMinus;
  final VoidCallback onPlus;
  final VoidCallback onTapValue;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget button(IconData icon, VoidCallback? onPressed) => CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(32, 32),
      onPressed: onPressed,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(color: c.fill, shape: BoxShape.circle),
        child: Icon(
          icon,
          size: 14,
          color: onPressed == null ? c.labelTertiary : c.accent,
        ),
      ),
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        button(CupertinoIcons.minus, onMinus),
        Expanded(
          child: Center(
            child: _TappableValue(
              text: Fmt.number(qty),
              color: c.label,
              bold: true,
              onTap: onTapValue,
              tooltip: 'Ketik jumlah',
            ),
          ),
        ),
        button(CupertinoIcons.plus, onPlus),
      ],
    );
  }
}

class _TappableValue extends StatelessWidget {
  const _TappableValue({
    required this.text,
    required this.color,
    required this.onTap,
    required this.tooltip,
    this.bold = false,
  });

  final String text;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: PressableScale(
        onPressed: onTap,
        pressedScale: 0.92,
        borderRadius: AppRadius.smAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(
            text,
            style: AppTypography.subheadline.copyWith(
              color: color,
              fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}
