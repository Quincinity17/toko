import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/choice_chips.dart';
import '../../../core/widgets/data_table_card.dart';
import '../../../core/widgets/inset_grouped_list.dart';
import '../../../core/widgets/state_views.dart';
import '../../reports/domain/report_models.dart';
import '../../reports/presentation/report_sections.dart' show SectionTitle;
import '../data/audit_repository.dart';
import '../data/integrity_service.dart';
import '../domain/audit_entry.dart';

typedef _Key = ({ReportRange range, int? storeId});

final _entriesProvider = FutureProvider.autoDispose
    .family<List<AuditEntry>, _Key>(
      (ref, k) => ref
          .watch(auditRepositoryProvider)
          .between(k.range.start, k.range.end, storeId: k.storeId),
    );

final _attentionProvider = FutureProvider.autoDispose
    .family<List<AttentionSummary>, _Key>(
      (ref, k) => ref
          .watch(auditRepositoryProvider)
          .attention(k.range.start, k.range.end, storeId: k.storeId),
    );

/// Pemeriksaan keutuhan (seluruh data perangkat, tidak tergantung rentang).
final integrityReportProvider = FutureProvider.autoDispose<IntegrityReport>(
  (ref) => ref.watch(integrityServiceProvider).check(),
);

/// Filter daftar catatan.
enum _Filter { attention, all, cashier, login, products, accounts, system }

extension on _Filter {
  String get label => switch (this) {
    _Filter.attention => 'Perlu perhatian',
    _Filter.all => 'Semua',
    _Filter.cashier => AuditCategory.cashier.label,
    _Filter.login => AuditCategory.login.label,
    _Filter.products => AuditCategory.products.label,
    _Filter.accounts => AuditCategory.accounts.label,
    _Filter.system => AuditCategory.system.label,
  };

  bool matches(AuditEntry e) => switch (this) {
    _Filter.attention => e.type.needsAttention,
    _Filter.all => true,
    _Filter.cashier => e.type.category == AuditCategory.cashier,
    _Filter.login => e.type.category == AuditCategory.login,
    _Filter.products => e.type.category == AuditCategory.products,
    _Filter.accounts => e.type.category == AuditCategory.accounts,
    _Filter.system => e.type.category == AuditCategory.system,
  };
}

/// Laporan › Aktivitas (admin): keutuhan data, tindakan yang perlu
/// diperhatikan per kasir, dan catatan aktivitas lengkap.
class ActivitySection extends ConsumerStatefulWidget {
  const ActivitySection({super.key, required this.range, this.storeId});

  final ReportRange range;
  final int? storeId;

  @override
  ConsumerState<ActivitySection> createState() => _ActivitySectionState();
}

class _ActivitySectionState extends ConsumerState<ActivitySection> {
  _Filter _filter = _Filter.attention;

  static const _gap = SizedBox(height: AppSpacing.xl);
  static const _listLimit = 300;

