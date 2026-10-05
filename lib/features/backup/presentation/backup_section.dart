import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/utils/device.dart';
import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/save_file.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/inset_grouped_list.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/backup_service.dart';
import '../data/restore_service.dart';
import '../domain/backup_policy.dart';

/// Memilih folder backup; di-override di tes.
final pickBackupFolderProvider = Provider<Future<String?> Function()>(
  (ref) =>
      () => FilePicker.getDirectoryPath(dialogTitle: 'Folder backup'),
);

/// Memilih file backup database untuk dipulihkan (mis. dari flashdisk).
/// Mengembalikan path lokal.
Future<String?> pickRestoreFile() async {
  final file = await FilePicker.pickFile(
    dialogTitle: 'Pilih backup database (toko-database-….sqlite)',
  );
  if (file == null) return null;
  if (file.path case final path?) return path;
  // Mis. Android: file bukan di disk lokal → salin ke folder sementara.
  final tmp = File(p.join(Directory.systemTemp.path, file.name));
  await tmp.writeAsBytes(await file.readAsBytes(), flush: true);
  return tmp.path;
}

/// [pickRestoreFile]; di-override di tes.
final pickRestoreFileProvider = Provider<Future<String?> Function()>(
  (ref) => pickRestoreFile,
);

/// Menutup aplikasi (setelah pemulihan disiapkan); di-override di tes.
final exitAppProvider = Provider<void Function()>(
  (ref) =>
      () => exit(0),
);

