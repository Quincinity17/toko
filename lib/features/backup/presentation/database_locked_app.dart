import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/database/database_bootstrap.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../data/restore_service.dart';
import 'backup_section.dart' show pickRestoreFile;

/// Pengganti aplikasi saat database terenkripsi tidak bisa dibuka (file
/// kunci hilang/rusak, atau database disalin dari perangkat lain). Satu-
/// satunya jalan: pulihkan dari file backup (backup tidak terenkripsi).
/// Sengaja tidak membuat database baru diam-diam (akun bawaan akan aktif).
class DatabaseLockedApp extends StatelessWidget {
  const DatabaseLockedApp({super.key, required this.locked});

  final DatabaseLocked locked;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Toko',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: _LockedPage(locked: locked),
    );
  }
}

class _LockedPage extends StatefulWidget {
  const _LockedPage({required this.locked});

  final DatabaseLocked locked;

  @override
  State<_LockedPage> createState() => _LockedPageState();
}

class _LockedPageState extends State<_LockedPage> {
  String? _message;
  bool _ready = false;

  Future<void> _pickBackup() async {
    // Pemilih file yang sama dengan Pengaturan › Backup.
    final path = await pickRestoreFile();
    if (path == null) return;
    try {
      await RestoreService.stageForLockedDatabase(path);
      setState(() {
        _ready = true;
        _message =
            'Backup siap dipulihkan. Tutup aplikasi lalu buka lagi; '
            'database lama disimpan sebagai toko-terkunci-….sqlite.';
      });
    } on RestoreFailure catch (e) {
      setState(() => _message = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: AppCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    CupertinoIcons.lock_shield_fill,
                    size: 44,
                    color: c.warning,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Database tidak bisa dibuka',
                    textAlign: TextAlign.center,
                    style: AppTypography.title2.copyWith(color: c.label),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '${widget.locked.reason} Data di perangkat ini '
                    'terenkripsi dan hanya bisa dibuka dengan kunci '
                    'perangkat ini. Pulihkan data dari file backup '
                    '(toko-database-….sqlite), lalu buka ulang aplikasi.',
                    textAlign: TextAlign.center,
                    style: AppTypography.subheadline.copyWith(
                      color: c.labelSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    widget.locked.databasePath,
                    textAlign: TextAlign.center,
                    style: AppTypography.caption.copyWith(
                      color: c.labelTertiary,
                    ),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: AppTypography.subheadline.copyWith(
                        color: _ready ? c.success : c.danger,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    label: _ready ? 'Tutup Aplikasi' : 'Pulihkan dari Backup…',
                    icon: _ready
                        ? CupertinoIcons.power
                        : CupertinoIcons.arrow_counterclockwise,
                    size: AppButtonSize.large,
                    expand: true,
                    onPressed: _ready ? () => exit(0) : _pickBackup,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
