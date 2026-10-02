import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/inset_grouped_list.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/backup_service.dart';
import '../domain/backup_policy.dart';

/// Memilih folder backup; di-override di tes.
final pickBackupFolderProvider = Provider<Future<String?> Function()>(
  (ref) =>
      () => FilePicker.getDirectoryPath(dialogTitle: 'Folder backup'),
);

/// Bagian "Backup" di halaman Pengaturan (admin): otomatis tiap minggu,
/// folder tujuan, backup sekarang, dan daftar file backup yang tersimpan.
class BackupSection extends ConsumerStatefulWidget {
  const BackupSection({super.key});

  @override
  ConsumerState<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends ConsumerState<BackupSection> {
  bool _running = false;

  BackupService get _service => ref.read(backupServiceProvider);

  Future<void> _runNow() async {
    if (_running) return;
    setState(() => _running = true);
    try {
      final files = await _service.run();
      if (!mounted) return;
      await AppDialogs.alert(
        context,
        title: 'Backup selesai',
        message: files.map((f) => f.name).join('\n'),
      );
    } on BackupFailure catch (e) {
      if (mounted) {
        await AppDialogs.alert(
          context,
          title: 'Backup gagal',
          message: e.message,
        );
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _chooseFolder(BackupStatus status) async {
    final user = ref.read(authControllerProvider)!;
    if (status.isCustomFolder) {
      final choice = await AppDialogs.actionSheet<bool>(
        context,
        title: 'Folder backup',
        message: status.folder,
        options: const [
          ActionSheetOption(label: 'Pilih folder lain…', value: true),
          ActionSheetOption(label: 'Kembali ke folder bawaan', value: false),
        ],
      );
      if (choice == null) return;
      if (!choice) {
        await _service.setFolder(user, null);
        return;
      }
    }
    final path = await ref.read(pickBackupFolderProvider)();
    if (path != null) await _service.setFolder(user, path);
  }

  Future<void> _openFolder(String path) async {
    await Directory(path).create(recursive: true);
    final command = Platform.isWindows
        ? 'explorer'
        : Platform.isMacOS
        ? 'open'
        : 'xdg-open';
    await Process.run(command, [path]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final status = ref.watch(backupStatusProvider).value;
    if (status == null) return const SizedBox.shrink();
    final user = ref.watch(authControllerProvider)!;

    String when(DateTime? d) => d == null ? 'Belum pernah' : Fmt.dateTime(d);
    String size(int bytes) => bytes >= 1024 * 1024
        ? '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB'
        : '${(bytes / 1024).ceil()} KB';

    return InsetGroupedSection(
      header: 'Backup',
      footer:
          'Berisi salinan database lengkap dan daftar barang per toko (Excel, '
          'bisa di-import ulang). Hanya ${status.keep} backup terbaru '
          'yang disimpan; backup baru menggantikan yang paling lama. Backup '
          'dibuat di komputer ini saat aplikasi terbuka. Sesekali salin ke '
          'flashdisk atau penyimpanan lain.',
      dividerIndent: 58,
      children: [
        InsetGroupedTile(
          leading: TileIcon(
            icon: CupertinoIcons.arrow_clockwise_circle_fill,
            color: c.success,
          ),
          title: 'Backup otomatis',
          trailing: CupertinoSwitch(
            value: status.enabled,
            activeTrackColor: c.success,
            onChanged: (v) => _service.setEnabled(user, v),
          ),
        ),
        InsetGroupedTile(
          leading: TileIcon(
            icon: CupertinoIcons.calendar,
            color: c.labelSecondary,
          ),
          title: 'Backup tiap',
          subtitle: status.intervalDays == 7
              ? 'Seminggu sekali'
              : status.intervalDays == 1
              ? 'Setiap hari'
              : null,
          trailing: _Stepper(
            key: const ValueKey('backup-interval'),
            value: status.intervalDays,
            min: BackupPolicy.intervalRange.min,
            max: BackupPolicy.intervalRange.max,
            unit: 'hari',
            onChanged: (v) => _service.setIntervalDays(user, v),
          ),
        ),
        InsetGroupedTile(
          leading: TileIcon(
            icon: CupertinoIcons.square_stack_3d_up_fill,
            color: c.labelSecondary,
          ),
          title: 'Simpan maksimal',
          subtitle:
              'Per jenis (database & Excel); yang lebih lama dihapus '
              'saat backup berikutnya',
          trailing: _Stepper(
            key: const ValueKey('backup-keep'),
            value: status.keep,
            min: BackupPolicy.keepRange.min,
            max: BackupPolicy.keepRange.max,
            unit: 'file',
            onChanged: (v) => _service.setKeep(user, v),
          ),
        ),
        InsetGroupedTile(
          leading: TileIcon(icon: CupertinoIcons.folder_fill, color: c.accent),
          title: 'Folder',
          subtitle: status.folder,
          value: status.isCustomFolder ? null : 'Bawaan',
          onPressed: () => _chooseFolder(status),
        ),
        InsetGroupedTile(
          leading: TileIcon(
            icon: status.lastError == null
                ? CupertinoIcons.checkmark_seal_fill
                : CupertinoIcons.exclamationmark_triangle_fill,
            color: status.lastError == null ? c.success : c.danger,
          ),
          title: 'Backup terakhir',
          subtitle:
              status.lastError ??
              (status.enabled && status.nextAt != null
                  ? 'Berikutnya ${Fmt.dateTime(status.nextAt!)}'
                  : null),
          value: when(status.lastAt),
        ),
        for (final f in status.files)
          InsetGroupedTile(
            leading: TileIcon(
              icon: f.kind == BackupKind.database
                  ? CupertinoIcons.archivebox_fill
                  : CupertinoIcons.table_fill,
              color: c.labelSecondary,
            ),
            title: f.name,
            subtitle: '${f.kind.label} · ${Fmt.dateTime(f.modified)}',
            value: size(f.size),
          ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Backup Sekarang',
                  icon: CupertinoIcons.arrow_down_doc_fill,
                  expand: true,
                  loading: _running,
                  onPressed: _runNow,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: AppButton(
                  label: 'Buka Folder',
                  icon: CupertinoIcons.folder,
                  variant: AppButtonVariant.gray,
                  expand: true,
                  onPressed: () => _openFolder(status.folder),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.onChanged,
  });

  final int value;
  final int min;
  final int max;
  final String unit;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIconButton(
          icon: CupertinoIcons.minus,
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 64,
          child: Text(
            '$value $unit',
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(
              color: c.label,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        AppIconButton(
          icon: CupertinoIcons.plus,
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}
