import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_mode_provider.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/inset_grouped_list.dart';
import '../../../core/widgets/large_title_page.dart';
import '../../auth/presentation/password_sheet.dart';
import '../../sync/presentation/terminal_section.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final mode = ref.watch(themeModeProvider);

    return LargeTitlePage(
      title: 'Pengaturan',
      slivers: [
        SliverToBoxAdapter(
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InsetGroupedSection(
                    header: 'Akun',
                    dividerIndent: 58,
                    children: [
                      InsetGroupedTile(
                        leading: TileIcon(
                          icon: CupertinoIcons.person_2_fill,
                          color: c.accent,
                        ),
                        title: 'Kelola Akun',
                        subtitle:
                            'Tambah, ubah, atau nonaktifkan akun admin '
                            'dan kasir',
                        onPressed: () => context.go(AppRoutes.kelolaAkun),
                      ),
                      InsetGroupedTile(
                        leading: TileIcon(
                          icon: CupertinoIcons.lock_fill,
                          color: c.labelSecondary,
                        ),
                        title: 'Ganti Password Saya',
                        onPressed: () => showChangeOwnPasswordSheet(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  InsetGroupedSection(
                    header: 'Penjualan',
                    dividerIndent: 58,
                    children: [
                      InsetGroupedTile(
                        leading: TileIcon(
                          icon: CupertinoIcons.creditcard_fill,
                          color: c.success,
                        ),
                        title: 'Metode Pembayaran',
                        subtitle: 'Tunai, QRIS, transfer, kartu, dll.',
                        onPressed: () => context.go(AppRoutes.metodeBayar),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const TerminalSection(),
                  const SizedBox(height: AppSpacing.xl),
                  InsetGroupedSection(
                    header: 'Tampilan',
                    dividerIndent: 58,
                    children: [
                      InsetGroupedTile(
                        leading: TileIcon(
                          icon: CupertinoIcons.circle_lefthalf_fill,
                          color: c.labelSecondary,
                        ),
                        title: 'Mode',
                        trailing: CupertinoSlidingSegmentedControl<ThemeMode>(
                          groupValue: mode,
                          onValueChanged: (v) {
                            if (v != null) {
                              ref.read(themeModeProvider.notifier).set(v);
                            }
                          },
                          children: const {
                            ThemeMode.system: _Seg('Sistem'),
                            ThemeMode.light: _Seg('Terang'),
                            ThemeMode.dark: _Seg('Gelap'),
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  InsetGroupedSection(
                    header: 'Toko',
                    footer:
                        'Data toko ditampilkan di struk. Bisa diubah '
                        'setelah database tersedia.',
                    dividerIndent: 58,
                    children: [
                      InsetGroupedTile(
                        leading: TileIcon(
                          icon: CupertinoIcons.bag_fill,
                          color: c.accent,
                        ),
                        title: 'Nama Toko',
                        value: 'Toko',
                        onPressed: () {},
                      ),
                      InsetGroupedTile(
                        leading: TileIcon(
                          icon: CupertinoIcons.printer_fill,
                          color: c.labelSecondary,
                        ),
                        title: 'Printer Struk',
                        value: 'Thermal 58 mm',
                        onPressed: () {},
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const _ComponentPreview(),
                  const SizedBox(height: AppSpacing.xl),
                  InsetGroupedSection(
                    header: 'Tentang',
                    children: [
                      const InsetGroupedTile(title: 'Versi', value: '0.1.0'),
                      InsetGroupedTile(
                        title: 'Contoh format Rupiah',
                        value: Fmt.rupiah(1250000),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Contoh komponen design system, untuk review tampilan di Langkah 1.
/// Akan dihapus setelah desain disetujui.
class _ComponentPreview extends StatelessWidget {
  const _ComponentPreview();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InsetGroupedSection(
      header: 'Pratinjau Komponen',
      footer: 'Bagian ini hanya untuk review desain dan akan dihapus.',
      dividerIndent: 58,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AppButton(label: 'Filled', onPressed: () {}),
              AppButton(
                label: 'Tinted',
                variant: AppButtonVariant.tinted,
                onPressed: () {},
              ),
              AppButton(
                label: 'Gray',
                variant: AppButtonVariant.gray,
                onPressed: () {},
              ),
              AppButton(
                label: 'Plain',
                variant: AppButtonVariant.plain,
                onPressed: () {},
              ),
              AppButton(
                label: 'Bayar',
                icon: CupertinoIcons.creditcard_fill,
                size: AppButtonSize.large,
                onPressed: () {},
              ),
              const AppButton(label: 'Menyimpan', loading: true),
            ],
          ),
        ),
        InsetGroupedTile(
          leading: TileIcon(
            icon: CupertinoIcons.exclamationmark_bubble_fill,
            color: c.warning,
          ),
          title: 'Contoh alert konfirmasi',
          onPressed: () => AppDialogs.confirm(
            context,
            title: 'Hapus produk?',
            message: 'Produk "Indomie Goreng" akan dihapus permanen.',
            confirmLabel: 'Hapus',
            destructive: true,
          ),
        ),
        InsetGroupedTile(
          leading: TileIcon(icon: CupertinoIcons.list_bullet, color: c.accent),
          title: 'Contoh action sheet',
          onPressed: () => AppDialogs.actionSheet<String>(
            context,
            title: 'Kode barang sudah ada',
            message: 'Pilih tindakan untuk 12 produk duplikat.',
            options: const [
              ActionSheetOption(label: 'Lewati', value: 'skip'),
              ActionSheetOption(
                label: 'Update stok & harga saja',
                value: 'update',
              ),
              ActionSheetOption(
                label: 'Timpa semua',
                value: 'overwrite',
                destructive: true,
              ),
            ],
          ),
        ),
        InsetGroupedTile(
          leading: TileIcon(
            icon: CupertinoIcons.rectangle_dock,
            color: c.success,
          ),
          title: 'Contoh bottom sheet',
          onPressed: () => AppDialogs.sheet<void>(
            context,
            title: 'Pembayaran',
            builder: (ctx) => Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.xl,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Total',
                    style: AppTypography.subheadline.copyWith(
                      color: ctx.colors.labelSecondary,
                    ),
                  ),
                  Text(
                    Fmt.rupiah(87500),
                    style: AppTypography.displayAmount.copyWith(
                      color: ctx.colors.label,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  AppButton(
                    label: 'Selesai',
                    size: AppButtonSize.large,
                    expand: true,
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Seg extends StatelessWidget {
  const _Seg(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Text(label, style: AppTypography.footnote),
    );
  }
}