/// Bagian "Backup" di halaman Pengaturan: otomatis tiap minggu, folder
/// tujuan, backup sekarang, dan daftar file backup yang tersimpan.
///
/// Supervisor & kasir hanya melihat pengaturannya, tetapi tetap bisa
/// Backup Sekarang dan Buka Folder.
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

  /// Pilih sumber pemulihan: backup di folder, atau file lain.
  Future<void> _chooseRestore(BackupStatus status) async {
    final backups = [
      for (final f in status.files)
        if (f.kind == BackupKind.database) f,
    ];
    final choice = await AppDialogs.actionSheet<String>(
      context,
      title: 'Pulihkan dari backup',
      message:
          'Semua data di komputer ini akan diganti dengan isi backup yang '
          'dipilih.',
      options: [
        for (final f in backups)
          ActionSheetOption(
            label: '${Fmt.dateTime(f.modified)} · ${f.name}',
            value: f.path,
          ),
        const ActionSheetOption(label: 'Pilih file lain…', value: ''),
      ],
    );
    if (choice == null || !mounted) return;
    final path = choice.isEmpty
        ? await ref.read(pickRestoreFileProvider)()
        : choice;
    if (path != null && mounted) await _restore(path);
  }

  Future<void> _restore(String path) async {
    final BackupInfo info;
    try {
      info = RestoreService.inspect(
        path,
        sealer: ref.read(appDatabaseProvider).sealer,
      );
    } on RestoreFailure catch (e) {
      await AppDialogs.alert(
        context,
        title: 'Tidak bisa dipulihkan',
        message: e.message,
      );
      return;
    }
    if (!mounted) return;
    final ok = await AppDialogs.confirm(
      context,
      title: 'Pulihkan data dari backup?',
      message:
          '${info.fileName}\n'
          '${Fmt.number(info.products)} barang · '
          '${Fmt.number(info.sales)} transaksi'
          '${info.lastSale == null ? '' : ' (terakhir ${Fmt.dateTime(info.lastSale!)})'}'
          '\n\n${switch (info.seals) {
            BackupSeals.intact => '✓ Isi backup utuh (segel cocok).',
            BackupSeals.tampered => '⚠ PERINGATAN: isi backup ini pernah diubah di luar aplikasi (faktur, akun, harga, atau stok). Jangan dipulihkan kecuali Anda yakin.',
            BackupSeals.unverifiable => 'Isi backup tidak bisa diperiksa (dari perangkat lain atau versi lama).',
          }}'
          '\n\nSemua data di komputer ini (barang, stok, transaksi, akun, '
          'pengaturan) diganti dengan isi backup ini. Data sekarang disalin '
          'dulu ke folder backup (${RestoreService.safetyPrefix}….sqlite).',
      confirmLabel: 'Pulihkan',
      destructive: true,
    );
    if (!ok || !mounted) return;

    final String safety;
    try {
      safety = await ref
          .read(restoreServiceProvider)
          .stage(ref.read(authControllerProvider)!, path);
    } on RestoreFailure catch (e) {
      if (mounted) {
        await AppDialogs.alert(context, title: 'Gagal', message: e.message);
      }
      return;
    }
    ref.invalidate(pendingRestoreProvider);
    if (!mounted) return;
    final close = await AppDialogs.confirm(
      context,
      title: 'Siap dipulihkan',
      message:
          'Data sekarang sudah disalin ke:\n$safety\n\nPemulihan dijalankan '
          'saat aplikasi dibuka lagi. Tutup aplikasi sekarang?',
      confirmLabel: 'Tutup Aplikasi',
      cancelLabel: 'Nanti',
    );
    if (close) ref.read(exitAppProvider)();
  }

  Future<void> _cancelRestore() async {
    await ref.read(restoreServiceProvider).cancelPending();
    ref.invalidate(pendingRestoreProvider);
  }

  /// HP/tablet: folder backup ada di penyimpanan aplikasi (tidak bisa
  /// dibuka, ikut hilang bila aplikasi dihapus) → salinan disimpan lewat
  /// dialog simpan Android (Download, Drive, …).
  static bool get _mobile => Device.isTouch;

  Future<void> _saveCopy(BackupStatus status) async {
    if (status.files.isEmpty) {
      await AppDialogs.alert(
        context,
        title: 'Belum ada backup',
        message: 'Tekan Backup Sekarang dulu.',
      );
      return;
    }
    final path = await AppDialogs.actionSheet<String>(
      context,
      title: 'Simpan salinan backup',
      message: 'Simpan ke Download, Google Drive, atau flashdisk.',
      options: [
        for (final f in status.files)
          ActionSheetOption(label: f.name, value: f.path),
      ],
    );
    if (path == null) return;
    final file = p.basename(path);
    final saved = await saveFileAs(
      fileName: file,
      bytes: await File(path).readAsBytes(),
      extension: file.endsWith('.xlsx') ? 'xlsx' : 'sqlite',
      mimeType: file.endsWith('.xlsx') ? xlsxMime : 'application/octet-stream',
    );
    if (saved != null && mounted) {
      await AppDialogs.alert(context, title: 'Tersimpan', message: saved);
    }
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
    final isAdmin = user.isAdmin;
    final pending = ref.watch(pendingRestoreProvider).value ?? false;
    final lastRestore = ref.watch(lastRestoreProvider).value;

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
          'flashdisk atau penyimpanan lain.'
          '${isAdmin ? '' : ' Pengaturan backup hanya bisa diubah admin.'}',
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
            onChanged: isAdmin ? (v) => _service.setEnabled(user, v) : null,
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
          value: isAdmin ? null : '${status.intervalDays} hari',
          trailing: !isAdmin
              ? null
              : _Stepper(
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
          value: isAdmin ? null : '${status.keep} file',
          trailing: !isAdmin
              ? null
              : _Stepper(
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
          onPressed: isAdmin && !_mobile ? () => _chooseFolder(status) : null,
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
        if (pending)
          InsetGroupedTile(
            leading: TileIcon(
              icon: CupertinoIcons.arrow_counterclockwise_circle_fill,
              color: c.warning,
            ),
            title: 'Pemulihan menunggu',
            subtitle: 'Dijalankan saat aplikasi ditutup lalu dibuka lagi.',
            trailing: isAdmin
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppButton(
                        label: 'Batalkan',
                        variant: AppButtonVariant.plain,
                        size: AppButtonSize.small,
                        onPressed: _cancelRestore,
                      ),
                      AppButton(
                        label: 'Tutup Aplikasi',
                        variant: AppButtonVariant.tinted,
                        size: AppButtonSize.small,
                        onPressed: () => ref.read(exitAppProvider)(),
                      ),
                    ],
                  )
                : null,
          ),
        if (lastRestore != null)
          InsetGroupedTile(
            leading: TileIcon(
              icon: CupertinoIcons.arrow_counterclockwise,
              color: c.labelSecondary,
            ),
            title: 'Terakhir dipulihkan',
            subtitle: 'Dari ${lastRestore.source}',
            value: Fmt.dateTime(lastRestore.at),
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
            // Admin: ketuk backup database untuk memulihkannya.
            onPressed: isAdmin && f.kind == BackupKind.database && !pending
                ? () => _restore(f.path)
                : null,
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
              if (isAdmin) ...[
                Expanded(
                  child: AppButton(
                    label: 'Pulihkan…',
                    icon: CupertinoIcons.arrow_counterclockwise,
                    variant: AppButtonVariant.gray,
                    expand: true,
                    onPressed: pending ? null : () => _chooseRestore(status),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              Expanded(
                child: _mobile
                    ? AppButton(
                        label: 'Simpan Salinan…',
                        icon: CupertinoIcons.square_arrow_down,
                        variant: AppButtonVariant.gray,
                        expand: true,
                        onPressed: () => _saveCopy(status),
                      )
                    : AppButton(
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
