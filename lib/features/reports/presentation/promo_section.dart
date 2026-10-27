import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../products/presentation/product_form_sheet.dart';
import '../../stores/presentation/store_scope.dart';
import '../../vouchers/domain/voucher.dart';
import '../../vouchers/presentation/voucher_form_sheet.dart';
import '../data/promo_repository.dart';
import '../domain/promo_advisor.dart';

/// Laporan › Saran Promo: saran dari data penjualan & stok (tidak mengikuti
/// filter tanggal; rentang analisa tetap, lihat [PromoAdvisor]).
class PromoSection extends ConsumerWidget {
  const PromoSection({super.key});

  static const _info = <PromoKind, (IconData, String)>{
    PromoKind.clearance: (
      CupertinoIcons.archivebox_fill,
      'Barang lambat laku: modal tertahan di stok '
          '(${PromoAdvisor.slowDays} hari terakhir).',
    ),
    PromoKind.bundle: (
      CupertinoIcons.cube_box_fill,
      'Barang yang sering dibeli bersamaan '
          '(${PromoAdvisor.pairDays} hari terakhir).',
    ),
    PromoKind.basket: (
      CupertinoIcons.cart_fill_badge_plus,
      'Mendorong pembeli menambah belanja '
          '(${PromoAdvisor.basketDays} hari terakhir).',
    ),
    PromoKind.quietHours: (
      CupertinoIcons.clock_fill,
      'Jam buka yang paling sepi (${PromoAdvisor.basketDays} hari terakhir).',
    ),
    PromoKind.traffic: (
      CupertinoIcons.star_fill,
      'Barang favorit dengan margin cukup tebal untuk diberi diskon kecil.',
    ),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final data = ref.watch(promoSuggestionsProvider);
    return data.when(
      loading: () => const SizedBox(height: 320, child: LoadingState()),
      error: (e, _) => ErrorBanner(message: 'Gagal menganalisa: $e'),
      data: (list) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Dihitung otomatis dari penjualan & stok '
            '${ref.watch(activeStoreProvider)?.name ?? 'semua toko'} '
            '(tidak mengikuti filter tanggal). Ini saran, bukan perintah: '
            'sesuaikan dengan kondisi toko.',
            style: AppTypography.footnote.copyWith(color: c.labelSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          if (list.isEmpty)
            Container(
              constraints: const BoxConstraints(minHeight: 260),
              alignment: Alignment.center,
              child: const EmptyState(
                icon: CupertinoIcons.lightbulb,
                title: 'Belum ada saran',
                message:
                    'Saran muncul setelah ada cukup data penjualan '
                    '(mis. ≥ 20 transaksi sebulan) atau ada barang yang '
                    'lambat laku.',
              ),
            ),
          if (ref.watch(promoResultsProvider).value case final results?
              when results.isNotEmpty) ...[
            _Header(
              kind: null,
              icon: CupertinoIcons.chart_bar_alt_fill,
              note:
                  'Penjualan per hari ${PromoResult.window} hari sebelum vs '
                  'sesudah promo dijalankan dari saran di bawah.',
            ),
            for (final r in results) ...[
              _ResultCard(result: r),
              const SizedBox(height: AppSpacing.sm),
            ],
            const SizedBox(height: AppSpacing.md),
          ],
          for (final kind in PromoKind.values)
            if (list.where((s) => s.kind == kind).toList() case final items
                when items.isNotEmpty) ...[
              _Header(kind: kind, icon: _info[kind]!.$1, note: _info[kind]!.$2),
              for (final s in items) ...[
                _SuggestionCard(suggestion: s),
                const SizedBox(height: AppSpacing.sm),
              ],
              const SizedBox(height: AppSpacing.md),
            ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.kind, required this.icon, required this.note});

  /// `null` = judul "Hasil promo".
  final PromoKind? kind;
  final IconData icon;
  final String note;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: c.accent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kind?.label ?? 'Hasil promo',
                  style: AppTypography.headline.copyWith(color: c.label),
                ),
                Text(
                  note,
                  style: AppTypography.footnote.copyWith(
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

class _SuggestionCard extends ConsumerWidget {
  const _SuggestionCard({required this.suggestion});

  final PromoSuggestion suggestion;

  Future<void> _editProduct(BuildContext context, WidgetRef ref) async {
    final p = await ref
        .read(appDatabaseProvider)
        .productsDao
        .findById(
          suggestion.productIds.first,
          storeId: ref.read(storeScopeProvider),
        );
    if (p == null || !context.mounted) return;
    await showProductFormSheet(context, existing: p);
    // Harga diubah = promo dijalankan: dicatat untuk "Hasil promo".
    final after = await ref
        .read(appDatabaseProvider)
        .productsDao
        .findById(p.id, storeId: ref.read(storeScopeProvider));
    if (after != null && after.sellingPrice != p.sellingPrice) {
      await ref
          .read(promoRepositoryProvider)
          .record(
            suggestion.kind,
            '${p.name}: ${Fmt.rupiah(p.sellingPrice)} → '
            '${Fmt.rupiah(after.sellingPrice)}',
            productId: p.id,
          );
      ref.invalidate(promoResultsProvider);
    }
    ref.invalidate(promoSuggestionsProvider);
  }

  Future<void> _createVoucher(BuildContext context, WidgetRef ref) async {
    final v = suggestion.voucher!;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await showVoucherFormSheet(
      context,
      template: Voucher(
        id: 0,
        code: v.code,
        name: v.name,
        type: VoucherType.amount,
        value: v.amount.toDouble(),
        minPurchase: v.minPurchase,
        startDate: today,
        endDate: today.add(Duration(days: v.days - 1)),
        storeId: ref.read(storeScopeProvider),
      ),
    );
    // Voucher tersimpan = promo dijalankan.
    final db = ref.read(appDatabaseProvider);
    final saved = await (db.select(
      db.vouchers,
    )..where((t) => t.code.equals(v.code))).getSingleOrNull();
    if (saved == null) return;
    await ref
        .read(promoRepositoryProvider)
        .record(PromoKind.basket, saved.name, voucherCode: saved.code);
    ref.invalidate(promoResultsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final s = suggestion;
    final admin = ref.watch(authControllerProvider)?.isAdmin ?? false;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.title,
            style: AppTypography.body.copyWith(
              color: c.label,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            s.detail,
            style: AppTypography.subheadline.copyWith(color: c.label),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            s.reason,
            style: AppTypography.footnote.copyWith(color: c.labelSecondary),
          ),
          if (admin && (s.voucher != null || s.kind == PromoKind.clearance))
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Align(
                alignment: Alignment.centerLeft,
                child: s.voucher != null
                    ? AppButton(
                        label: 'Buat Voucher',
                        icon: CupertinoIcons.ticket,
                        variant: AppButtonVariant.tinted,
                        size: AppButtonSize.small,
                        onPressed: () => _createVoucher(context, ref),
                      )
                    : AppButton(
                        label: 'Ubah Harga',
                        icon: CupertinoIcons.pencil,
                        variant: AppButtonVariant.tinted,
                        size: AppButtonSize.small,
                        onPressed: () => _editProduct(context, ref),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});

  final PromoResult result;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = result;
    String perDay(double v) =>
        Fmt.number(v >= 10 ? v.roundToDouble() : (v * 10).round() / 10);
    final change = r.change;
    final String detail;
    final Color tone;
    if (r.isVoucher) {
      detail =
          'Dipakai ${r.uses}× · potongan ${Fmt.rupiah(r.discount)}'
          '${r.basketBefore == null || r.basketAfter == null ? '' : ' · rata-rata belanja ${Fmt.rupiah(r.basketBefore!)} → ${Fmt.rupiah(r.basketAfter!)}'}';
      tone = (r.basketAfter ?? 0) > (r.basketBefore ?? 0)
          ? c.success
          : c.labelSecondary;
    } else {
      detail =
          'Laku ${perDay(r.perDayBefore)}/hari → ${perDay(r.perDayAfter)}/hari'
          '${change == null ? '' : ' (${change >= 0 ? '+' : ''}${Fmt.number((change * 100).round())}%)'}'
          ' · omzet sesudah ${Fmt.rupiah(r.revenueAfter)}';
      tone = (change ?? (r.qtyAfter > 0 ? 1 : 0)) > 0 ? c.success : c.warning;
    }
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            r.title,
            style: AppTypography.body.copyWith(
              color: c.label,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            '${r.kind.label} · dijalankan ${Fmt.dayShort(r.at)} '
            '(${r.daysAfter} hari)',
            style: AppTypography.footnote.copyWith(color: c.labelSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(detail, style: AppTypography.subheadline.copyWith(color: tone)),
        ],
      ),
    );
  }
}
