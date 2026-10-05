import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_mode_provider.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/inset_grouped_list.dart';
import '../../../core/widgets/large_title_page.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/password_sheet.dart';
import '../../backup/presentation/backup_section.dart';
import '../../products/data/tag_repository.dart';
import '../../receipt/data/receipt_settings_repository.dart';
import '../../sync/presentation/terminal_section.dart';

/// Admin: semua pengaturan. Supervisor & kasir: versi ringkas (terminal,
/// backup, tampilan, tentang); hak ubahnya tetap dijaga di repository.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final mode = ref.watch(themeModeProvider);
    final isAdmin = ref.watch(authControllerProvider)?.isAdmin ?? false;

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
                  if (isAdmin) ...[
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
                              'Admin, supervisor, dan kasir beserta tokonya',
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
                      header: 'Barang',
                      dividerIndent: 58,
                      children: [
                        InsetGroupedTile(
                          leading: TileIcon(
                            icon: CupertinoIcons.tag_fill,
                            color: c.purple,
                          ),
                          title: 'Kelola Kategori',
                          subtitle:
                              'Jenis barang: Mainan, Boneka, Alat Tulis, …',
                          value: switch (ref
                              .watch(tagsProvider)
                              .value
                              ?.length) {
                            null || 0 => null,
                            final n => '$n kategori',
                          },
                          onPressed: () => context.go(AppRoutes.kelolaKategori),
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
                  ],
                  const TerminalSection(),
                  const SizedBox(height: AppSpacing.xl),
                  const BackupSection(),
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
                  if (isAdmin) ...[
                    InsetGroupedSection(
                      header: 'Toko',
                      dividerIndent: 58,
                      children: [
                        InsetGroupedTile(
                          leading: TileIcon(
                            icon: CupertinoIcons.building_2_fill,
                            color: c.accent,
                          ),
                          title: 'Kelola Toko',
                          subtitle: 'Cabang, alamat, dan status aktif',
                          onPressed: () => context.go(AppRoutes.kelolaToko),
                        ),
                        InsetGroupedTile(
                          leading: TileIcon(
                            icon: CupertinoIcons.printer_fill,
                            color: c.labelSecondary,
                          ),
                          title: 'Struk & Printer',
                          subtitle: 'Bentuk struk, printer, dan laci uang',
                          value: ref
                              .watch(printerConfigProvider)
                              .value
                              ?.summary,
                          onPressed: () => context.go(AppRoutes.strukPrinter),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                  ],
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
