import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:go_router/go_router.dart';

import '../../labels/presentation/label_queue.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/number_input.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../products/domain/product.dart';
import '../data/stock_repository.dart';
import '../domain/stock_adjustment.dart';

/// Riwayat stok (barang, toko), terbaru dulu.
final stockHistoryProvider = StreamProvider.autoDispose
    .family<List<StockMovement>, (int, int)>(
      (ref, key) =>
          ref.watch(stockRepositoryProvider).watchHistory(key.$1, key.$2),
    );

/// Popup menyesuaikan stok [product] di toko [storeId], dengan riwayatnya.
Future<void> showStockAdjustDialog(
  BuildContext context, {
  required Product product,
  required int storeId,
}) {
  return AppDialogs.popup<void>(
    context,
    title: product.name,
    maxWidth: 560,
    autofocusRoot: false,
    builder: (_) => _AdjustForm(product: product, storeId: storeId),
  );
}

class _AdjustForm extends ConsumerStatefulWidget {
  const _AdjustForm({required this.product, required this.storeId});

  final Product product;
  final int storeId;

  @override
  ConsumerState<_AdjustForm> createState() => _AdjustFormState();
}

class _AdjustFormState extends ConsumerState<_AdjustForm> {
  final _qty = TextEditingController();
  final _qtyFocus = FocusNode();
  final _note = TextEditingController();
  StockAdjustMode _mode = StockAdjustMode.receive;
  bool _saving = false;
  String? _error;

  double get _current => widget.product.stock;
  double? get _qtyValue =>
      _qty.text.trim().isEmpty ? null : parseIdNumber(_qty.text);

  @override
  void dispose() {
    _qty.dispose();
    _qtyFocus.dispose();
    _note.dispose();
    super.dispose();
  }

  void _setMode(StockAdjustMode m) {
    setState(() {
      _mode = m;
      _error = null;
    });
    _qtyFocus.requestFocus();
  }

  /// [labels]: setelah barang masuk tersimpan, barang ditambahkan ke
  /// daftar Cetak Label sebanyak jumlah yang masuk, lalu halamannya dibuka.
  Future<void> _save({bool labels = false}) async {
    final qty = _qtyValue;
    if (_saving) return;
    if (qty == null) {
      setState(() => _error = 'Isi ${_mode.qtyLabel.toLowerCase()}.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(stockRepositoryProvider)
          .adjust(
            actor: ref.read(authControllerProvider)!,
            storeId: widget.storeId,
            productId: widget.product.id,
            mode: _mode,
            qty: qty,
            note: _note.text,
          );
      if (!mounted) return;
      final router = GoRouter.of(context);
      Navigator.pop(context);
      if (labels) {
        ref
            .read(labelQueueProvider.notifier)
            .addProduct(widget.product, copies: qty.ceil());
        router.go(AppRoutes.cetakLabel);
      }
    } on StockFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final unit = widget.product.unitName ?? '';
    final qty = _qtyValue;
    final after = qty == null ? null : _current + _mode.delta(_current, qty);
    const tabular = [FontFeature.tabularFigures()];
    final history = ref.watch(
      stockHistoryProvider((widget.storeId, widget.product.id)),
    );
    // Tanpa hak "Ubah stok": hanya stok sekarang + riwayat.
    final canAdjust =
        ref.watch(authControllerProvider)?.canAdjustStockAt(widget.storeId) ??
        false;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: c.fillSecondary,
              borderRadius: AppRadius.mdAll,
            ),
            child: Row(
              children: [
                Text(
                  'Stok sekarang',
                  style: AppTypography.headline.copyWith(color: c.label),
                ),
                const Spacer(),
                Text(
                  '${Fmt.number(_current)} $unit'.trim(),
                  style: AppTypography.title2.copyWith(
                    color: c.label,
                    fontFeatures: tabular,
                  ),
                ),
              ],
            ),
          ),
          if (!canAdjust) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Anda hanya bisa melihat stok. Mengubah stok perlu hak akses '
              '"Ubah stok" dari admin.',
              style: AppTypography.footnote.copyWith(color: c.labelSecondary),
            ),
          ] else ...[
            const SizedBox(height: AppSpacing.md),
            CupertinoSlidingSegmentedControl<StockAdjustMode>(
              groupValue: _mode,
              padding: const EdgeInsets.all(3),
              onValueChanged: (m) {
                if (m != null) _setMode(m);
              },
              children: {
                for (final m in StockAdjustMode.values)
                  m: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(m.label, style: AppTypography.subheadline),
                  ),
              },
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: _qty,
              focusNode: _qtyFocus,
              autofocus: true,
              label: unit.isEmpty
                  ? _mode.qtyLabel
                  : '${_mode.qtyLabel} ($unit)',
              placeholder: '0',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _save(),
            ),
            if (after != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Stok menjadi ${Fmt.number(after)} $unit'.trim(),
                style: AppTypography.footnote.copyWith(
                  color: after < 0 ? c.warning : c.labelSecondary,
                  fontFeatures: tabular,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: _note,
              label: 'Catatan (opsional)',
              placeholder: switch (_mode) {
                StockAdjustMode.receive => 'mis. kiriman supplier',
                StockAdjustMode.remove => 'mis. rusak, kedaluwarsa',
                StockAdjustMode.count => 'mis. opname akhir bulan',
              },
              onSubmitted: (_) => _save(),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              ErrorBanner(message: _error!),
            ],
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'Simpan',
              icon: CupertinoIcons.checkmark_alt,
              size: AppButtonSize.large,
              expand: true,
              loading: _saving,
              onPressed: _save,
            ),
            if (_mode == StockAdjustMode.receive &&
                (ref
                        .watch(authControllerProvider)
                        ?.canAccess(AppRoutes.cetakLabel) ??
                    false)) ...[
              const SizedBox(height: AppSpacing.xs),
              AppButton(
                label: 'Simpan & Cetak Label',
                icon: CupertinoIcons.tag,
                variant: AppButtonVariant.plain,
                expand: true,
                onPressed: _saving ? null : () => _save(labels: true),
              ),
            ],
          ],
          const SizedBox(height: AppSpacing.xl),
          Text(
            'RIWAYAT STOK',
            style: AppTypography.footnote.copyWith(
              color: c.labelSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          history.when(
            loading: () => const SizedBox(height: 48, child: LoadingState()),
            error: (e, _) => ErrorBanner(message: '$e'),
            data: (list) => list.isEmpty
                ? Text(
                    'Belum ada riwayat di toko ini.',
                    style: AppTypography.footnote.copyWith(
                      color: c.labelTertiary,
                    ),
                  )
                : Column(children: [for (final m in list) _HistoryRow(m)]),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow(this.m);

  final StockMovement m;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final muted = AppTypography.caption.copyWith(color: c.labelSecondary);
    final up = m.change > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.note ?? m.typeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.subheadline.copyWith(color: c.label),
                ),
                Text(
                  [
                    DateFormat('d MMM HH:mm', 'id_ID').format(m.date),
                    m.typeLabel,
                    ?m.userName,
                  ].join(' · '),
                  style: muted,
                ),
              ],
            ),
          ),
          Text(
            '${up ? '+' : '−'}${Fmt.number(m.change.abs())}',
            style: AppTypography.subheadline.copyWith(
              color: up ? c.success : c.labelSecondary,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
