import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/utils/formatters.dart';

/// Data stok satu barang di satu toko, bahan [StockAlerts.analyze].
@immutable
class StockHealthRow {
  const StockHealthRow({
    required this.productId,
    required this.code,
    required this.name,
    this.unit,
    required this.stock,
    this.minStock = 0,
    this.sold = 0,
    this.adjustedOut = 0,
    this.storeId,
    this.storeName,
  });

  final int productId;

  /// Toko (diisi saat melihat semua toko).
  final int? storeId;
  final String? storeName;
  final String code;
  final String name;
  final String? unit;
  final double stock;
  final double minStock;

  /// Terjual bersih (penjualan − retur, satuan dasar) dalam
  /// [StockAlerts.days] hari terakhir.
  final double sold;

  /// Stok yang berkurang lewat penyesuaian (barang keluar / opname minus)
  /// dalam [StockAlerts.days] hari terakhir, positif.
  final double adjustedOut;
}

enum StockAlertLevel {
  /// Harus segera ditangani (minus, habis padahal laku).
  danger,

  /// Perlu dibeli (menipis, akan habis).
  warning,

  /// Kemungkinan stok tercatat tidak sesuai stok nyata: cek fisik/opname.
  check,
}

enum StockAlertKind {
  negative(StockAlertLevel.danger, 'Stok minus'),
  outOfStock(StockAlertLevel.danger, 'Habis, masih laku'),
  low(StockAlertLevel.warning, 'Menipis'),
  runningOut(StockAlertLevel.warning, 'Akan habis'),
  fractional(StockAlertLevel.check, 'Stok pecahan'),
  excessive(StockAlertLevel.check, 'Stok tidak wajar'),
  shrinkage(StockAlertLevel.check, 'Banyak berkurang di luar penjualan');

  const StockAlertKind(this.level, this.label);

  final StockAlertLevel level;
  final String label;
}

@immutable
class StockAlert {
  const StockAlert({
    required this.row,
    required this.kind,
    required this.message,
    this.suggestedBuy,
  });

  final StockHealthRow row;
  final StockAlertKind kind;
  final String message;

  /// Saran jumlah beli (satuan dasar); `null` = tidak perlu.
  final double? suggestedBuy;
}

/// Ambang peringatan stok (diatur admin, settings `stock.alerts`).
@immutable
class StockAlertSettings {
  const StockAlertSettings({
    this.days = 30,
    this.runningOutDays = 7,
    this.coverDays = 14,
    this.excessiveDays = 365,
  });

  /// Rentang data penjualan & penyesuaian (hari).
  final int days;

  /// Akan habis bila perkiraan habis ≤ ini (hari).
  final int runningOutDays;

  /// Saran beli = cukup untuk sekian hari (minimal 2 × stok minimum).
  final int coverDays;

  /// Persediaan lebih dari ini (hari) dianggap tidak wajar.
  final int excessiveDays;

  static const kSetting = 'stock.alerts';

  /// Batas wajar tiap isian: (min, maks).
  static const limits = (
    days: (7, 365),
    runningOutDays: (1, 60),
    coverDays: (1, 180),
    excessiveDays: (60, 3650),
  );

  static int _clamp(Object? v, int fallback, (int, int) range) =>
      ((v as num?)?.round() ?? fallback).clamp(range.$1, range.$2);

  factory StockAlertSettings.fromJson(String? raw) {
    if (raw == null || raw.isEmpty) return const StockAlertSettings();
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      const d = StockAlertSettings();
      return StockAlertSettings(
        days: _clamp(m['days'], d.days, limits.days),
        runningOutDays: _clamp(
          m['runningOutDays'],
          d.runningOutDays,
          limits.runningOutDays,
        ),
        coverDays: _clamp(m['coverDays'], d.coverDays, limits.coverDays),
        excessiveDays: _clamp(
          m['excessiveDays'],
          d.excessiveDays,
          limits.excessiveDays,
        ),
      );
    } on FormatException {
      return const StockAlertSettings();
    }
  }

  String toJson() => jsonEncode({
    'days': days,
    'runningOutDays': runningOutDays,
    'coverDays': coverDays,
    'excessiveDays': excessiveDays,
  });

  @override
  bool operator ==(Object other) =>
      other is StockAlertSettings &&
      other.days == days &&
      other.runningOutDays == runningOutDays &&
      other.coverDays == coverDays &&
      other.excessiveDays == excessiveDays;

  @override
  int get hashCode =>
      Object.hash(days, runningOutDays, coverDays, excessiveDays);
}

/// Peringatan stok satu toko: stok menipis/habis + stok yang kemungkinan
/// tidak sesuai stok nyata. Fungsi murni.
abstract final class StockAlerts {
  /// Ambang bawaan (lihat [StockAlertSettings]).
  static const defaults = StockAlertSettings();
  static final days = defaults.days;
  static final coverDays = defaults.coverDays;

  /// Satuan timbangan/ukur: stok pecahan wajar.
  static const _measured = {
    'KG', 'G', 'GR', 'GRAM', 'ONS', 'L', 'LT', 'LTR', 'LITER', 'ML', //
    'M', 'METER', 'CM', 'MM', 'YARD',
  };

