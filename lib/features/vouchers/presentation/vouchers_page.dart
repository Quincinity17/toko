import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/inset_grouped_list.dart';
import '../../../core/widgets/large_title_page.dart';
import '../../../core/widgets/state_views.dart';
import '../../stores/data/store_repository.dart';
import '../data/voucher_repository.dart';
import '../domain/voucher.dart';
import 'voucher_form_sheet.dart';

final vouchersProvider = StreamProvider.autoDispose<List<Voucher>>(
  (ref) => ref.watch(voucherRepositoryProvider).watchAll(),
);

/// Pengaturan › Voucher promo (khusus admin). Kasir memakai voucher dengan
/// mengetik kodenya (F7).
class VouchersPage extends ConsumerWidget {
  const VouchersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vouchers = ref.watch(vouchersProvider);

    return LargeTitlePage(
      title: 'Voucher',
      backLabel: 'Pengaturan',
      onBack: () => context.go(AppRoutes.pengaturan),
      actions: [
        AppButton(
          label: 'Tambah Voucher',
          icon: CupertinoIcons.add,
          onPressed: () => showVoucherFormSheet(context),
        ),
      ],
      slivers: [
        vouchers.when(
          loading: () => const SliverToBoxAdapter(
            child: SizedBox(height: 240, child: LoadingState()),
          ),
          error: (e, _) => SliverToBoxAdapter(
            child: ErrorBanner(message: 'Gagal memuat voucher: $e'),
          ),
          data: (list) => SliverToBoxAdapter(
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: list.isEmpty
                    ? EmptyState(
                        icon: CupertinoIcons.tag,
                        title: 'Belum ada voucher',
                        message:
                            'Buat voucher persen atau nominal, lalu kasir '
                            'bisa memakainya dengan mengetik kodenya.',
                        actionLabel: 'Tambah Voucher',
                        onAction: () => showVoucherFormSheet(context),
                      )
                    : _Groups(vouchers: list),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Groups extends StatelessWidget {
  const _Groups({required this.vouchers});

  final List<Voucher> vouchers;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final usable = <Voucher>[];
    final scheduled = <Voucher>[];
    final ended = <Voucher>[];
    for (final v in vouchers) {
      switch (v.statusAt(now)) {
        case VoucherStatus.active:
          usable.add(v);
        case VoucherStatus.scheduled:
          scheduled.add(v);
        case VoucherStatus.expired || VoucherStatus.inactive:
          ended.add(v);
      }
    }

    Widget section(String header, List<Voucher> list, String footer) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: InsetGroupedSection(
        header: header,
        footer: footer,
        dividerIndent: 58,
        children: [for (final v in list) _VoucherTile(voucher: v, now: now)],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (usable.isNotEmpty)
          section('Bisa dipakai', usable, 'Kasir bisa memakai voucher ini.'),
        if (scheduled.isNotEmpty)
          section(
            'Terjadwal',
            scheduled,
            'Otomatis bisa dipakai mulai tanggal berlakunya.',
          ),
        if (ended.isNotEmpty)
          section(
            'Tidak berlaku',
            ended,
            'Nonaktif atau kedaluwarsa. Ketuk untuk mengubah.',
          ),
      ],
    );
  }
}

class _VoucherTile extends ConsumerWidget {
  const _VoucherTile({required this.voucher, required this.now});

  final Voucher voucher;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final v = voucher;
    final stores = ref.watch(storesProvider).value ?? const [];
    final store = v.storeId == null
        ? null
        : stores.where((s) => s.id == v.storeId).firstOrNull;
    final status = v.statusAt(now);
    final color = switch (status) {
      VoucherStatus.active => c.success,
      VoucherStatus.scheduled => c.accent,
      _ => c.labelTertiary,
    };

    final details = <String>[
      v.summary,
      if (v.endDate != null) 's.d. ${Fmt.dateShort(v.endDate!)}',
      if (v.storeId != null) 'hanya ${store?.name ?? 'toko lain'}',
    ];

    return InsetGroupedTile(
      leading: TileIcon(icon: CupertinoIcons.tag_fill, color: color),
      title: v.name.isEmpty ? v.code : '${v.code} · ${v.name}',
      subtitle: details.join(' · '),
      trailing: status == VoucherStatus.active
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: c.fill,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                status.label,
                style: AppTypography.caption.copyWith(
                  color: c.labelSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
      showChevron: true,
      onPressed: () => showVoucherFormSheet(context, existing: v),
    );
  }
}
