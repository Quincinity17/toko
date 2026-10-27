import 'package:excel/excel.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/number_input.dart';
import '../../../core/utils/save_file.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/inset_grouped_list.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/stock_repository.dart';
import '../domain/stock_alert.dart';
import 'stock_adjust_dialog.dart';

/// Daftar peringatan stok, dikelompokkan: segera ditangani, perlu dibeli,
/// cek stok nyata. Ketuk = popup ubah stok / opname di toko peringatan itu.
/// [storeId] `null` = semua toko (nama toko ditampilkan).
class StockAlertList extends ConsumerWidget {
  const StockAlertList({super.key, required this.alerts, this.storeId});

  final List<StockAlert> alerts;
  final int? storeId;

  static List<(StockAlertLevel, String, String)> _groups(
    StockAlertSettings s,
  ) => [
    (
      StockAlertLevel.danger,
      'Segera ditangani',
      'Stok minus atau habis padahal masih laku. Stok minus berarti stok '
          'tercatat tidak sesuai stok nyata: hitung fisik lalu Stok Opname.',
    ),
    (
      StockAlertLevel.warning,
      'Perlu dibeli',
      'Akan habis ≤ ${s.runningOutDays} hari. Saran beli = cukup untuk '
          '±${s.coverDays} hari penjualan (minimal 2 × stok minimum), dari '
          'penjualan ${s.days} hari terakhir.',
    ),
    (
      StockAlertLevel.check,
      'Cek stok nyata',
      'Stok tercatat kemungkinan tidak sesuai kenyataan. Cocokkan dengan '
          'fisik barang dan riwayat stoknya.',
    ),
  ];

