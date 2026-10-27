import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/domain/permission.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../receipt/data/receipt_settings_repository.dart';
import '../../receipt/presentation/printer_settings_section.dart';
import '../../stores/presentation/store_scope.dart';
import 'widgets/checkout_view.dart';
import 'widgets/today_sales_view.dart';

enum _PosTab { checkout, today }

/// Halaman Kasir: tab Transaksi Baru (checkout) dan Hari Ini (daftar faktur).
///
/// Berjualan selalu di satu toko: toko akun (supervisor/kasir) atau toko yang
/// dipilih admin. Admin yang sedang di "Semua toko" diminta memilih dulu.
class PosPage extends ConsumerStatefulWidget {
  const PosPage({super.key});

  @override
  ConsumerState<PosPage> createState() => _PosPageState();
}

class _PosPageState extends ConsumerState<PosPage> {
  final _checkoutKey = GlobalKey<CheckoutViewState>();
  _PosTab _tab = _PosTab.checkout;

  void _setTab(_PosTab tab) {
    setState(() => _tab = tab);
    if (tab == _PosTab.checkout) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _checkoutKey.currentState?.focusEntry(),
      );
    }
  }

  Future<void> _openPrinterSettings() async {
    await showPrinterSettingsDialog(
      context,
      storeId: ref.read(storeScopeProvider),
    );
    _checkoutKey.currentState?.focusEntry();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasStore = ref.watch(storeScopeProvider) != null;
    final printerReady =
        ref.watch(printerConfigProvider).value?.isReady ?? false;
    final canSetPrinter =
        ref.watch(authControllerProvider)?.can(Permission.printerSettings) ??
        false;

    return ColoredBox(
      color: c.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (AppBreakpoints.isCompact(context))
            // HP: judul + printer (ikon), tab di baris sendiri.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageGutterCompact,
                AppSpacing.xs,
                AppSpacing.pageGutterCompact,
                AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Kasir',
                          style: AppTypography.title1.copyWith(color: c.label),
                        ),
                      ),
                      if (canSetPrinter)
                        AppIconButton(
                          icon: CupertinoIcons.printer,
                          tooltip: printerReady
                              ? 'Printer Nota'
                              : 'Atur Printer',
                          filled: true,
                          onPressed: _openPrinterSettings,
                        ),
                    ],
                  ),
                  if (hasStore) ...[
                    const SizedBox(height: AppSpacing.xs),
                    CupertinoSlidingSegmentedControl<_PosTab>(
                      groupValue: _tab,
                      padding: const EdgeInsets.all(3),
                      onValueChanged: (t) {
                        if (t != null) _setTab(t);
                      },
                      children: const {
                        _PosTab.checkout: _Seg('Transaksi Baru'),
                        _PosTab.today: _Seg('Hari Ini'),
                      },
                    ),
                  ],
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xl,
                AppSpacing.xl,
                AppSpacing.md,
              ),
              child: Row(
                children: [
                  Text(
                    'Kasir',
                    style: AppTypography.largeTitle.copyWith(color: c.label),
                  ),
                  const SizedBox(width: AppSpacing.xl),
                  if (hasStore)
                    CupertinoSlidingSegmentedControl<_PosTab>(
                      groupValue: _tab,
                      padding: const EdgeInsets.all(3),
                      onValueChanged: (t) {
                        if (t != null) _setTab(t);
                      },
                      children: const {
                        _PosTab.checkout: _Seg('Transaksi Baru'),
                        _PosTab.today: _Seg('Hari Ini'),
                      },
                    ),
                  const SizedBox(width: AppSpacing.md),
                  const Expanded(child: _InfoBar()),
                  const SizedBox(width: AppSpacing.md),
                  // Printer menempel ke komputer kasir, jadi diatur dari sini
                  // (hak "Atur printer"; bentuk struk tetap diatur admin).
                  if (canSetPrinter)
                    AppButton(
                      label: printerReady ? 'Printer Nota' : 'Atur Printer',
                      icon: CupertinoIcons.printer,
                      variant: AppButtonVariant.tinted,
                      size: AppButtonSize.small,
                      onPressed: _openPrinterSettings,
                    ),
                ],
              ),
            ),
          Expanded(
            child: hasStore
                ? IndexedStack(
                    index: _tab.index,
                    children: [
                      CheckoutView(key: _checkoutKey),
                      const TodaySalesView(),
                    ],
                  )
                : EmptyState(
                    icon: CupertinoIcons.building_2_fill,
                    title: 'Pilih toko dulu',
                    message:
                        'Kasir selalu berjualan di satu toko: stok dan harga '
                        'mengikuti toko yang dipilih.',
                    actionLabel: 'Pilih Toko',
                    onAction: () =>
                        pickStoreScope(context, ref, allowAll: false),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Nama kasir dan jam, diperbarui setiap 30 detik.
class _InfoBar extends ConsumerStatefulWidget {
  const _InfoBar();

  @override
  ConsumerState<_InfoBar> createState() => _InfoBarState();
}

class _InfoBarState extends ConsumerState<_InfoBar> {
  late final Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => setState(() => _now = DateTime.now()),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final user = ref.watch(authControllerProvider);
    final style = AppTypography.subheadline.copyWith(color: c.labelSecondary);
    Widget item(IconData icon, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: c.labelSecondary),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
    // Rata kanan; bila sempit, jam disembunyikan lebih dulu.
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: item(
              CupertinoIcons.person_crop_circle,
              user?.fullName ?? '',
            ),
          ),
          if (constraints.maxWidth > 320) ...[
            const SizedBox(width: AppSpacing.lg),
            item(CupertinoIcons.calendar, Fmt.dateTime(_now)),
          ],
        ],
      ),
    );
  }
}

class _Seg extends StatelessWidget {
  const _Seg(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    child: Text(label, style: AppTypography.subheadline),
  );
}