  @override
  Widget build(BuildContext context) {
    final key = (range: widget.range, storeId: widget.storeId);
    final entries = ref.watch(_entriesProvider(key));
    final attention = ref.watch(_attentionProvider(key));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle(
          'Keutuhan data',
          subtitle:
              'Mendeteksi data yang diubah di luar aplikasi (faktur, akun, '
              'harga, stok, catatan aktivitas).',
        ),
        const _IntegrityCard(),
        _gap,
        const SectionTitle(
          'Perlu perhatian',
          subtitle:
              'Tindakan yang tidak meninggalkan faktur atau bisa dipakai '
              'curang, per akun.',
        ),
        attention.when(
          loading: () => const SizedBox(height: 120, child: LoadingState()),
          error: (e, _) => ErrorBanner(message: '$e'),
          data: _attentionTable,
        ),
        _gap,
        const SectionTitle('Catatan aktivitas'),
        ChoiceChips<_Filter>(
          values: _Filter.values,
          selected: _filter,
          label: (f) => f.label,
          onSelected: (f) => setState(() => _filter = f),
          subtle: true,
        ),
        const SizedBox(height: AppSpacing.sm),
        entries.when(
          loading: () => const SizedBox(height: 200, child: LoadingState()),
          error: (e, _) => ErrorBanner(message: '$e'),
          data: _entryTable,
        ),
      ],
    );
  }

  Widget _attentionTable(List<AttentionSummary> list) {
    String count(AttentionSummary s, AuditType t) =>
        s.counts[t] == null ? '–' : Fmt.number(s.counts[t]!);
    if (AppBreakpoints.isCompact(context)) {
      // HP: daftar, satu baris per akun.
      String part(AttentionSummary s, AuditType t, String label, [int? v]) {
        final n = s.counts[t];
        if (n == null) return '';
        return '$label $n${v == null || v == 0 ? '' : ' (${Fmt.compact(v)})'}';
      }

      return InsetGroupedSection(
        footer: list.isEmpty
            ? 'Tidak ada tindakan yang perlu diperhatikan.'
            : 'Bandingkan dengan uang di laci; kasir yang sering membatalkan '
                  'transaksi perlu diperiksa.',
        children: [
          for (final s in list)
            InsetGroupedTile(
              title: s.userName,
              below: Text(
                [
                  part(s, AuditType.cartCleared, 'Batal', s.cartClearedValue),
                  part(s, AuditType.cartItemReduced, 'Kurangi'),
                  part(s, AuditType.drawerOpened, 'Laci'),
                  part(s, AuditType.heldCartDeleted, 'Tertahan dihapus'),
                  part(s, AuditType.saleReturn, 'Retur', s.returnValue),
                  part(s, AuditType.loginFailed, 'Login gagal'),
                  part(s, AuditType.clockBack, 'Jam mundur'),
                ].where((x) => x.isNotEmpty).join(' · '),
                style: AppTypography.footnote.copyWith(
                  color: context.colors.labelSecondary,
                ),
              ),
              value: '${s.total}',
            ),
          if (list.isEmpty) const InsetGroupedTile(title: '–'),
        ],
      );
    }
    return DataTableCard(
      columns: const [
        TableColumnSpec('Akun', flex: 2),
        TableColumnSpec.number('Batal transaksi', width: 130),
        TableColumnSpec.number('Kurangi barang', width: 120),
        TableColumnSpec.number('Laci', width: 70),
        TableColumnSpec.number('Tertahan dihapus', width: 130),
        TableColumnSpec.number('Retur', width: 120),
        TableColumnSpec.number('Login gagal', width: 100),
      ],
      emptyMessage: 'Tidak ada tindakan yang perlu diperhatikan.',
      rows: [
        for (final s in list)
          TableRowData([
            CellText(s.userName, bold: true),
            CellText(
              s.counts[AuditType.cartCleared] == null
                  ? '–'
                  : '${s.counts[AuditType.cartCleared]} · '
                        '${Fmt.compact(s.cartClearedValue)}',
              number: true,
            ),
            CellText(count(s, AuditType.cartItemReduced), number: true),
            CellText(count(s, AuditType.drawerOpened), number: true),
            CellText(count(s, AuditType.heldCartDeleted), number: true),
            CellText(
              s.counts[AuditType.saleReturn] == null
                  ? '–'
                  : '${s.counts[AuditType.saleReturn]} · '
                        '${Fmt.compact(s.returnValue)}',
              number: true,
            ),
            CellText(count(s, AuditType.loginFailed), number: true),
          ]),
      ],
      footer:
          'Batal transaksi & retur: jumlah · nilai. Bandingkan dengan uang di '
          'laci; kasir yang sering membatalkan transaksi perlu diperiksa.',
    );
  }

  Widget _entryTable(List<AuditEntry> all) {
    final c = context.colors;
    final list = all.where(_filter.matches).toList();
    final time = DateFormat('d MMM HH:mm', 'id_ID');
    if (AppBreakpoints.isCompact(context)) {
      return InsetGroupedSection(
        footer: list.isEmpty
            ? 'Tidak ada catatan pada periode ini.'
            : list.length > _listLimit
            ? 'Menampilkan $_listLimit dari ${Fmt.number(list.length)} '
                  'catatan terbaru.'
            : null,
        children: [
          for (final e in list.take(_listLimit))
            InsetGroupedTile(
              title: e.type.label,
              subtitle: '${time.format(e.at)} · ${e.userName ?? '–'}',
              below: Text(
                e.summary,
                style: AppTypography.footnote.copyWith(color: c.label),
              ),
            ),
          if (list.isEmpty) const InsetGroupedTile(title: '–'),
        ],
      );
    }
    return DataTableCard(
      columns: const [
        TableColumnSpec('Waktu', width: 110),
        TableColumnSpec('Jenis', width: 180),
        TableColumnSpec('Oleh', width: 130),
        TableColumnSpec('Keterangan', flex: 3),
      ],
      emptyMessage: 'Tidak ada catatan pada periode ini.',
      rows: [
        for (final e in list.take(_listLimit))
          TableRowData([
            CellText(time.format(e.at), muted: true),
            CellText(
              e.type.label,
              bold: e.type.needsAttention,
              color: e.type.needsAttention ? c.warning : null,
            ),
            CellText(e.userName ?? '–', muted: true),
            CellText(e.summary),
          ]),
      ],
      footer: list.length > _listLimit
          ? 'Menampilkan $_listLimit dari ${Fmt.number(list.length)} catatan '
                'terbaru.'
          : null,
    );
  }
}