  Future<void> _open(BuildContext context, WidgetRef ref, StockAlert a) async {
    final store = a.row.storeId ?? storeId;
    if (store == null) return;
    final p = await ref
        .read(appDatabaseProvider)
        .productsDao
        .findById(a.row.productId, storeId: store);
    if (p == null || !context.mounted) return;
    await showStockAdjustDialog(context, product: p, storeId: store);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final settings =
        ref.watch(stockAlertSettingsProvider).value ??
        const StockAlertSettings();
    final isAdmin = ref.watch(authControllerProvider)?.isAdmin ?? false;
    final buy = [
      for (final a in alerts)
        if (a.suggestedBuy != null) a,
    ];

    final toolbar = Wrap(
      spacing: AppSpacing.xs,
      children: [
        if (buy.isNotEmpty)
          AppButton(
            label: 'Daftar Belanja (${buy.length})',
            icon: CupertinoIcons.cart,
            variant: AppButtonVariant.gray,
            size: AppButtonSize.small,
            onPressed: () => showShoppingList(context, buy),
          ),
        if (isAdmin)
          AppButton(
            label: 'Atur Peringatan',
            icon: CupertinoIcons.slider_horizontal_3,
            variant: AppButtonVariant.plain,
            size: AppButtonSize.small,
            onPressed: () => AppDialogs.popup<void>(
              context,
              title: 'Atur Peringatan Stok',
              maxWidth: 460,
              autofocusRoot: false,
              builder: (_) => _SettingsForm(initial: settings),
            ),
          ),
      ],
    );

    if (alerts.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          toolbar,
          Container(
            constraints: const BoxConstraints(minHeight: 320),
            alignment: Alignment.center,
            child: EmptyState(
              icon: CupertinoIcons.checkmark_seal,
              title: 'Stok aman',
              message:
                  'Tidak ada stok minus, menipis, atau yang perlu dicek '
                  '${storeId == null ? 'di semua toko' : 'di toko ini'}.',
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        toolbar,
        const SizedBox(height: AppSpacing.sm),
        for (final (level, title, footer) in _groups(settings))
          if (alerts.where((a) => a.kind.level == level).toList()
              case final list when list.isNotEmpty) ...[
            InsetGroupedSection(
              header: '$title (${list.length})',
              footer: footer,
              children: [
                for (final a in list)
                  InsetGroupedTile(
                    title: a.row.name,
                    subtitle: [
                      a.row.code,
                      ?a.row.storeName,
                      a.kind.label,
                    ].join(' · '),
                    below: Text(
                      a.message,
                      style: AppTypography.footnote.copyWith(
                        color: c.labelSecondary,
                      ),
                    ),
                    trailing: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${Fmt.number(a.row.stock)} ${a.row.unit ?? ''}'
                              .trim(),
                          style: AppTypography.headline.copyWith(
                            color: switch (level) {
                              StockAlertLevel.danger => c.danger,
                              StockAlertLevel.warning => c.warning,
                              StockAlertLevel.check => c.label,
                            },
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        if (a.suggestedBuy case final buy?)
                          Text(
                            'Beli ±${Fmt.number(buy)}',
                            style: AppTypography.caption.copyWith(
                              color: c.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    showChevron: true,
                    onPressed: () => _open(context, ref, a),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
      ],
    );
  }
}

/// Teks daftar belanja (untuk WhatsApp / catatan), per toko bila perlu.
String shoppingListText(List<StockAlert> items, {DateTime? at}) {
  final byStore = <String?, List<StockAlert>>{};
  for (final a in items) {
    byStore.putIfAbsent(a.row.storeName, () => []).add(a);
  }
  final out = StringBuffer(
    'Daftar belanja ${Fmt.dateLong(at ?? DateTime.now())}',
  );
  for (final MapEntry(key: store, value: list) in byStore.entries) {
    out.write('\n');
    if (store != null) out.write('\n*$store*');
    for (final a in list) {
      out.write(
        '\n- ${a.row.name} (${a.row.code}): '
                '${Fmt.number(a.suggestedBuy!)} ${a.row.unit ?? ''}'
            .trimRight(),
      );
    }
  }
  return out.toString();
}

/// Daftar belanja sebagai Excel (kolom: toko, barcode, nama, stok, beli).
Uint8List shoppingListXlsx(List<StockAlert> items) {
  final book = Excel.createExcel();
  final sheet = book['Sheet1'];
  sheet.appendRow([
    for (final h in ['Toko', 'Barcode', 'Nama', 'Satuan', 'Stok', 'Beli'])
      TextCellValue(h),
  ]);
  for (final a in items) {
    sheet.appendRow([
      TextCellValue(a.row.storeName ?? ''),
      TextCellValue(a.row.code),
      TextCellValue(a.row.name),
      TextCellValue(a.row.unit ?? ''),
      DoubleCellValue(a.row.stock),
      DoubleCellValue(a.suggestedBuy ?? 0),
    ]);
  }
  sheet.setColumnWidth(2, 40);
  return Uint8List.fromList(book.encode()!);
}

Future<void> showShoppingList(BuildContext context, List<StockAlert> items) {
  final text = shoppingListText(items);
  return AppDialogs.popup<void>(
    context,
    title: 'Daftar Belanja',
    maxWidth: 520,
    builder: (ctx) {
      final c = ctx.colors;
      return Padding(
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
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: SingleChildScrollView(
                child: SelectableText(
                  text,
                  style: AppTypography.subheadline.copyWith(color: c.label),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Salin Teks',
                    icon: CupertinoIcons.doc_on_doc,
                    variant: AppButtonVariant.gray,
                    expand: true,
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: text));
                      if (ctx.mounted) {
                        await AppDialogs.alert(
                          ctx,
                          title: 'Tersalin',
                          message: 'Tempel di WhatsApp atau catatan.',
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: AppButton(
                    label: 'Simpan Excel',
                    icon: CupertinoIcons.square_arrow_down,
                    expand: true,
                    onPressed: () => saveFileAs(
                      fileName: 'daftar-belanja-${fileStamp()}.xlsx',
                      bytes: shoppingListXlsx(items),
                      extension: 'xlsx',
                      mimeType: xlsxMime,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

class _SettingsForm extends ConsumerStatefulWidget {
  const _SettingsForm({required this.initial});

  final StockAlertSettings initial;

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  late final _days = TextEditingController(text: '${widget.initial.days}');
  late final _running = TextEditingController(
    text: '${widget.initial.runningOutDays}',
  );
  late final _cover = TextEditingController(
    text: '${widget.initial.coverDays}',
  );
  late final _excessive = TextEditingController(
    text: '${widget.initial.excessiveDays}',
  );
  String? _error;

  @override
  void dispose() {
    for (final c in [_days, _running, _cover, _excessive]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _n(TextEditingController c) => parseIdNumber(c.text)?.round();

  Future<void> _save() async {
    final values = [_n(_days), _n(_running), _n(_cover), _n(_excessive)];
    if (values.any((v) => v == null || v <= 0)) {
      setState(() => _error = 'Isi semua dengan angka hari.');
      return;
    }
    try {
      await ref
          .read(stockAlertRepositoryProvider)
          .saveSettings(
            ref.read(authControllerProvider)!,
            StockAlertSettings(
              days: values[0]!,
              runningOutDays: values[1]!,
              coverDays: values[2]!,
              excessiveDays: values[3]!,
            ),
          );
      if (mounted) Navigator.pop(context);
    } on StockFailure catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController c, String label, String helper) =>
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: AppTextField(
            controller: c,
            label: label,
            helper: helper,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
        );
    const l = StockAlertSettings.limits;
    return Padding(
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
          field(
            _days,
            'Data penjualan (hari terakhir)',
            'Dasar rata-rata laku per hari (${l.days.$1}–${l.days.$2}).',
          ),
          field(
            _running,
            'Peringatan "akan habis" (hari)',
            'Muncul bila stok habis dalam sekian hari '
                '(${l.runningOutDays.$1}–${l.runningOutDays.$2}).',
          ),
          field(
            _cover,
            'Saran beli cukup untuk (hari)',
            '${l.coverDays.$1}–${l.coverDays.$2} hari.',
          ),
          field(
            _excessive,
            'Stok tidak wajar bila cukup untuk lebih dari (hari)',
            'Kemungkinan salah ketik (${l.excessiveDays.$1}–'
                '${l.excessiveDays.$2}).',
          ),
          if (_error != null) ...[
            ErrorBanner(message: _error!),
            const SizedBox(height: AppSpacing.md),
          ],
          AppButton(
            label: 'Simpan',
            size: AppButtonSize.large,
            expand: true,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