  static bool isMeasured(String? unit) =>
      unit != null && _measured.contains(unit.trim().toUpperCase());

  static String _q(double v, String? unit) =>
      '${Fmt.number(v)} ${unit ?? ''}'.trim();

  /// Satu barang bisa punya beberapa peringatan. Urut: bahaya, beli, cek;
  /// di dalamnya yang paling parah dulu.
  static List<StockAlert> analyze(
    Iterable<StockHealthRow> rows, {
    StockAlertSettings settings = const StockAlertSettings(),
  }) {
    final days = settings.days;
    final runningOutDays = settings.runningOutDays;
    final coverDays = settings.coverDays;
    final excessiveDays = settings.excessiveDays;
    final out = <StockAlert>[];
    for (final r in rows) {
      final perDay = r.sold > 0 ? r.sold / days : 0.0;
      final daysLeft = perDay > 0 ? r.stock / perDay : null;
      final target = [
        r.minStock * 2,
        perDay * coverDays,
      ].reduce((a, b) => a > b ? a : b);
      double? buy() {
        final need = target - r.stock;
        if (need <= 0) return null;
        return isMeasured(r.unit)
            ? (need * 10).ceil() / 10
            : need.ceilToDouble();
      }

      final rate = perDay > 0
          ? ' Laku ±${Fmt.number(_round(perDay))}/hari.'
          : '';

      if (r.stock < 0) {
        out.add(
          StockAlert(
            row: r,
            kind: StockAlertKind.negative,
            message:
                'Stok tercatat ${_q(r.stock, r.unit)}. Ada barang terjual yang '
                'belum dicatat masuk, atau stok opname terakhir salah. Hitung '
                'fisik lalu Stok Opname.$rate',
            suggestedBuy: buy(),
          ),
        );
      } else if (r.stock == 0 && r.sold > 0) {
        out.add(
          StockAlert(
            row: r,
            kind: StockAlertKind.outOfStock,
            message: 'Stok habis padahal masih laku.$rate',
            suggestedBuy: buy(),
          ),
        );
      } else if (r.minStock > 0 && r.stock <= r.minStock) {
        out.add(
          StockAlert(
            row: r,
            kind: StockAlertKind.low,
            message:
                'Sisa ${_q(r.stock, r.unit)} (min. ${Fmt.number(r.minStock)})'
                '${daysLeft == null ? '.' : ', habis ±${daysLeft.ceil()} hari lagi.'}',
            suggestedBuy: buy(),
          ),
        );
      } else if (daysLeft != null &&
          r.stock > 0 &&
          daysLeft <= runningOutDays) {
        out.add(
          StockAlert(
            row: r,
            kind: StockAlertKind.runningOut,
            message:
                'Sisa ${_q(r.stock, r.unit)}, habis ±${daysLeft.ceil()} hari '
                'lagi.$rate',
            suggestedBuy: buy(),
          ),
        );
      }

      if (!isMeasured(r.unit) && r.stock != r.stock.roundToDouble()) {
        out.add(
          StockAlert(
            row: r,
            kind: StockAlertKind.fractional,
            message:
                'Stok ${_q(r.stock, r.unit)} berupa pecahan, padahal satuannya '
                'tidak ditimbang. Kemungkinan salah ketik saat input/opname.',
          ),
        );
      }
      if (daysLeft != null && daysLeft > excessiveDays && r.stock >= 100) {
        out.add(
          StockAlert(
            row: r,
            kind: StockAlertKind.excessive,
            message:
                'Stok ${_q(r.stock, r.unit)} cukup untuk ±'
                '${Fmt.number((daysLeft / 30).round())} bulan. Kemungkinan salah '
                'ketik (kelebihan nol) — cek fisik.$rate',
          ),
        );
      }
      if (r.adjustedOut >= 5 &&
          r.adjustedOut >= 0.1 * (r.sold + r.stock.abs() + r.adjustedOut)) {
        out.add(
          StockAlert(
            row: r,
            kind: StockAlertKind.shrinkage,
            message:
                'Berkurang ${_q(r.adjustedOut, r.unit)} lewat barang keluar / '
                'opname dalam $days hari (terjual ${_q(r.sold, r.unit)}). Cek '
                'riwayat stok: rusak, hilang, atau salah catat?',
          ),
        );
      }
    }

    double severity(StockAlert a) => switch (a.kind) {
      StockAlertKind.negative => a.row.stock,
      StockAlertKind.outOfStock => -a.row.sold,
      StockAlertKind.low || StockAlertKind.runningOut => _daysLeft(a.row, days),
      StockAlertKind.shrinkage => -a.row.adjustedOut,
      _ => 0,
    };
    out.sort((a, b) {
      final level = a.kind.level.index.compareTo(b.kind.level.index);
      if (level != 0) return level;
      final s = severity(a).compareTo(severity(b));
      return s != 0 ? s : a.row.name.compareTo(b.row.name);
    });
    return out;
  }

  static double _daysLeft(StockHealthRow r, int days) =>
      r.sold > 0 ? r.stock / (r.sold / days) : double.maxFinite;

  static double _round(double v) =>
      v >= 10 ? v.roundToDouble() : (v * 10).round() / 10;
}
