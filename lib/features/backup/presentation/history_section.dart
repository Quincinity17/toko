import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/inset_grouped_list.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/history_cleanup_service.dart';
import '../domain/history_retention.dart';

final historyStatusProvider = FutureProvider.autoDispose<HistoryStatus>(
  (ref) => ref.watch(historyCleanupServiceProvider).status(),
);

/// Bagian "Riwayat Penjualan" di Pengaturan (admin): ukuran data, hapus
/// otomatis riwayat lama (bawaan: tidak pernah), dan Hapus Sekarang.
class HistorySection extends ConsumerStatefulWidget {
  const HistorySection({super.key});

  @override
  ConsumerState<HistorySection> createState() => _HistorySectionState();
}

class _HistorySectionState extends ConsumerState<HistorySection> {
  bool _busy = false;

  HistoryCleanupService get _service => ref.read(historyCleanupServiceProvider);

  Future<void> _pickRetention(int current) async {
    final picked = await AppDialogs.actionSheet<int>(
      context,
      title: 'Hapus riwayat penjualan otomatis',
      message:
          'Faktur yang lebih lama dari batas ini dihapus sekali sehari. '
          'Salinan data disimpan dulu di folder backup.',
      options: [
        for (final m in HistoryRetention.options)
          ActionSheetOption(
            label: '${HistoryRetention.label(m)}${m == current ? '  ✓' : ''}',
            value: m,
          ),
      ],
    );
    if (picked == null || picked == current) return;
    await _service.setKeepMonths(ref.read(authControllerProvider)!, picked);
    ref.invalidate(historyStatusProvider);
  }

  Future<void> _runNow(HistoryStatus status) async {
    if (_busy) return;
    final count = await _service.preview(status.keepMonths);
    if (!mounted) return;
    final cutoff = HistoryRetention.cutoff(DateTime.now(), status.keepMonths);
    if (count == 0) {
      await AppDialogs.alert(
        context,
        title: 'Tidak ada yang dihapus',
        message:
            'Tidak ada faktur sebelum ${Fmt.dateShort(cutoff)} yang bisa '
            'dihapus.',
      );
      return;
    }
    final ok = await AppDialogs.confirm(
      context,
      title: 'Hapus ${Fmt.number(count)} faktur?',
      message:
          'Faktur sebelum ${Fmt.dateShort(cutoff)} beserta nota returnya '
          'dihapus permanen. Laporan sebelum tanggal itu menjadi kosong. '
          'Stok barang tidak berubah.\n\nSalinan lengkap data sekarang '
          'disimpan dulu di folder backup (toko-sebelum-hapus-…).',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await _service.runNow(ref.read(authControllerProvider)!);
      if (!mounted) return;
      await AppDialogs.alert(
        context,
        title: 'Riwayat dihapus',
        message:
            '${Fmt.number(r.sales)} faktur dan ${Fmt.number(r.returns)} '
            'nota retur dihapus.'
            '${r.safetyCopy == null ? '' : '\n\nSalinan: ${p.basename(r.safetyCopy!)}'}',
      );
    } on HistoryCleanupFailure catch (e) {
      if (mounted) {
        await AppDialogs.alert(context, title: 'Gagal', message: e.message);
      }
    } finally {
      ref.invalidate(historyStatusProvider);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final status = ref.watch(historyStatusProvider).value;
    if (status == null) return const SizedBox.shrink();

    final size = status.databaseBytes >= 1024 * 1024
        ? '${(status.databaseBytes / 1024 / 1024).toStringAsFixed(1)} MB'
        : '${(status.databaseBytes / 1024).ceil()} KB';
    final enabled = status.keepMonths != HistoryRetention.never;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InsetGroupedSection(
          header: 'Riwayat Penjualan',
          footer:
              'Catatan aktivitas tidak ikut dihapus. Simpan riwayat sesuai '
              'kebutuhan pembukuan/pajak (umumnya 10 tahun); salinan '
              'sebelum hapus bisa dipindah ke flashdisk.',
          dividerIndent: 58,
          children: [
            InsetGroupedTile(
              leading: TileIcon(
                icon: CupertinoIcons.doc_text_fill,
                color: c.accent,
              ),
              title: 'Tersimpan',
              subtitle: status.oldest == null
                  ? 'Belum ada transaksi'
                  : '${Fmt.number(status.sales)} faktur sejak '
                        '${Fmt.dateShort(status.oldest!)}',
              value: size,
            ),
            InsetGroupedTile(
              leading: TileIcon(icon: CupertinoIcons.timer, color: c.warning),
              title: 'Hapus otomatis',
              value: HistoryRetention.label(status.keepMonths),
              showChevron: true,
              onPressed: () => _pickRetention(status.keepMonths),
            ),
            if (status.lastRun != null)
              InsetGroupedTile(
                title: 'Terakhir dibersihkan',
                value:
                    '${Fmt.dateTime(status.lastRun!)} · '
                    '${Fmt.number(status.lastDeleted)} faktur',
              ),
            if (enabled)
              InsetGroupedTile(
                leading: TileIcon(icon: CupertinoIcons.trash, color: c.danger),
                title: _busy ? 'Menghapus…' : 'Hapus Sekarang',
                subtitle:
                    'Faktur sebelum '
                    '${Fmt.dateShort(HistoryRetention.cutoff(DateTime.now(), status.keepMonths))}',
                onPressed: _busy ? null : () => _runNow(status),
              ),
          ],
        ),
        if (status.lastError != null) ...[
          const SizedBox(height: AppSpacing.sm),
          ErrorBanner(message: status.lastError!),
        ],
      ],
    );
  }
}
