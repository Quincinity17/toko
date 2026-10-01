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
  ('Kode', 104, TextAlign.left),
  ('Nama Barang', null, TextAlign.left),
  ('Jumlah', 132, TextAlign.center),
  ('Satuan', 64, TextAlign.left),
  ('Harga', 104, TextAlign.right),
  ('Pot.', 64, TextAlign.right),
  ('Total', 120, TextAlign.right),
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
    required this.onEditDiscount,
    required this.onRemove,
  });

  final Cart cart;
  final int? selectedIndex;
  final ScrollController scrollController;
  final ValueChanged<int> onSelect;
  final void Function(int index, double qty) onQtyChanged;
  final ValueChanged<int> onEditQty;
  final ValueChanged<int> onEditDiscount;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _Header(),
          Container(height: 0.5, color: c.separator),
          Expanded(
            child: cart.isEmpty
                ? const EmptyState(
                    icon: CupertinoIcons.barcode_viewfinder,
                    title: 'Belum ada barang',
                    message:
                        'Scan barcode atau ketik kode barang lalu tekan Enter. '
                        'Tekan F3 untuk mencari berdasarkan nama.',
                  )
                : ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: cart.lines.length,
                    separatorBuilder: (_, _) => Padding(
                      padding: const EdgeInsets.only(left: 52),
                      child: Container(height: 0.5, color: c.separator),
                    ),
                    itemBuilder: (context, i) => _Row(
                      key: ValueKey(cart.lines[i].product.id),
                      index: i,
                      line: cart.lines[i],
                      selected: i == selectedIndex,
                      onTap: () => onSelect(i),
                      onMinus: () => onQtyChanged(i, cart.lines[i].qty - 1),
                      onPlus: () => onQtyChanged(i, cart.lines[i].qty + 1),
                      onEditQty: () => onEditQty(i),
                      onEditDiscount: () => onEditDiscount(i),
                      onRemove: () => onRemove(i),
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
    required this.index,
    required this.line,
    required this.selected,
    required this.onTap,
    required this.onMinus,
    required this.onPlus,
    required this.onEditQty,
    required this.onEditDiscount,
    required this.onRemove,
  });

  final int index;
  final CartLine line;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onEditQty;
  final VoidCallback onEditDiscount;
  final VoidCallback onRemove;

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
        child: Row(
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
                  if (line.exceedsStock)
                    Text(
                      'Stok tercatat ${Fmt.number(p.stock)}',
                      style: AppTypography.caption.copyWith(color: c.warning),
                    ),
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
            _cell(
              _cols[4].$2,
              Text(
                p.unitName ?? '–',
                style: body.copyWith(color: c.labelSecondary),
              ),
            ),
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
              Align(
                alignment: Alignment.centerRight,
                child: _TappableValue(
                  text: line.discountPercent == 0
                      ? '–'
                      : '${Fmt.number(line.discountPercent)}%',
                  color: line.discountPercent == 0 ? c.labelTertiary : c.danger,
                  onTap: onEditDiscount,
                  tooltip: 'Ubah potongan barang',
                ),
              ),
            ),
            _cell(
              _cols[7].$2,
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
              _cols[8].$2,
              Tooltip(
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
}

class _QtyStepper extends StatelessWidget {
  const _QtyStepper({
    required this.qty,
    required this.onMinus,
    required this.onPlus,
    required this.onTapValue,
  });

  final double qty;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onTapValue;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget button(IconData icon, VoidCallback onPressed) => CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(32, 32),
      onPressed: onPressed,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(color: c.fill, shape: BoxShape.circle),
        child: Icon(icon, size: 14, color: c.accent),
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
