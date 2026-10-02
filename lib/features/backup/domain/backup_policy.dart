import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// Aturan backup otomatis (permintaan user): seminggu sekali, hanya 2 backup
/// terbaru per jenis yang disimpan; backup baru menggantikan yang paling lama.
class BackupPolicy {
  const BackupPolicy._();

  static const interval = Duration(days: 7);
  static const keep = 2;

  static final _stamp = DateFormat('yyyyMMdd-HHmmss');

  /// Sudah waktunya backup: belum pernah, atau terakhir ≥ [interval] lalu.
  static bool isDue(DateTime? lastAt, DateTime now) =>
      lastAt == null || !now.isBefore(lastAt.add(interval));

  static String fileName(BackupKind kind, DateTime at) =>
      '${kind.prefix}${_stamp.format(at)}.${kind.extension}';

  /// File [kind] yang harus dihapus agar tersisa [keep] terbaru. Nama file
  /// memuat waktu (yyyyMMdd-HHmmss), jadi urutan nama = urutan waktu.
  static List<String> toDelete(
    Iterable<String> names,
    BackupKind kind, {
    int keep = keep,
  }) {
    final mine = names.where(kind.matches).toList()
      ..sort((a, b) => b.compareTo(a));
    return mine.skip(keep).toList();
  }
}

enum BackupKind {
  /// Salinan lengkap database (bisa dipulihkan).
  database('toko-database-', 'sqlite', 'Database'),

  /// Daftar barang per toko dalam Excel (bisa di-import ulang).
  products('toko-barang-', 'xlsx', 'Barang (Excel)');

  const BackupKind(this.prefix, this.extension, this.label);

  final String prefix;
  final String extension;
  final String label;

  bool matches(String name) =>
      name.startsWith(prefix) && name.endsWith('.$extension');
}

/// Satu file backup di folder.
@immutable
class BackupFile {
  const BackupFile({
    required this.kind,
    required this.name,
    required this.path,
    required this.size,
    required this.modified,
  });

  final BackupKind kind;
  final String name;
  final String path;
  final int size;
  final DateTime modified;
}

/// Keadaan backup untuk ditampilkan di Pengaturan.
@immutable
class BackupStatus {
  const BackupStatus({
    required this.enabled,
    required this.folder,
    required this.isCustomFolder,
    this.lastAt,
    this.lastError,
    this.files = const [],
  });

  final bool enabled;
  final String folder;

  /// Folder dipilih admin (bukan folder bawaan Documents).
  final bool isCustomFolder;
  final DateTime? lastAt;

  /// Pesan gagal backup otomatis terakhir (mis. flashdisk dicabut).
  final String? lastError;
  final List<BackupFile> files;

  DateTime? get nextAt => lastAt?.add(BackupPolicy.interval);
}
