import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/database/tables/audit.dart';

export '../../../core/database/tables/audit.dart' show AuditType;

/// Kelompok catatan untuk filter di layar.
enum AuditCategory {
  cashier('Kasir'),
  login('Login'),
  products('Barang & stok'),
  accounts('Akun'),
  system('Pengaturan & sistem');

  const AuditCategory(this.label);
  final String label;
}

extension AuditTypeInfo on AuditType {
  String get label => switch (this) {
    AuditType.login => 'Login',
    AuditType.loginFailed => 'Login gagal',
    AuditType.logout => 'Keluar',
    AuditType.sale => 'Penjualan',
    AuditType.saleReturn => 'Retur / batal faktur',
    AuditType.cartCleared => 'Batal transaksi',
    AuditType.cartItemReduced => 'Barang dikurangi/dihapus',
    AuditType.heldCartDeleted => 'Transaksi tertahan dihapus',
    AuditType.drawerOpened => 'Laci dibuka tanpa transaksi',
    AuditType.productCreated => 'Barang baru',
    AuditType.productUpdated => 'Barang diubah',
    AuditType.productDeleted => 'Barang dihapus/nonaktif',
    AuditType.productsImported => 'Import barang',
    AuditType.stockAdjusted => 'Stok diubah',
    AuditType.userCreated => 'Akun baru',
    AuditType.userUpdated => 'Akun diubah',
    AuditType.userPasswordReset => 'Reset password',
    AuditType.userDeleted => 'Akun dihapus',
    AuditType.passwordChanged => 'Ganti password',
    AuditType.storeChanged => 'Toko diubah',
    AuditType.paymentMethodChanged => 'Metode bayar diubah',
    AuditType.terminalChanged => 'Kode terminal diubah',
    AuditType.backupChanged => 'Pengaturan backup',
    AuditType.restoreStaged => 'Pemulihan disiapkan',
    AuditType.restoreApplied => 'Data dipulihkan',
    AuditType.sealsRebuilt => 'Segel data dibuat',
    AuditType.clockBack => 'Jam perangkat mundur',
  };

  AuditCategory get category => switch (this) {
    AuditType.sale ||
    AuditType.saleReturn ||
    AuditType.cartCleared ||
    AuditType.cartItemReduced ||
    AuditType.heldCartDeleted ||
    AuditType.drawerOpened => AuditCategory.cashier,
    AuditType.login ||
    AuditType.loginFailed ||
    AuditType.logout => AuditCategory.login,
    AuditType.productCreated ||
    AuditType.productUpdated ||
    AuditType.productDeleted ||
    AuditType.productsImported ||
    AuditType.stockAdjusted => AuditCategory.products,
    AuditType.userCreated ||
    AuditType.userUpdated ||
    AuditType.userPasswordReset ||
    AuditType.userDeleted ||
    AuditType.passwordChanged => AuditCategory.accounts,
    _ => AuditCategory.system,
  };

  /// Tindakan yang perlu diperhatikan admin (bisa dipakai untuk curang).
  bool get needsAttention => switch (this) {
    AuditType.cartCleared ||
    AuditType.cartItemReduced ||
    AuditType.heldCartDeleted ||
    AuditType.drawerOpened ||
    AuditType.saleReturn ||
    AuditType.loginFailed ||
    AuditType.clockBack ||
    AuditType.restoreApplied => true,
    _ => false,
  };
}

/// Satu catatan aktivitas untuk ditampilkan.
@immutable
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.at,
    required this.type,
    required this.summary,
    this.userId,
    this.userName,
    this.storeId,
    this.terminalCode,
    this.data,
  });

  final int id;
  final DateTime at;
  final AuditType type;
  final String summary;
  final int? userId;
  final String? userName;
  final int? storeId;
  final String? terminalCode;

  /// JSON rincian (bisa `null`).
  final String? data;

  Map<String, Object?> get details {
    if (data == null) return const {};
    try {
      return (jsonDecode(data!) as Map).cast<String, Object?>();
    } on FormatException {
      return const {};
    }
  }
}

/// Jumlah tindakan yang perlu diperhatikan per user dalam satu periode.
@immutable
class AttentionSummary {
  const AttentionSummary({
    required this.userName,
    required this.counts,
    this.cartClearedValue = 0,
    this.returnValue = 0,
  });

  final String userName;
  final Map<AuditType, int> counts;

  /// Nilai keranjang yang dibatalkan (Rp).
  final int cartClearedValue;

  /// Nilai uang yang dikembalikan lewat retur (Rp).
  final int returnValue;

  int get total => counts.values.fold(0, (a, b) => a + b);
}
