import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../auth/domain/app_user.dart';
import '../domain/printer_config.dart';
import '../domain/receipt_template.dart';
import 'printer_failure.dart';
import '../../sync/data/terminal_repository.dart';

/// Bentuk struk per toko (kolom `stores.receipt_template`, khusus admin) dan
/// pengaturan printer komputer ini (tabel `settings`, semua peran boleh
/// mengubah karena printer menempel ke komputer kasirnya).
class ReceiptSettingsRepository {
  ReceiptSettingsRepository(this._db);

  final AppDatabase _db;

  static const kPrinter = 'printer.config';

  /// Bentuk struk toko [storeId]; belum diatur = template bawaan.
  Future<ReceiptTemplate> templateFor(int storeId) async =>
      _template(await _db.storesDao.receiptTemplateOf(storeId));

  Stream<ReceiptTemplate> watchTemplate(int storeId) =>
      _db.storesDao.watchReceiptTemplate(storeId).map(_template);

  /// Menyimpan bentuk struk (template + logo) toko [storeId].
  Future<void> saveTemplate(
    AppUser actor,
    ReceiptTemplate t, {
    required int storeId,
  }) async {
    _requireAdmin(actor);
    await _requireMaster();
    return _db.storesDao.setReceiptTemplate(storeId, jsonEncode(t.toJson()));
  }

  /// Memakai template HTML [html] di semua toko. Logo tiap toko tetap
  /// (logo bisa berbeda per toko).
  Future<void> applyHtmlToAllStores(AppUser actor, String html) async {
    _requireAdmin(actor);
    await _requireMaster();
    return _db.transaction(() async {
      for (final id in await _db.storesDao.allIds()) {
        final current = await templateFor(id);
        await _db.storesDao.setReceiptTemplate(
          id,
          jsonEncode(current.copyWith(html: html).toJson()),
        );
      }
    });
  }

  /// Data master hanya diubah di komputer server (lihat sinkron).
  Future<void> _requireMaster() async {
    final message = await TerminalRepository.masterLockMessage(_db);
    if (message != null) throw PrinterFailure(message);
  }

  void _requireAdmin(AppUser actor) {
    if (!actor.isAdmin) {
      throw const PrinterFailure(
        'Hanya admin yang bisa mengubah bentuk struk.',
      );
    }
  }

  Future<PrinterConfig> printer() async =>
      _printer(await _db.settingsDao.get(kPrinter));

  Stream<PrinterConfig> watchPrinter() =>
      _db.settingsDao.watch(kPrinter).map(_printer);

  /// Semua peran boleh mengatur printer komputer ini (keputusan user).
  Future<void> savePrinter(AppUser actor, PrinterConfig c) {
    if (!actor.isActive) {
      throw const PrinterFailure('Akun tidak aktif.');
    }
    return _db.settingsDao.set(kPrinter, jsonEncode(c.toJson()));
  }

  static ReceiptTemplate _template(String? raw) {
    final json = _decode(raw);
    return json == null
        ? const ReceiptTemplate()
        : ReceiptTemplate.fromJson(json);
  }

  static PrinterConfig _printer(String? raw) {
    final json = _decode(raw);
    return json == null ? const PrinterConfig() : PrinterConfig.fromJson(json);
  }

  static Map<String, Object?>? _decode(String? raw) {
    if (raw == null) return null;
    try {
      final v = jsonDecode(raw);
      return v is Map<String, Object?> ? v : null;
    } on FormatException {
      return null;
    }
  }
}

final receiptSettingsRepositoryProvider = Provider<ReceiptSettingsRepository>(
  (ref) => ReceiptSettingsRepository(ref.watch(appDatabaseProvider)),
);

final printerConfigProvider = StreamProvider<PrinterConfig>(
  (ref) => ref.watch(receiptSettingsRepositoryProvider).watchPrinter(),
);
