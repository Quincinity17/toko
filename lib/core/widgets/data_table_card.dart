import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_card.dart';
import 'pressable_scale.dart';

/// Kolom tabel: [width] tetap, atau [flex] berbagi sisa ruang.
class TableColumnSpec {
  const TableColumnSpec(
    this.label, {
    this.width,
    this.flex = 1,
    this.align = TextAlign.left,
  });

  /// Kolom angka: rata kanan.
  const TableColumnSpec.number(this.label, {this.width = 110, this.flex = 1})
    : align = TextAlign.right;

  final String label;
  final double? width;
  final int flex;
  final TextAlign align;
}

class TableRowData {
  const TableRowData(this.cells, {this.onTap});

  final List<Widget> cells;
  final VoidCallback? onTap;
}

/// Tabel ringkas bergaya iOS di dalam kartu: judul kolom kecil, baris
/// dipisah garis tipis, angka rata kanan dengan digit selebar sama.
class DataTableCard extends StatelessWidget {
  const DataTableCard({
    super.key,
    required this.columns,
    required this.rows,
    this.emptyMessage = 'Belum ada data pada periode ini.',
    this.footer,
  });

  final List<TableColumnSpec> columns;
  final List<TableRowData> rows;
  final String emptyMessage;
  final String? footer;

  Widget _cell(TableColumnSpec col, Widget child) {
    final aligned = Align(
      alignment: col.align == TextAlign.right
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: child,
    );
    return col.width != null
        ? SizedBox(width: col.width, child: aligned)
        : Expanded(flex: col.flex, child: aligned);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final header = AppTypography.caption.copyWith(
      color: c.labelSecondary,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    for (final col in columns)
                      _cell(
                        col,
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            col.label.toUpperCase(),
                            textAlign: col.align,
                            style: header,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Container(height: 0.5, color: c.separator),
              if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Text(
                    emptyMessage,
                    textAlign: TextAlign.center,
                    style: AppTypography.subheadline.copyWith(
                      color: c.labelSecondary,
                    ),
                  ),
                ),
              for (final (i, row) in rows.indexed) ...[
                if (i > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Container(height: 0.5, color: c.separator),
                  ),
                PressableScale(
                  onPressed: row.onTap,
                  pressedScale: 1,
                  borderRadius: BorderRadius.zero,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 11,
                    ),
                    child: Row(
                      children: [
                        for (var j = 0; j < columns.length; j++)
                          _cell(
                            columns[j],
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: j < row.cells.length
                                  ? row.cells[j]
                                  : const SizedBox.shrink(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              footer!,
              style: AppTypography.footnote.copyWith(color: c.labelSecondary),
            ),
          ),
      ],
    );
  }
}

/// Teks sel tabel. [number] = rata kanan dengan digit selebar sama.
class CellText extends StatelessWidget {
  const CellText(
    this.text, {
    super.key,
    this.number = false,
    this.bold = false,
    this.muted = false,
    this.color,
  });

  final String text;
  final bool number;
  final bool bold;
  final bool muted;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: number ? TextAlign.right : TextAlign.left,
      style: AppTypography.subheadline.copyWith(
        color: color ?? (muted ? c.labelSecondary : c.label),
        fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
        fontFeatures: number ? const [FontFeature.tabularFigures()] : null,
      ),
    );
  }
}
