import 'package:flutter/foundation.dart';

import '../../../core/database/tables/sales.dart';

/// Cara mengubah stok di halaman Stok.
enum StockAdjustMode {
  /// Barang datang (dari supplier/gudang): stok bertambah.
  receive('Barang Masuk', 'Jumlah masuk'),

  /// Barang rusak, hilang, kedaluwarsa, dipakai sendiri: stok berkurang.
  remove('Barang Keluar', 'Jumlah keluar'),

  /// Hitung ulang fisik: stok diganti dengan hasil hitungan.
  count('Stok Opname', 'Stok sebenarnya');

  const StockAdjustMode(this.label, this.qtyLabel);

  final String label;
  final String qtyLabel;

  /// Perubahan stok untuk isian [qty] bila stok sekarang [current].
  double delta(double current, double qty) => switch (this) {
    StockAdjustMode.receive => qty,
    StockAdjustMode.remove => -qty,
    StockAdjustMode.count => qty - current,
  };
}

/// Satu baris riwayat stok.
@immutable
class StockMovement {
  const StockMovement({
    required this.date,
    required this.type,
    required this.change,
    this.note,
    this.userName,
  });

  final DateTime date;
  final StockMovementType type;
  final double change;
  final String? note;
  final String? userName;

  String get typeLabel => switch (type) {
    StockMovementType.sale => 'Penjualan',
    StockMovementType.import => 'Import',
    StockMovementType.adjust => 'Penyesuaian',
  };
}