class _IntegrityCard extends ConsumerWidget {
  const _IntegrityCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final async = ref.watch(integrityReportProvider);
    return AppCard(
      child: async.when(
        loading: () => const SizedBox(height: 80, child: LoadingState()),
        error: (e, _) => ErrorBanner(message: 'Gagal memeriksa: $e'),
        data: (r) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  r.ok
                      ? CupertinoIcons.checkmark_shield_fill
                      : CupertinoIcons.exclamationmark_shield_fill,
                  color: r.ok
                      ? c.success
                      : r.issues.any(
                          (i) => i.severity == IntegritySeverity.danger,
                        )
                      ? c.danger
                      : c.warning,
                  size: 28,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.ok
                            ? 'Data utuh'
                            : '${r.issues.length} masalah ditemukan',
                        style: AppTypography.headline.copyWith(color: c.label),
                      ),
                      Text(
                        'Diperiksa ${Fmt.dateTime(r.checkedAt)} · '
                        '${Fmt.number(r.auditRows)} catatan, '
                        '${Fmt.number(r.sales)} faktur, '
                        '${Fmt.number(r.sealedRows)} data bersegel'
                        '${r.since == null ? '' : ' sejak ${Fmt.dateTime(r.since!)}'}',
                        style: AppTypography.footnote.copyWith(
                          color: c.labelSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                AppButton(
                  label: 'Periksa Ulang',
                  icon: CupertinoIcons.arrow_clockwise,
                  variant: AppButtonVariant.gray,
                  size: AppButtonSize.small,
                  onPressed: () => ref.invalidate(integrityReportProvider),
                ),
              ],
            ),
            for (final i in r.issues) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(height: 0.5, color: c.separator),
              const SizedBox(height: AppSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    i.severity == IntegritySeverity.danger
                        ? CupertinoIcons.xmark_octagon_fill
                        : CupertinoIcons.exclamationmark_triangle_fill,
                    size: 18,
                    color: i.severity == IntegritySeverity.danger
                        ? c.danger
                        : c.warning,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          i.title,
                          style: AppTypography.subheadline.copyWith(
                            color: c.label,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (i.detail != null)
                          Text(
                            i.detail!,
                            style: AppTypography.footnote.copyWith(
                              color: c.labelSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
